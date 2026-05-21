function Initialize-DashboardController {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $DashboardPage,
        [Parameter(Mandatory)] [scriptblock] $SetStatus,
        [Parameter(Mandatory)] [scriptblock] $OnStateChanged
    )

    $script:ctx = @{
        DashboardPage  = $DashboardPage
        SetStatus      = $SetStatus
        OnStateChanged = $OnStateChanged

        BtnSelectIso   = $null
        BtnMountIso    = $null
        BtnAutoDetect  = $null
        BtnDismountIso = $null
        BtnSelectImage = $null
        BtnRefreshJobs = $null
        BtnCopyJobDetails = $null
        BtnOpenHistory = $null
        BtnOpenDismLog = $null
        GridRecentJobs = $null
    }

    $p = $DashboardPage
    $script:ctx.BtnSelectIso    = Find-Ui -Root $p -Name "BtnSelectIso"
    $script:ctx.BtnMountIso     = Find-Ui -Root $p -Name "BtnMountIso"
    $script:ctx.BtnAutoDetect   = Find-Ui -Root $p -Name "BtnAutoDetectIso"
    $script:ctx.BtnDismountIso  = Find-Ui -Root $p -Name "BtnDismountIso"
    $script:ctx.BtnSelectImage  = Find-Ui -Root $p -Name "BtnSelectImage"
    $script:ctx.BtnRefreshJobs  = Find-Ui -Root $p -Name "BtnDashRefreshJobs"
    $script:ctx.BtnCopyJobDetails = Find-Ui -Root $p -Name "BtnDashCopyJobDetails"
    $script:ctx.BtnOpenHistory = Find-Ui -Root $p -Name "BtnDashOpenHistory"
    $script:ctx.BtnOpenDismLog = Find-Ui -Root $p -Name "BtnDashOpenDismLog"
    $script:ctx.GridRecentJobs  = Find-Ui -Root $p -Name "GridDashRecentJobs"

    if ($script:ctx.BtnSelectIso) {
        $script:ctx.BtnSelectIso.Add_Click({
            try {
                Invoke-SetStatusSafe "ISO auswählen..."
                $iso = Select-IsoFile
                if ($iso) {
                    Set-AppStateValue -Key "IsoPath" -Value $iso
                    try { Write-Log -Level INFO -Message ("ISO gesetzt: {0}" -f $iso) -ToConsole } catch {}
                }
            } catch { Show-UiError -Message $_.Exception.Message }
            finally { Invoke-StateChangedSafe; Refresh-DashboardUI; Invoke-SetStatusSafe "Ready" }
        })
    }

    if ($script:ctx.BtnMountIso) {
        $script:ctx.BtnMountIso.Add_Click({
            try {
                $isoPath = Get-AppStateValue -Key "IsoPath" -Default $null
                if (-not $isoPath) { throw "Bitte zuerst eine ISO auswählen." }

                Invoke-SetStatusSafe "ISO mounten & scannen..."
                $info = Mount-IsoFile -IsoPath $isoPath

                Set-AppStateValue -Key "IsoRoot"             -Value $info.IsoRoot
                try { Set-AppStateValue -Key "IsoRootPath"   -Value $info.IsoRoot } catch {}
                Set-AppStateValue -Key "BootImagePath"       -Value $info.BootImagePath
                Set-AppStateValue -Key "IsoInstallImagePath" -Value $info.InstallImagePath

                try { Write-Log -Level INFO -Message ("ISO gemountet: Root={0}; Boot={1}; Install={2}" -f $info.IsoRoot, $info.BootImagePath, $info.InstallImagePath) -ToConsole } catch {}
            } catch { Show-UiError -Message $_.Exception.Message }
            finally { Invoke-StateChangedSafe; Refresh-DashboardUI; Invoke-SetStatusSafe "Ready" }
        })
    }

    if ($script:ctx.BtnAutoDetect) {
        $script:ctx.BtnAutoDetect.Add_Click({
            try { Invoke-SetStatusSafe "AutoDetect..."; $null = Try-AutoDetectIso_Local }
            catch { Show-UiError -Message $_.Exception.Message }
            finally { Invoke-StateChangedSafe; Refresh-DashboardUI; Invoke-SetStatusSafe "Ready" }
        })
    }

    if ($script:ctx.BtnDismountIso) {
        $script:ctx.BtnDismountIso.Add_Click({
            try {
                $isoPath = Get-AppStateValue -Key "IsoPath" -Default $null
                if (-not $isoPath) { throw "Keine ISO im State gesetzt (IsoPath)." }

                Invoke-SetStatusSafe "ISO aushängen..."
                Dismount-IsoFile -IsoPath $isoPath

                Set-AppStateValue -Key "IsoRoot"             -Value $null
                try { Set-AppStateValue -Key "IsoRootPath"   -Value $null } catch {}
                Set-AppStateValue -Key "BootImagePath"       -Value $null
                Set-AppStateValue -Key "IsoInstallImagePath" -Value $null
            } catch { Show-UiError -Message $_.Exception.Message }
            finally { Invoke-StateChangedSafe; Refresh-DashboardUI; Invoke-SetStatusSafe "Ready" }
        })
    }

    if ($script:ctx.BtnSelectImage) {
        $script:ctx.BtnSelectImage.Add_Click({
            try {
                Invoke-SetStatusSafe "Standalone wählen..."
                $img = Select-ImageFile
                if (-not $img) { return }

                Set-AppStateValue -Key "StandaloneImagePath" -Value $img
                Set-AppStateValue -Key "SelectedViewMode"    -Value "Standalone"
            } catch { Show-UiError -Message $_.Exception.Message }
            finally { Invoke-StateChangedSafe; Refresh-DashboardUI; Invoke-SetStatusSafe "Ready" }
        })
    }

    if ($script:ctx.BtnRefreshJobs) {
        $script:ctx.BtnRefreshJobs.Add_Click({
            try {
                Refresh-DashboardJobOverview -Root $script:ctx.DashboardPage
                Invoke-SetStatusSafe "Job-Verlauf aktualisiert."
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.GridRecentJobs) {
        $script:ctx.GridRecentJobs.Add_SelectionChanged({
            try {
                Update-DashboardJobDetails -Root $script:ctx.DashboardPage -JobView $script:ctx.GridRecentJobs.SelectedItem
            } catch {}
        })
    }

    if ($script:ctx.BtnCopyJobDetails) {
        $script:ctx.BtnCopyJobDetails.Add_Click({
            try {
                Copy-DashboardSelectedJobDetails -Root $script:ctx.DashboardPage
                Invoke-SetStatusSafe "Jobdetails kopiert."
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnOpenHistory) {
        $script:ctx.BtnOpenHistory.Add_Click({
            try {
                Open-DashboardJobHistoryFile
                Invoke-SetStatusSafe "Job-History geöffnet."
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnOpenDismLog) {
        $script:ctx.BtnOpenDismLog.Add_Click({
            try {
                Open-DashboardDismLog
                Invoke-SetStatusSafe "DISM-Log geöffnet."
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    try { $null = Try-AutoDetectIso_Local -Quiet } catch {}
    Invoke-StateChangedSafe
    Refresh-DashboardUI
}
