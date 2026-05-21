function Set-ImageServicingBusyState {
    param([Parameter(Mandatory)][bool]$Busy)

    try {
        Set-AppStateValue -Key "IsImageServicingBusy" -Value $Busy
    } catch {}
}

function Sync-DriverControllerAfterMountChange {
    param(
        [string]$Reason = "MountChanged"
    )

    $didSomething = $false

    try {
        $cmdRefresh = Get-Command -Name "Refresh-DriverMountedList" -ErrorAction SilentlyContinue
        if ($cmdRefresh) {
            try {
                if ($cmdRefresh.ScriptBlock) {
                    & $cmdRefresh.ScriptBlock
                } else {
                    & $cmdRefresh.Name
                }
                $didSomething = $true
            } catch {
                try {
                    Write-Log -Level WARN -Message ("Images->Driver sync: Refresh-DriverMountedList failed: {0}" -f $_.Exception.Message)
                } catch {}
            }
        }
    } catch {}

    try {
        $cmdReload = Get-Command -Name "Request-DriversReload" -ErrorAction SilentlyContinue
        if ($cmdReload) {
            try {
                if ($cmdReload.Parameters.ContainsKey("Reason")) {
                    if ($cmdReload.ScriptBlock) {
                        & $cmdReload.ScriptBlock -Reason $Reason
                    } else {
                        & $cmdReload.Name -Reason $Reason
                    }
                }
                else {
                    if ($cmdReload.ScriptBlock) {
                        & $cmdReload.ScriptBlock
                    } else {
                        & $cmdReload.Name
                    }
                }
                $didSomething = $true
            } catch {
                try {
                    Write-Log -Level WARN -Message ("Images->Driver sync: Request-DriversReload failed: {0}" -f $_.Exception.Message)
                } catch {}
            }
        }
    } catch {}

    return $didSomething
}

function Clear-DriverSelectionForUnmountedMount {
    param([string]$MountDir)

    if ([string]::IsNullOrWhiteSpace($MountDir)) { return }

    try {
        $driverMount = Get-AppStateValue -Key "DriverMountDir" -Default $null
    } catch {
        $driverMount = $null
    }

    if ([string]::IsNullOrWhiteSpace($driverMount)) { return }

    try {
        $a = Normalize-PathText $driverMount
        $b = Normalize-PathText $MountDir
        if ($a -eq $b) {
            Set-AppStateValue -Key "DriverMountDir" -Value $null
        }
    } catch {}
}

function Update-MountUiFromState {
    if (-not $script:ctx) { return }

    $dir = Get-AppStateValue -Key "CurrentMountDir" -Default $null
    $ro  = [bool](Get-AppStateValue -Key "CurrentMountReadOnly" -Default $false)

    if ($script:ctx.TxtMountDir) {
        try { $script:ctx.TxtMountDir.Text = (Get-DisplayValue $dir) } catch {}
    }

    $hasSelectedIndex = $false
    try {
        if ($script:ctx.LstWimImages) {
            if ($script:ctx.LstWimImages.SelectedItems -and $script:ctx.LstWimImages.SelectedItems.Count -gt 0) {
                $hasSelectedIndex = $true
            } elseif ($script:ctx.LstWimImages.SelectedItem) {
                $hasSelectedIndex = $true
            }
        }
    } catch {
        $hasSelectedIndex = $false
    }

    $btnMount = $null
    try { $btnMount = $script:ctx.BtnMountSelected } catch {}
    if ($btnMount) {
        try { $btnMount.IsEnabled = ((-not $script:isBusy) -and $hasSelectedIndex) } catch {}
    }

    if (-not $script:isBusy) {
        $btnCommit  = $null
        $btnDiscard = $null

        try { $btnCommit  = $script:ctx.BtnUnmountMountedCommit  } catch {}
        try { $btnDiscard = $script:ctx.BtnUnmountMountedDiscard } catch {}

        if (-not $btnCommit)  { try { $btnCommit  = $script:ctx.BtnUnmountCommit  } catch {} }
        if (-not $btnDiscard) { try { $btnDiscard = $script:ctx.BtnUnmountDiscard } catch {} }

        if ($btnCommit)  { try { $btnCommit.IsEnabled  = ([bool]$dir -and (-not $ro)) } catch {} }
        if ($btnDiscard) { try { $btnDiscard.IsEnabled = ([bool]$dir) } catch {} }
    }
}

function Clear-MountState {
    try { Set-AppStateValue -Key "CurrentMountDir"       -Value $null } catch {}
    try { Set-AppStateValue -Key "CurrentMountMode"      -Value $null } catch {}
    try { Set-AppStateValue -Key "CurrentMountIndex"     -Value $null } catch {}
    try { Set-AppStateValue -Key "CurrentMountImagePath" -Value $null } catch {}
    try { Set-AppStateValue -Key "CurrentMountReadOnly"  -Value $null } catch {}
}

function Start-MountAsync {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    try {
        $mode = Get-ImagesViewMode
        if (-not $mode) { throw "Keine Ansicht ausgewählt." }

        $selectedItems = @(Get-SelectedWimItems)
        if ($selectedItems.Count -lt 1) { throw "Bitte zuerst mindestens einen Index auswählen." }

        $mountRequests = New-Object System.Collections.Generic.List[object]
        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }
            if ($item.PSObject.Properties.Match("Index").Count -eq 0) { continue }

            $itemIndex = $null
            try { $itemIndex = [int]$item.Index } catch { $itemIndex = $null }
            if ($null -eq $itemIndex) { continue }

            $itemPath = $null
            if ($item.PSObject.Properties.Match("ImagePath").Count -gt 0) {
                $itemPath = [string]$item.ImagePath
            }
            if ([string]::IsNullOrWhiteSpace([string]$itemPath)) {
                $itemPath = Get-ImagesPathForMode -Mode $mode
            }

            if ([string]::IsNullOrWhiteSpace([string]$itemPath)) {
                throw "ImageFile für Index $itemIndex nicht ermittelbar."
            }
            if (-not (Test-Path -LiteralPath $itemPath -PathType Leaf)) {
                throw "ImageFile nicht gefunden: $itemPath"
            }

            $fileName = $null
            try {
                if ($item.PSObject.Properties.Match("FileName").Count -gt 0) { $fileName = [string]$item.FileName }
            } catch {}
            if ([string]::IsNullOrWhiteSpace($fileName)) {
                $fileName = [System.IO.Path]::GetFileName($itemPath)
            }

            $mountRequests.Add([pscustomobject]@{
                ImagePath = [string]$itemPath
                Index     = [int]$itemIndex
                FileName  = [string]$fileName
            }) | Out-Null
        }

        $mountRequestArray = @($mountRequests.ToArray())
        if ($mountRequestArray.Count -lt 1) {
            throw "Die Auswahl enthält keine mountbaren Indexe."
        }

        try {
            $planText = Get-ImagesSelectedBatchPlanText -Items @($selectedItems)
            if ($script:ctx.TxtImagesBatchPlan) { $script:ctx.TxtImagesBatchPlan.Text = $planText }
        } catch {}

        $readOnly = $false
        if ($script:ctx.ChkReadOnly) {
            try { $readOnly = [bool]$script:ctx.ChkReadOnly.IsChecked } catch { $readOnly = $false }
        }

        $ctxLocal  = $script:ctx
        $setStatus = $script:ctx.SetStatus

        $fnSetBusy        = (Get-Item function:Set-ImagesBusy                          -ErrorAction Stop).ScriptBlock
        $fnUpdMountUi     = (Get-Item function:Update-MountUiFromState                 -ErrorAction Stop).ScriptBlock
        $fnRefreshPage    = (Get-Item function:Refresh-ImagesUI                        -ErrorAction Stop).ScriptBlock
        $fnRefMounted     = (Get-Item function:Refresh-MountedList                     -ErrorAction Stop).ScriptBlock
        $fnSetSvcBusy     = (Get-Item function:Set-ImageServicingBusyState             -ErrorAction Stop).ScriptBlock
        $fnSyncDriver     = (Get-Item function:Sync-DriverControllerAfterMountChange   -ErrorAction Stop).ScriptBlock
        $fnShowUiError    = (Get-Item function:Show-UiError                            -ErrorAction Stop).ScriptBlock

        $busyReason = if ($mountRequestArray.Count -gt 1) { "Mount läuft ({0} Indexe nacheinander)..." -f $mountRequestArray.Count } else { "Mount läuft..." }
        & $fnSetBusy -Busy $true -Reason $busyReason -Context $ctxLocal
        & $fnSetSvcBusy -Busy $true

        $coreBoot   = (Resolve-ProjectPath "Core\Bootstrap.psm1" -MustExist)
        $coreCfg    = (Resolve-ProjectPath "Core\Config.psm1"    -MustExist)
        $coreLog    = (Resolve-ProjectPath "Core\Logger.psm1"    -MustExist)
        $svcDism    = (Resolve-ProjectPath "Services\DismService.psm1"  -MustExist)
        $svcMount   = (Resolve-ProjectPath "Services\MountService.psm1" -MustExist)

        $safeBoot  = $coreBoot.Replace("'", "''")
        $safeCfg   = $coreCfg.Replace("'", "''")
        $safeLog   = $coreLog.Replace("'", "''")
        $safeDism  = $svcDism.Replace("'", "''")
        $safeMount = $svcMount.Replace("'", "''")

        $safeMode  = $mode.Replace("'", "''")
        $safeRO    = if ($readOnly) { '$true' } else { '$false' }
        $requestsJson = @($mountRequestArray) | ConvertTo-Json -Compress -Depth 6
        $requestsB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$requestsJson))

        $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$safeBoot'  -Force
Import-Module '$safeCfg'   -Force
Import-Module '$safeLog'   -Force
Import-Module '$safeDism'  -Force
Import-Module '$safeMount' -Force

function ConvertFrom-WorkerBase64Json {
    param([Parameter(Mandatory)][string]`$Base64)

    `$json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$Base64))
    if ([string]::IsNullOrWhiteSpace(`$json) -or `$json -eq 'null') {
        return @()
    }

    `$value = `$json | ConvertFrom-Json
    return @(`$value)
}

`$requests = @(ConvertFrom-WorkerBase64Json -Base64 '$requestsB64')
`$results = New-Object System.Collections.Generic.List[object]
`$mode = '$safeMode'
`$readOnly = $safeRO
`$position = 0

foreach (`$request in `$requests) {
    `$position++
    `$imagePath = [string]`$request.ImagePath
    `$index = [int]`$request.Index
    `$fileName = [string]`$request.FileName

    try {
        Write-Log -Level INFO -Message ("Images: Batch-Mount {0}/{1}: {2} Index {3}" -f `$position, @(`$requests).Count, `$imagePath, `$index)
        `$mountResult = Mount-WimImage -ImagePath `$imagePath -Index `$index -Mode `$mode -ReadOnly:`$readOnly

        `$results.Add([pscustomobject]@{
            Success   = `$true
            ImagePath = `$imagePath
            FileName  = `$fileName
            Index     = `$index
            Mode      = `$mode
            MountDir  = [string]`$mountResult.MountDir
            ReadOnly  = [bool]`$readOnly
            Error     = ''
        }) | Out-Null
    } catch {
        `$results.Add([pscustomobject]@{
            Success   = `$false
            ImagePath = `$imagePath
            FileName  = `$fileName
            Index     = `$index
            Mode      = `$mode
            MountDir  = ''
            ReadOnly  = [bool]`$readOnly
            Error     = `$_.Exception.Message
        }) | Out-Null
    }
}

return ,(`$results.ToArray())
"@

        $label = if ($mountRequestArray.Count -gt 1) { ("Mount:{0}:Batch_{1}" -f $mode, $mountRequestArray.Count) } else { ("Mount:{0}:Index_{1}" -f $mode, [int]$mountRequestArray[0].Index) }

        $onCompleted = {
            param($result)
            try {
                $items = @($result)
                if ($items.Count -eq 1 -and $items[0] -is [array]) { $items = @($items[0]) }

                $ok = @($items | Where-Object { $_ -and $_.PSObject.Properties.Match("Success").Count -gt 0 -and [bool]$_.Success })
                $failed = @($items | Where-Object { $_ -and $_.PSObject.Properties.Match("Success").Count -gt 0 -and -not [bool]$_.Success })

                $lastOk = if ($ok.Count -gt 0) { $ok[-1] } else { $null }
                if ($lastOk) {
                    $mountDir = [string]$lastOk.MountDir
                    try { Set-AppStateValue -Key "CurrentMountDir"       -Value $mountDir } catch {}
                    try { Set-AppStateValue -Key "CurrentMountMode"      -Value $mode } catch {}
                    try { Set-AppStateValue -Key "CurrentMountIndex"     -Value ([int]$lastOk.Index) } catch {}
                    try { Set-AppStateValue -Key "CurrentMountImagePath" -Value ([string]$lastOk.ImagePath) } catch {}
                    try { Set-AppStateValue -Key "CurrentMountReadOnly"  -Value $readOnly } catch {}
                }

                & $fnUpdMountUi

                $statusText = "Mount fertig: {0} OK, {1} Fehler" -f $ok.Count, $failed.Count
                if ($setStatus) { & $setStatus $statusText }

                if ($failed.Count -gt 0) {
                    $lines = @($failed | ForEach-Object {
                        "{0} Index {1}: {2}" -f [string]$_.FileName, [int]$_.Index, [string]$_.Error
                    })
                    & $fnShowUiError -Message ("Nicht alle ausgewählten Indexe konnten gemountet werden.`n`n{0}" -f ($lines -join "`n"))
                }
            } finally {
                & $fnSetSvcBusy -Busy $false
                & $fnSetBusy -Busy $false -Context $ctxLocal

                try { & $fnRefreshPage } catch {}
                try {
                    $selectMount = Get-AppStateValue -Key "CurrentMountDir" -Default $null
                    & $fnRefMounted -SelectMountDir $selectMount
                } catch {}
                try { & $fnSyncDriver -Reason "Mount success" } catch {}
            }
        }.GetNewClosure()

        $onError = {
            param($ex)
            try { & $fnShowUiError -Message $ex.Message }
            finally {
                & $fnSetSvcBusy -Busy $false
                & $fnSetBusy -Busy $false -Context $ctxLocal
                if ($setStatus) { & $setStatus "Ready" }
            }
        }.GetNewClosure()

        Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label $label
    } catch {
        try { Set-ImageServicingBusyState -Busy $false } catch {}
        try { Set-ImagesBusy -Busy $false } catch {}
        Show-UiError -Message $_.Exception.Message
    }
}

function Invoke-UnmountMounted {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][ValidateSet("Commit","Discard")] [string]$Mode
    )

    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    try {
        $fnSetBusy         = (Get-Item function:Set-ImagesBusy                          -ErrorAction Stop).ScriptBlock
        $fnUpdBtns         = (Get-Item function:Update-MountedButtons                   -ErrorAction Stop).ScriptBlock
        $fnUpdMountUi      = (Get-Item function:Update-MountUiFromState                 -ErrorAction Stop).ScriptBlock
        $fnRefreshPage     = (Get-Item function:Refresh-ImagesUI                        -ErrorAction Stop).ScriptBlock
        $fnClear           = (Get-Item function:Clear-MountState                        -ErrorAction Stop).ScriptBlock
        $fnRefMounted      = (Get-Item function:Refresh-MountedList                     -ErrorAction Stop).ScriptBlock
        $fnNorm            = (Get-Item function:Normalize-PathText                      -ErrorAction Stop).ScriptBlock
        $fnSetSvcBusy      = (Get-Item function:Set-ImageServicingBusyState             -ErrorAction Stop).ScriptBlock
        $fnClearDriverSel  = (Get-Item function:Clear-DriverSelectionForUnmountedMount  -ErrorAction Stop).ScriptBlock
        $fnSyncDriver      = (Get-Item function:Sync-DriverControllerAfterMountChange   -ErrorAction Stop).ScriptBlock
        $fnShowUiError     = (Get-Item function:Show-UiError                            -ErrorAction Stop).ScriptBlock

        $MountDir = (& $fnNorm $MountDir)
        if ([string]::IsNullOrWhiteSpace($MountDir)) { throw "MountDir ist leer." }

        $ctxLocal  = $script:ctx
        $setStatus = $script:ctx.SetStatus

        & $fnSetBusy -Busy $true -Reason ("Unmount ({0})..." -f $Mode) -Context $ctxLocal
        & $fnSetSvcBusy -Busy $true

        $coreBoot   = (Resolve-ProjectPath "Core\Bootstrap.psm1" -MustExist)
        $coreCfg    = (Resolve-ProjectPath "Core\Config.psm1"    -MustExist)
        $coreLog    = (Resolve-ProjectPath "Core\Logger.psm1"    -MustExist)
        $svcDism    = (Resolve-ProjectPath "Services\DismService.psm1"  -MustExist)
        $svcMount   = (Resolve-ProjectPath "Services\MountService.psm1" -MustExist)

        $safeBoot  = $coreBoot.Replace("'", "''")
        $safeCfg   = $coreCfg.Replace("'", "''")
        $safeLog   = $coreLog.Replace("'", "''")
        $safeDism  = $svcDism.Replace("'", "''")
        $safeMount = $svcMount.Replace("'", "''")

        $safeDir = $MountDir.Replace("'", "''")
        $preCommitDelaySec = 0
        if ($Mode -eq "Commit") {
            $lastRefreshRaw = $null
            try { $lastRefreshRaw = Get-AppStateValue -Key "LastMountedWimRefreshAtUtc" -Default $null } catch { $lastRefreshRaw = $null }
            $quietPeriodSec = 15
            try { $quietPeriodSec = [int](Get-ConfigValue -Key "MountedWimRefreshQuietPeriodSec" -Default 15) } catch { $quietPeriodSec = 15 }
            if ($quietPeriodSec -lt 0) { $quietPeriodSec = 0 }

            if (-not [string]::IsNullOrWhiteSpace([string]$lastRefreshRaw) -and $quietPeriodSec -gt 0) {
                $lastRefreshUtc = [DateTime]::MinValue
                if ([DateTime]::TryParse([string]$lastRefreshRaw, [ref]$lastRefreshUtc)) {
                    $elapsedSec = [Math]::Max(0, [int]([DateTime]::UtcNow - $lastRefreshUtc.ToUniversalTime()).TotalSeconds)
                    if ($elapsedSec -lt $quietPeriodSec) {
                        $preCommitDelaySec = $quietPeriodSec - $elapsedSec
                    }
                }
            }
        }

        $commit  = if ($Mode -eq "Commit") { '$true' } else { '$false' }
        $discard = if ($Mode -eq "Discard") { '$true' } else { '$false' }
        $safePreCommitDelaySec = [int]$preCommitDelaySec

        $code = @"
`$ErrorActionPreference = 'Stop'
`$preCommitDelaySec = $safePreCommitDelaySec
if ($commit -and `$preCommitDelaySec -gt 0) {
    Start-Sleep -Seconds `$preCommitDelaySec
}
Import-Module '$safeBoot'  -Force
Import-Module '$safeCfg'   -Force
Import-Module '$safeLog'   -Force
Import-Module '$safeDism'  -Force
Import-Module '$safeMount' -Force

Unmount-WimImage -MountDir '$safeDir' -Commit:$commit -Discard:$discard
"@

        $label = ("Unmount:{0}" -f $Mode)

        $onCompleted = {
            param($result)
            try {
                $cur = Get-AppStateValue -Key "CurrentMountDir" -Default $null
                if ($cur) {
                    $nCur = (& $fnNorm $cur)
                    $nDir = (& $fnNorm $MountDir)
                    if ($nCur -eq $nDir) {
                        try { & $fnClear } catch {}
                    }
                }

                try { & $fnClearDriverSel -MountDir $MountDir } catch {}

                & $fnUpdMountUi
                if ($setStatus) { & $setStatus ("Unmount OK: {0}" -f $MountDir) }
            } finally {
                & $fnSetSvcBusy -Busy $false
                & $fnSetBusy -Busy $false -Context $ctxLocal

                try { & $fnRefreshPage } catch {}
                try { & $fnRefMounted } catch {}
                try { & $fnSyncDriver -Reason ("Unmount {0}" -f $Mode) } catch {}
                try { & $fnUpdBtns } catch {}
            }
        }.GetNewClosure()

        $onError = {
            param($ex)
            try { & $fnShowUiError -Message $ex.Message }
            finally {
                & $fnSetSvcBusy -Busy $false
                & $fnSetBusy -Busy $false -Context $ctxLocal
                if ($setStatus) { & $setStatus "Ready" }
            }
        }.GetNewClosure()

        Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label $label
    } catch {
        try { Set-ImageServicingBusyState -Busy $false } catch {}
        try { Set-ImagesBusy -Busy $false } catch {}
        Show-UiError -Message $_.Exception.Message
    }
}

function Unmount-CurrentCommit {
    if ($script:isBusy) { return }
    $dir = Get-AppStateValue -Key "CurrentMountDir" -Default $null
    $ro  = [bool](Get-AppStateValue -Key "CurrentMountReadOnly" -Default $false)
    if (-not $dir) { Show-UiError -Message "Kein CurrentMountDir gesetzt."; return }
    if ($ro) { Show-UiError -Message "Commit nicht möglich (Current Mount ist ReadOnly)." ; return }
    Invoke-UnmountMounted -MountDir $dir -Mode "Commit"
}

function Unmount-CurrentDiscard {
    if ($script:isBusy) { return }
    $dir = Get-AppStateValue -Key "CurrentMountDir" -Default $null
    if (-not $dir) { Show-UiError -Message "Kein CurrentMountDir gesetzt."; return }
    Invoke-UnmountMounted -MountDir $dir -Mode "Discard"
}

function Unmount-MountedSelectedDiscard {
    if ($script:isBusy) { return }
    $dir = Get-SelectedMountedDir
    if (-not $dir) { Show-UiError -Message "Bitte ein Mounted Image auswählen."; return }
    Invoke-UnmountMounted -MountDir $dir -Mode "Discard"
}

function Unmount-MountedSelectedCommit {
    if ($script:isBusy) { return }
    if (-not $script:ctx -or -not $script:ctx.LstMountedWims) { return }
    $sel = $script:ctx.LstMountedWims.SelectedItem
    if (-not $sel) { Show-UiError -Message "Bitte ein Mounted Image auswählen."; return }
    if (-not (Test-MountedWritable -MountedItem $sel)) {
        $msg = "Commit ist für diesen Mount nicht möglich."
        try {
            $hint = Get-MountedSelectionHint -MountedItem $sel
            if (-not [string]::IsNullOrWhiteSpace($hint)) { $msg = $hint }
        } catch {}
        Show-UiError -Message $msg
        return
    }
    $dir = Get-SelectedMountedDir
    if (-not $dir) { Show-UiError -Message "MountDir nicht ermittelbar."; return }
    Invoke-UnmountMounted -MountDir $dir -Mode "Commit"
}
