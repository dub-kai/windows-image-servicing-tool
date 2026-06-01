function Resolve-DriverMountDir {
    param(
        [hashtable]$Context = $null
    )

    $ctxLocal = if ($null -ne $Context) { $Context } else { $script:ctx }
    if (-not $ctxLocal) { return $null }

    $cmb = $ctxLocal["CmbDriverMount"]
    if (-not $cmb) { return $null }

    $selected = $null
    try { $selected = [string]$cmb.SelectedItem } catch { $selected = $null }

    if (-not [string]::IsNullOrWhiteSpace($selected)) {
        return $selected
    }

    $wanted = $null
    try { $wanted = Get-AppStateValue -Key "DriverMountDir" -Default $null } catch { $wanted = $null }

    if (-not [string]::IsNullOrWhiteSpace($wanted)) {
        try {
            $items = @($cmb.ItemsSource)
            if ($items -contains $wanted) {
                return $wanted
            }
        } catch {}
    }

    try {
        $items = @($cmb.ItemsSource)
        if ($items.Count -gt 0) {
            return [string]$items[0]
        }
    } catch {}

    return $null
}

function Test-DriverPageVisible {
    param(
        [hashtable]$Context = $null
    )

    $ctxLocal = if ($null -ne $Context) { $Context } else { $script:ctx }
    if (-not $ctxLocal) { return $false }

    $page = $ctxLocal["DriverPage"]
    if (-not $page) { return $false }

    try {
        return [bool]$page.IsVisible
    } catch {
        return $false
    }
}

function Refresh-DriverMountedList {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    $fnBusy        = (Get-Item function:Set-DriverBusy             -ErrorAction Stop).ScriptBlock
    $fnRefresh     = (Get-Item function:Refresh-DriverUI           -ErrorAction Stop).ScriptBlock
    $fnErr         = (Get-Item function:Show-UiError               -ErrorAction Stop).ScriptBlock
    $fnClear       = (Get-Item function:Clear-DriversList          -ErrorAction Stop).ScriptBlock
    $fnBusyChk     = (Get-Item function:Get-ImageServicingBusy     -ErrorAction Stop).ScriptBlock
    $fnMountOk     = (Get-Item function:Test-DriverMountUsable     -ErrorAction Stop).ScriptBlock
    $fnLoad        = (Get-Item function:Load-DriversAsync          -ErrorAction Stop).ScriptBlock
    $fnResolveMnt  = (Get-Item function:Resolve-DriverMountDir     -ErrorAction Stop).ScriptBlock
    $fnPageVisible = (Get-Item function:Test-DriverPageVisible     -ErrorAction Stop).ScriptBlock

    $ctxLocal  = $script:ctx
    $setStatus = $ctxLocal["SetStatus"]

    & $fnBusy -Busy $true -Reason "Mounted WIMs werden geladen..." -Context $ctxLocal

    $dismMod    = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist).Replace("'", "''")
    $mountedMod = (Resolve-ProjectPath "Services\MountedWimService.psm1" -MustExist).Replace("'", "''")

    $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$dismMod' -Force
Import-Module '$mountedMod' -Force
Get-MountedWimList
"@

    $onCompleted = {
        param($resArr)

        $selectedMountAfterRefresh = $null
        $mountDirs = @()
        $shouldAutoLoad = $false
        $autoLoadMount = $null
        $pageVisible = $false

        try {
            $items = @($resArr)

            foreach ($it in $items) {
                if ($it -and $it.PSObject.Properties.Match("MountDir").Count -gt 0) {
                    $md = [string]$it.MountDir
                    if (-not [string]::IsNullOrWhiteSpace($md)) {
                        $mountDirs += $md
                    }
                }
            }

            $cmb = $ctxLocal["CmbDriverMount"]
            if ($cmb) {
                $script:suppressMountSelectionReload = $true
                try {
                    $cmb.ItemsSource = $null
                    $cmb.ItemsSource = $mountDirs

                    $wanted = $null
                    try { $wanted = Get-AppStateValue -Key "DriverMountDir" -Default $null } catch {}

                    if ($wanted -and ($mountDirs -contains $wanted)) {
                        $cmb.SelectedItem = $wanted
                    }
                    elseif ($mountDirs.Count -gt 0) {
                        $cmb.SelectedIndex = 0
                    }
                    else {
                        $cmb.SelectedIndex = -1
                    }

                    try {
                        $selectedMountAfterRefresh = [string]$cmb.SelectedItem
                    } catch {
                        $selectedMountAfterRefresh = $null
                    }
                }
                finally {
                    $script:suppressMountSelectionReload = $false
                }
            }

            if ([string]::IsNullOrWhiteSpace($selectedMountAfterRefresh)) {
                try {
                    $selectedMountAfterRefresh = & $fnResolveMnt -Context $ctxLocal
                } catch {
                    $selectedMountAfterRefresh = $null
                }
            }

            try {
                Set-AppStateValue -Key "DriverMountDir" -Value $selectedMountAfterRefresh
            } catch {}

            if ($mountDirs.Count -lt 1) {
                try {
                    & $fnClear -Context $ctxLocal -StatusText (Get-UiString -Key 'DriverCountZero')
                } catch {}
            }
            else {
                if ($setStatus) {
                    try { & $setStatus ("Driver: Mounts={0}" -f $mountDirs.Count) } catch {}
                }
            }

            try {
                $pageVisible = (& $fnPageVisible -Context $ctxLocal)
            } catch {
                $pageVisible = $false
            }
        }
        finally {
            & $fnBusy -Busy $false -Context $ctxLocal
            try { & $fnRefresh } catch {}

            if ($mountDirs.Count -lt 1) {
                try {
                    Write-Log -Level INFO -Message "Driver: AutoLoad skipped (keine Mounts vorhanden)"
                } catch {}
            }
            elseif (-not $pageVisible) {
                try {
                    Write-Log -Level INFO -Message "Driver: AutoLoad skipped (Driver-Seite nicht sichtbar)"
                } catch {}
            }
            elseif (& $fnBusyChk) {
                $script:reloadPending = $true
                try {
                    Write-Log -Level INFO -Message "Driver: AutoLoad deferred (Image servicing busy)"
                } catch {}
            }
            else {
                if ([string]::IsNullOrWhiteSpace($selectedMountAfterRefresh)) {
                    try {
                        $selectedMountAfterRefresh = & $fnResolveMnt -Context $ctxLocal
                    } catch {
                        $selectedMountAfterRefresh = $null
                    }
                }

                if (& $fnMountOk $selectedMountAfterRefresh) {
                    $shouldAutoLoad = $true
                    $autoLoadMount = $selectedMountAfterRefresh
                    try {
                        Write-Log -Level INFO -Message ("Driver: AutoLoad start for MountDir={0}" -f $autoLoadMount)
                    } catch {}
                }
                else {
                    try {
                        Write-Log -Level INFO -Message ("Driver: AutoLoad skipped (Mount ungueltig): {0}" -f $selectedMountAfterRefresh)
                    } catch {}
                }
            }
        }

        if ($shouldAutoLoad) {
            try {
                & $fnLoad
            } catch {
                try {
                    Write-Log -Level WARN -Message ("Driver: AutoLoad failed to start: {0}" -f $_.Exception.Message)
                } catch {}
            }
        }
    }.GetNewClosure()

    $onError = {
        param($ex)
        try { & $fnErr -Message $ex.Message } catch {}
        finally {
            & $fnBusy -Busy $false -Context $ctxLocal
            if ($setStatus) { try { & $setStatus "Ready" } catch {} }
        }
    }.GetNewClosure()

    Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label "Driver:MountedWims"
}
