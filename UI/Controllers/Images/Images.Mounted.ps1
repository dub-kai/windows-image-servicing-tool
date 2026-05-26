function Test-MountedWritable {
    param($MountedItem)
    if (-not $MountedItem) { return $false }
    if ($MountedItem.PSObject.Properties.Match("CanCommit").Count -gt 0) {
        try {
            if (-not [bool]$MountedItem.CanCommit) { return $false }
        } catch {
            return $false
        }
    }
    if ($MountedItem -and $MountedItem.PSObject.Properties.Match("Status").Count -gt 0) {
        $status = [string]$MountedItem.Status
        if (-not [string]::IsNullOrWhiteSpace($status)) {
            $s = $status.ToLowerInvariant()
            if ($s -notmatch '^(ok|mounted)$') { return $false }
        }
    }
    if (-not $MountedItem) { return $false }
    if ($MountedItem.PSObject.Properties.Match("ReadWrite").Count -eq 0) { return $false }
    $rw = [string]$MountedItem.ReadWrite
    if ([string]::IsNullOrWhiteSpace($rw)) { return $false }

    $x = $rw.ToLowerInvariant()
    if ($x -match "readonly") { return $false }
    if ($x -match "read\s*only") { return $false }
    if ($x -match "^no$") { return $false }
    if ($x -match "^false$") { return $false }
    if ($x -match "^yes$") { return $true }
    if ($x -match "^true$") { return $true }
    if ($x -match "read/write") { return $true }
    if ($x -match "readwrite") { return $true }
    if ($x -match "rw") { return $true }
    return $false
}

function Test-MountedDiscardAllowed {
    param($MountedItem)

    if (-not $MountedItem) { return $false }

    if ($MountedItem.PSObject.Properties.Match("CanDiscard").Count -gt 0) {
        try { return [bool]$MountedItem.CanDiscard } catch { return $false }
    }

    return $true
}

function Get-MountedSelectionHint {
    param($MountedItem)

    if (-not $MountedItem) {
        return 'Tipp: Auswahl anklicken, dann Unmount.'
    }

    $health = '-'
    $hint = $null
    $action = $null
    $capability = $null
    $guidance = $null
    $mountDir = $null

    try {
        if ($MountedItem.PSObject.Properties.Match("Health").Count -gt 0) { $health = [string]$MountedItem.Health }
        if ($MountedItem.PSObject.Properties.Match("HealthHint").Count -gt 0) { $hint = [string]$MountedItem.HealthHint }
        if ($MountedItem.PSObject.Properties.Match("RecommendedAction").Count -gt 0) { $action = [string]$MountedItem.RecommendedAction }
        if ($MountedItem.PSObject.Properties.Match("MountCapability").Count -gt 0) { $capability = [string]$MountedItem.MountCapability }
        if ($MountedItem.PSObject.Properties.Match("MountGuidance").Count -gt 0) { $guidance = [string]$MountedItem.MountGuidance }
        if ($MountedItem.PSObject.Properties.Match("MountDir").Count -gt 0) { $mountDir = [string]$MountedItem.MountDir }
    } catch {}

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($mountDir)) { [void]$parts.Add($mountDir) }
    if (-not [string]::IsNullOrWhiteSpace($health)) { [void]$parts.Add(("Zustand: {0}" -f $health)) }
    if (-not [string]::IsNullOrWhiteSpace($capability)) { [void]$parts.Add(("Eignung: {0}" -f $capability)) }
    if (-not [string]::IsNullOrWhiteSpace($guidance)) { [void]$parts.Add($guidance) }
    if (-not [string]::IsNullOrWhiteSpace($hint)) { [void]$parts.Add($hint) }
    if (-not [string]::IsNullOrWhiteSpace($action)) { [void]$parts.Add(("Empfohlen: {0}" -f $action)) }

    if ($parts.Count -lt 1) { return 'Tipp: Auswahl anklicken, dann Unmount.' }
    return ($parts -join ' | ')
}

function Get-SelectedMountedItems {
    if (-not $script:ctx -or -not $script:ctx.LstMountedWims) { return @() }

    $items = @()
    try {
        if ($script:ctx.LstMountedWims.SelectedItems) {
            foreach ($item in $script:ctx.LstMountedWims.SelectedItems) {
                if ($null -ne $item) { $items += $item }
            }
        }
    } catch {
        $items = @()
    }

    if ($items.Count -eq 0) {
        try {
            if ($script:ctx.LstMountedWims.SelectedItem) {
                $items = @($script:ctx.LstMountedWims.SelectedItem)
            }
        } catch {}
    }

    return @($items)
}

function Get-MountedBatchSelectionHint {
    param([object[]]$Items = @())

    $items = @($Items | Where-Object { $null -ne $_ })
    if ($items.Count -lt 1) { return 'Tipp: Auswahl anklicken, dann Unmount.' }

    if ($items.Count -eq 1) {
        return (Get-MountedSelectionHint -MountedItem $items[0])
    }

    $commit = @($items | Where-Object { Test-MountedWritable -MountedItem $_ })
    $discard = @($items | Where-Object { Test-MountedDiscardAllowed -MountedItem $_ })
    return ("Mehrfachauswahl: {0} Mounts | Commit möglich: {1} | Discard/Bereinigen möglich: {2}. Ablauf ist nacheinander." -f $items.Count, $commit.Count, $discard.Count)
}

function Get-MountedHealthSummaryText {
    param([object[]]$Items = @())

    $flatItems = @()
    foreach ($raw in @($Items)) {
        if ($null -eq $raw) { continue }
        if ($raw -is [System.Collections.IEnumerable] -and -not ($raw -is [string]) -and -not ($raw -is [System.Management.Automation.PSCustomObject])) {
            foreach ($entry in $raw) {
                if ($null -ne $entry) { $flatItems += $entry }
            }
        } else {
            $flatItems += $raw
        }
    }

    if ($flatItems.Count -lt 1) {
        return "Mount-Status: Keine gemounteten Images gefunden."
    }

    $ok = 0
    $problem = 0
    $registryOnly = 0
    $partial = 0
    $commit = 0
    $discard = 0
    $readOnly = 0
    $readWrite = 0
    $integratable = 0
    $bootLike = 0

    foreach ($item in $flatItems) {
        $health = ''
        $rw = ''
        try { if ($item.PSObject.Properties.Match("Health").Count -gt 0) { $health = [string]$item.Health } } catch {}
        try { if ($item.PSObject.Properties.Match("ReadWrite").Count -gt 0) { $rw = [string]$item.ReadWrite } } catch {}
        try { if ($item.PSObject.Properties.Match("CanIntegrateUpdates").Count -gt 0 -and [bool]$item.CanIntegrateUpdates) { $integratable++ } } catch {}
        try { if ($item.PSObject.Properties.Match("MountKind").Count -gt 0 -and [string]$item.MountKind -match 'Boot|WinPE') { $bootLike++ } } catch {}
        try { if ($item.PSObject.Properties.Match("RegistryOnly").Count -gt 0 -and [bool]$item.RegistryOnly) { $registryOnly++ } } catch {}
        try { if (Test-MountedWritable -MountedItem $item) { $commit++ } } catch {}
        try { if (Test-MountedDiscardAllowed -MountedItem $item) { $discard++ } } catch {}

        if ($health -match '^OK$') { $ok++ } else { $problem++ }
        if ($health -match 'Teilweise') { $partial++ }

        $rwLower = $rw.ToLowerInvariant()
        if ($rwLower -match 'readonly|read\s*only|^no$|^false$') {
            $readOnly++
        } elseif ($rwLower -match 'read/write|readwrite|rw|^yes$|^true$') {
            $readWrite++
        }
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add(("Mounts: {0}" -f $flatItems.Count)) | Out-Null
    $parts.Add(("OK: {0}" -f $ok)) | Out-Null
    $parts.Add(("Problem: {0}" -f $problem)) | Out-Null
    $parts.Add(("Commit möglich: {0}" -f $commit)) | Out-Null
    $parts.Add(("Discard möglich: {0}" -f $discard)) | Out-Null
    $parts.Add(("Update-Ziele: {0}" -f $integratable)) | Out-Null
    if ($readWrite -gt 0 -or $readOnly -gt 0) { $parts.Add(("RW/RO: {0}/{1}" -f $readWrite, $readOnly)) | Out-Null }
    if ($bootLike -gt 0) { $parts.Add(("Boot/WinPE: {0}" -f $bootLike)) | Out-Null }
    if ($partial -gt 0) { $parts.Add(("Teilweise ausgehängt: {0}" -f $partial)) | Out-Null }
    if ($registryOnly -gt 0) { $parts.Add(("Registry-Reste: {0}" -f $registryOnly)) | Out-Null }

    $tail = if ($problem -gt 0) {
        "Bitte betroffene Einträge markieren. Das Tool zeigt dir dann die empfohlene Aktion."
    } else {
        "Alle gelisteten Mounts wirken gesund."
    }

    return ("Mount-Status: {0}. {1}" -f ($parts.ToArray() -join " | "), $tail)
}

function Update-MountedHealthSummary {
    param([object[]]$Items = $null)

    if (-not $script:ctx -or -not $script:ctx.TxtMountedHealthSummary) { return }

    if ($null -eq $Items) {
        try { $Items = @($script:ctx.LstMountedWims.ItemsSource | Where-Object { $null -ne $_ }) } catch { $Items = @() }
        if (@($Items | Where-Object { $null -ne $_ }).Count -lt 1 -and $script:ctx.LstMountedWims) {
            try { $Items = @($script:ctx.LstMountedWims.Items) } catch { $Items = @() }
        }
    }

    try {
        $script:ctx.TxtMountedHealthSummary.Text = Get-MountedHealthSummaryText -Items @($Items)
    } catch {}
}

function Update-MountedButtons {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    $hasSel = $false
    $canCommit = $false
    $canDiscard = $false
    $selected = $null
    $selectedItems = @(Get-SelectedMountedItems)

    if ($selectedItems.Count -gt 0) {
        $hasSel = $true
        $selected = $selectedItems[0]
        $canCommit = (@($selectedItems | Where-Object { Test-MountedWritable -MountedItem $_ }).Count -gt 0)
        $canDiscard = (@($selectedItems | Where-Object { Test-MountedDiscardAllowed -MountedItem $_ }).Count -gt 0)
    }

    if ($script:ctx.BtnUnmountMountedDiscard) {
        try {
            $script:ctx.BtnUnmountMountedDiscard.IsEnabled = ($hasSel -and $canDiscard)
            $recommendedAction = ''
            if ($selected -and $selected.PSObject.Properties.Match("RecommendedAction").Count -gt 0) {
                $recommendedAction = [string]$selected.RecommendedAction
            }
            if ($selectedItems.Count -gt 1) {
                $script:ctx.BtnUnmountMountedDiscard.Content = 'Auswahl Discard'
            } elseif ($recommendedAction -match 'bereinig|Ohne Commit') {
                $script:ctx.BtnUnmountMountedDiscard.Content = 'Mount bereinigen'
            } else {
                $script:ctx.BtnUnmountMountedDiscard.Content = 'Unmount (Discard)'
            }
        } catch {}
    }
    if ($script:ctx.BtnUnmountMountedCommit)  {
        try {
            $script:ctx.BtnUnmountMountedCommit.IsEnabled = ($hasSel -and $canCommit)
            $script:ctx.BtnUnmountMountedCommit.Content = if ($selectedItems.Count -gt 1) { 'Auswahl Commit' } else { 'Unmount (Commit)' }
        } catch {}
    }
    if ($script:ctx.BtnRepairMounts) { try { $script:ctx.BtnRepairMounts.IsEnabled = $true } catch {} }
    if ($script:ctx.MiMountedCommit)  { try { $script:ctx.MiMountedCommit.IsEnabled = ($hasSel -and $canCommit) } catch {} }
    if ($script:ctx.MiMountedDiscard) { try { $script:ctx.MiMountedDiscard.IsEnabled = ($hasSel -and $canDiscard) } catch {} }
    if ($script:ctx.MiMountedCopyPath) { try { $script:ctx.MiMountedCopyPath.IsEnabled = $hasSel } catch {} }
    if ($script:ctx.MiMountedRefresh) { try { $script:ctx.MiMountedRefresh.IsEnabled = $true } catch {} }
    if ($script:ctx.MiMountedRepair) { try { $script:ctx.MiMountedRepair.IsEnabled = $true } catch {} }
    try { Update-MountedHealthSummary } catch {}
    if ($script:ctx.TxtMountedHint) { try { $script:ctx.TxtMountedHint.Text = (Get-MountedBatchSelectionHint -Items $selectedItems) } catch {} }
}

function Get-MountRepairProblemItems {
    if (-not $script:ctx -or -not $script:ctx.LstMountedWims) { return @() }

    $items = @()
    try { $items = @($script:ctx.LstMountedWims.ItemsSource) } catch { $items = @() }
    if ($items.Count -lt 1) { return @() }

    return @($items | Where-Object {
        $registryOnly = $false
        $health = ''
        $action = ''
        try { $registryOnly = [bool]$_.RegistryOnly } catch {}
        try { $health = [string]$_.Health } catch {}
        try { $action = [string]$_.RecommendedAction } catch {}

        $registryOnly -or
        ($health -and $health -notmatch '^OK$') -or
        ($action -match 'Cleanup|bereinig|Ohne Commit')
    })
}

function Start-MountRepairAssistant {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    $problemItems = @(Get-MountRepairProblemItems)
    if ($problemItems.Count -lt 1) {
        Show-UiInfo -Title 'Mount-Reparatur' -Message 'Aktuell sehe ich keine problematischen Mounts. Wenn trotzdem etwas hängt, bitte erst die Mount-Liste aktualisieren.'
        return
    }

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
    $mountText = (($problemItems | Select-Object -First 6 | ForEach-Object { [string]$_.MountDir }) -join "`r`n")
    if ($problemItems.Count -gt 6) { $mountText += "`r`n..." }

    $message = "Es wurden problematische Mount-Einträge gefunden:`r`n`r`n$mountText`r`n`r`nSoll DISM /Cleanup-Wim jetzt ausgeführt werden? Das bereinigt hängende Mount-Registry-Einträge, führt aber keinen Commit aus."
    $answer = [System.Windows.MessageBox]::Show(
        $message,
        'Mount-Reparatur',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $ctxLocal = $script:ctx
    $setStatus = $script:ctx.SetStatus
    $fnSetBusy = (Get-Item function:Set-ImagesBusy -ErrorAction Stop).ScriptBlock
    $fnRefresh = (Get-Item function:Refresh-MountedList -ErrorAction Stop).ScriptBlock
    $fnShowUiError = (Get-Item function:Show-UiError -ErrorAction Stop).ScriptBlock

    & $fnSetBusy -Busy $true -Reason 'Mount-Reparatur läuft...' -Context $ctxLocal

    $projectRoot = (Get-ProjectRoot).Replace("'", "''")
    $coreBoot = (Resolve-ProjectPath "Core\Bootstrap.psm1" -MustExist).Replace("'", "''")
    $coreCfg = (Resolve-ProjectPath "Core\Config.psm1" -MustExist).Replace("'", "''")
    $coreLog = (Resolve-ProjectPath "Core\Logger.psm1" -MustExist).Replace("'", "''")
    $svcDism = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist).Replace("'", "''")
    $svcMount = (Resolve-ProjectPath "Services\MountService.psm1" -MustExist).Replace("'", "''")
    $svcMounted = (Resolve-ProjectPath "Services\MountedWimService.psm1" -MustExist).Replace("'", "''")

    $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$coreBoot' -Force -DisableNameChecking
Set-ProjectRoot -Path '$projectRoot' | Out-Null
Import-Module '$coreCfg' -Force -DisableNameChecking
Import-Module '$coreLog' -Force -DisableNameChecking
Import-Module '$svcDism' -Force -DisableNameChecking
Import-Module '$svcMount' -Force -DisableNameChecking
Import-Module '$svcMounted' -Force -DisableNameChecking

Repair-WimMountRegistry -TimeoutSec 900 | Out-Null
`$mounts = @(Get-MountedWimList)
[pscustomobject]@{
    Remaining = @(`$mounts).Count
}
"@

    Start-UiTask -Work ([scriptblock]::Create($code)) -Label 'MountRepair:CleanupWim' -OnCompleted {
        param($result)
        try {
            $item = @($result) | Select-Object -First 1
            $remaining = if ($item) { [int]$item.Remaining } else { 0 }
            if ($setStatus) { & $setStatus ("Mount-Reparatur fertig. Einträge danach: {0}" -f $remaining) }
            Show-UiInfo -Title 'Mount-Reparatur' -Message ("DISM /Cleanup-Wim wurde ausgeführt.`r`nVerbleibende Mount-Einträge: {0}" -f $remaining)
        } finally {
            & $fnSetBusy -Busy $false -Context $ctxLocal
            try { & $fnRefresh } catch {}
        }
    } -OnError {
        param($ex)
        try { & $fnShowUiError -Title 'Mount-Reparatur' -Message $ex.Message }
        finally {
            & $fnSetBusy -Busy $false -Context $ctxLocal
            try { & $fnRefresh } catch {}
            if ($setStatus) { & $setStatus 'Ready' }
        }
    }
}

function Get-SelectedMountedDir {
    if (-not $script:ctx -or -not $script:ctx.LstMountedWims) { return $null }

    $sel = $null
    try { $sel = $script:ctx.LstMountedWims.SelectedItem } catch { $sel = $null }
    if ($sel -and $sel.PSObject.Properties.Match("MountDir").Count -gt 0) {
        $d = [string]$sel.MountDir
        if (-not [string]::IsNullOrWhiteSpace($d)) { return (Normalize-PathText $d) }
    }

    $sv = $null
    try { $sv = $script:ctx.LstMountedWims.SelectedValue } catch { $sv = $null }
    if ($sv -is [string] -and -not [string]::IsNullOrWhiteSpace($sv)) {
        return (Normalize-PathText $sv)
    }

    return $null
}

function Refresh-MountedList {
    param([string]$SelectMountDir)

    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    $ctxLocal  = $script:ctx
    $setStatus = $script:ctx.SetStatus
    $selectDir = $SelectMountDir

    # Capture refs for Invoke-Ui safety
    $fnSetBusy = ${function:Set-ImagesBusy}
    $fnNorm    = ${function:Normalize-PathText}
    $fnUpdBtns = ${function:Update-MountedButtons}
    $fnUpdHealth = ${function:Update-MountedHealthSummary}

    & $fnSetBusy -Busy $true -Reason "Mounted list..." -Context $ctxLocal

    $dismMod    = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist)
    $mountedMod = (Resolve-ProjectPath "Services\MountedWimService.psm1" -MustExist)

    $safeDism    = $dismMod.Replace("'", "''")
    $safeMounted = $mountedMod.Replace("'", "''")

    $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$safeDism' -Force
Import-Module '$safeMounted' -Force

Get-MountedWimList
"@

    $onCompleted = {
        param($result)

        $needsBtnUpdate = $false

        try {
            $items = @($result)
            try { Set-AppStateValue -Key "LastMountedWimRefreshAtUtc" -Value ([DateTime]::UtcNow.ToString('o')) } catch {}

            try { Write-Log -Level INFO -Message ("MountedWimInfo: Items={0}" -f @($items).Count) -ToConsole } catch {}
            if (@($items).Count -gt 0) {
                $first = $items[0]
                $md = if ($first.PSObject.Properties.Match("MountDir").Count -gt 0) { [string]$first.MountDir } else { "<no MountDir>" }
                $im = if ($first.PSObject.Properties.Match("ImageFile").Count -gt 0) { [string]$first.ImageFile } else { "<no ImageFile>" }
                try { Write-Log -Level INFO -Message ("MountedWimInfo: First MountDir={0} ImageFile={1}" -f $md,$im) -ToConsole } catch {}
            }

            if ($ctxLocal.LstMountedWims) {
                $oc = New-Object System.Collections.ObjectModel.ObservableCollection[object]
                foreach ($it in $items) { [void]$oc.Add($it) }

                $ctxLocal.LstMountedWims.ItemsSource = $oc
                try { $ctxLocal.LstMountedWims.Items.Refresh() } catch {}
                try { & $fnUpdHealth -Items @($oc) } catch {}

                $selected = $null
                if ($selectDir) {
                    $want = (& $fnNorm $selectDir)
                    foreach ($it in $oc) {
                        if ($it -and $it.PSObject.Properties.Match("MountDir").Count -gt 0) {
                            $md2 = (& $fnNorm ([string]$it.MountDir))
                            if ($md2 -eq $want) { $selected = $it; break }
                        }
                    }
                }

                if (-not $selected -and $oc.Count -gt 0) { $selected = $oc[0] }

                if ($selected) {
                    try { $ctxLocal.LstMountedWims.SelectedItem = $selected } catch {}
                    try { $ctxLocal.LstMountedWims.ScrollIntoView($selected) } catch {}
                } else {
                    try { $ctxLocal.LstMountedWims.SelectedItem = $null } catch {}
                }

                # Buttons müssen nach Busy=false gesetzt werden (Update-MountedButtons blockt bei isBusy)
                $needsBtnUpdate = $true
            }
        } finally {
            & $fnSetBusy -Busy $false -Context $ctxLocal

            if ($needsBtnUpdate) {
                try { & $fnUpdBtns } catch {}
            }

            if ($setStatus) { & $setStatus "Ready" }
        }
    }.GetNewClosure()

    $onError = {
        param($ex)
        try { Show-UiError -Message $ex.Message }
        finally {
            & $fnSetBusy -Busy $false -Context $ctxLocal
            try { & $fnUpdBtns } catch {}
            if ($setStatus) { & $setStatus "Ready" }
        }
    }.GetNewClosure()

    Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label "MountedWimInfo"
}
