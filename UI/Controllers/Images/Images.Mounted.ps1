function Test-MountedWritable {
    param($MountedItem)
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

function Update-MountedButtons {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    $hasSel = $false
    $canCommit = $false

    if ($script:ctx.LstMountedWims -and $script:ctx.LstMountedWims.SelectedItem) {
        $hasSel = $true
        $canCommit = (Test-MountedWritable -MountedItem $script:ctx.LstMountedWims.SelectedItem)
    }

    if ($script:ctx.BtnUnmountMountedDiscard) { try { $script:ctx.BtnUnmountMountedDiscard.IsEnabled = $hasSel } catch {} }
    if ($script:ctx.BtnUnmountMountedCommit)  { try { $script:ctx.BtnUnmountMountedCommit.IsEnabled  = ($hasSel -and $canCommit) } catch {} }
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