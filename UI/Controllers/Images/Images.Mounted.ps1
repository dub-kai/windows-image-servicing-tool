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
    $mountDir = $null

    try {
        if ($MountedItem.PSObject.Properties.Match("Health").Count -gt 0) { $health = [string]$MountedItem.Health }
        if ($MountedItem.PSObject.Properties.Match("HealthHint").Count -gt 0) { $hint = [string]$MountedItem.HealthHint }
        if ($MountedItem.PSObject.Properties.Match("RecommendedAction").Count -gt 0) { $action = [string]$MountedItem.RecommendedAction }
        if ($MountedItem.PSObject.Properties.Match("MountDir").Count -gt 0) { $mountDir = [string]$MountedItem.MountDir }
    } catch {}

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($mountDir)) { [void]$parts.Add($mountDir) }
    if (-not [string]::IsNullOrWhiteSpace($health)) { [void]$parts.Add(("Zustand: {0}" -f $health)) }
    if (-not [string]::IsNullOrWhiteSpace($hint)) { [void]$parts.Add($hint) }
    if (-not [string]::IsNullOrWhiteSpace($action)) { [void]$parts.Add(("Empfohlen: {0}" -f $action)) }

    if ($parts.Count -lt 1) { return 'Tipp: Auswahl anklicken, dann Unmount.' }
    return ($parts -join ' | ')
}

function Update-MountedButtons {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    $hasSel = $false
    $canCommit = $false
    $canDiscard = $false
    $selected = $null

    if ($script:ctx.LstMountedWims -and $script:ctx.LstMountedWims.SelectedItem) {
        $hasSel = $true
        $selected = $script:ctx.LstMountedWims.SelectedItem
        $canCommit = (Test-MountedWritable -MountedItem $selected)
        $canDiscard = (Test-MountedDiscardAllowed -MountedItem $selected)
    }

    if ($script:ctx.BtnUnmountMountedDiscard) {
        try {
            $script:ctx.BtnUnmountMountedDiscard.IsEnabled = ($hasSel -and $canDiscard)
            $recommendedAction = ''
            if ($selected -and $selected.PSObject.Properties.Match("RecommendedAction").Count -gt 0) {
                $recommendedAction = [string]$selected.RecommendedAction
            }
            if ($recommendedAction -match 'bereinig|Ohne Commit') {
                $script:ctx.BtnUnmountMountedDiscard.Content = 'Mount bereinigen'
            } else {
                $script:ctx.BtnUnmountMountedDiscard.Content = 'Unmount (Discard)'
            }
        } catch {}
    }
    if ($script:ctx.BtnUnmountMountedCommit)  { try { $script:ctx.BtnUnmountMountedCommit.IsEnabled  = ($hasSel -and $canCommit) } catch {} }
    if ($script:ctx.TxtMountedHint) { try { $script:ctx.TxtMountedHint.Text = (Get-MountedSelectionHint -MountedItem $selected) } catch {} }
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
