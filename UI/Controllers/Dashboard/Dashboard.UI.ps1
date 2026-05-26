function Refresh-DashboardUI {
    if (-not $script:ctx) { return }
    $p = $script:ctx.DashboardPage

    Refresh-DashboardHealthOverview -Root $p
    Refresh-DashboardJobOverview -Root $p

    Set-UiText -Root $p -Name "TxtIsoPath"        -Value (Get-AppStateValue -Key "IsoPath" -Default $null)
    Set-UiText -Root $p -Name "TxtIsoRoot"        -Value (Get-AppStateValue -Key "IsoRoot" -Default $null)
    Set-UiText -Root $p -Name "TxtBootPath"       -Value (Get-AppStateValue -Key "BootImagePath" -Default $null)
    Set-UiText -Root $p -Name "TxtIsoInstallPath" -Value (Get-AppStateValue -Key "IsoInstallImagePath" -Default $null)

    $standalone = Get-AppStateValue -Key "StandaloneImagePath" -Default $null
    $panel = Find-Ui -Root $p -Name "PanelStandalone"
    $txt   = Find-Ui -Root $p -Name "TxtStandaloneImagePath"

    if ($panel -and $panel.PSObject.Properties.Match("Visibility").Count -gt 0) {
        $panel.Visibility = if ($standalone) { "Visible" } else { "Collapsed" }
    }
    if ($txt -and $txt.PSObject.Properties.Match("Text").Count -gt 0) {
        $txt.Text = (Get-DisplayValue $standalone)
    }

    Refresh-DashboardWorkOverview -Root $p
}

function Get-DashboardMountedCountSafe {
    try {
        if (-not (Get-Command Get-MountedWimList -ErrorAction SilentlyContinue)) { return 0 }
        $mounts = @(Get-MountedWimList)
        $active = @($mounts | Where-Object {
            $registryOnly = $false
            try { $registryOnly = [bool]$_.RegistryOnly } catch {}
            -not $registryOnly
        })
        return $active.Count
    } catch {
        return 0
    }
}

function Refresh-DashboardWorkOverview {
    param($Root)

    if (-not $Root) { return }

    $isoPath = Get-AppStateValue -Key "IsoPath" -Default $null
    $isoRoot = Get-AppStateValue -Key "IsoRoot" -Default $null
    if ([string]::IsNullOrWhiteSpace([string]$isoRoot)) {
        try { $isoRoot = Get-AppStateValue -Key "IsoRootPath" -Default $null } catch {}
    }
    $bootPath = Get-AppStateValue -Key "BootImagePath" -Default $null
    $installPath = Get-AppStateValue -Key "IsoInstallImagePath" -Default $null
    $standalone = Get-AppStateValue -Key "StandaloneImagePath" -Default $null
    $mountCount = Get-DashboardMountedCountSafe

    $hasIso = -not [string]::IsNullOrWhiteSpace([string]$isoPath)
    $hasIsoRoot = -not [string]::IsNullOrWhiteSpace([string]$isoRoot)
    $hasBoot = -not [string]::IsNullOrWhiteSpace([string]$bootPath)
    $hasInstall = -not [string]::IsNullOrWhiteSpace([string]$installPath)
    $hasStandalone = -not [string]::IsNullOrWhiteSpace([string]$standalone)

    $sourceState = "Keine Quelle"
    $sourceDetail = "Wähle eine ISO oder eine einzelne WIM/ESD."
    $primary = "Noch keine Arbeitsquelle gewählt"
    $next = "Starte mit ISO wählen, AutoDetect oder WIM/ESD wählen."
    $step1 = "1. Quelle wählen"
    $step2 = "ISO auswählen oder Standalone-WIM/ESD laden."
    $step3 = "Danach in Images die gewünschten Editionen mounten."

    if ($mountCount -gt 0) {
        $sourceState = if ($hasInstall -or $hasStandalone) { "Quelle + Mounts" } else { "Mounts aktiv" }
        $sourceDetail = ("{0} Mount(s) aktiv. Updates, Treiber oder Unmount sind jetzt sinnvoll." -f $mountCount)
        $primary = ("{0} Mount(s) bereit" -f $mountCount)
        $next = "Weiter mit Updates, Driver oder Images zum Commit/Discard."
        $step1 = "1. Updates oder Treiber integrieren"
        $step2 = "Nutze Updates für MSU/CAB/Catalog oder Driver für Treiberpakete."
        $step3 = "Zum Abschluss in Images sauber Commit oder Discard ausführen."
    }
    elseif ($hasInstall -or $hasStandalone) {
        $sourceState = if ($hasStandalone) { "Standalone bereit" } else { "ISO bereit" }
        $sourceDetail = if ($hasStandalone) { [string]$standalone } else { [string]$installPath }
        $primary = "Quelle bereit, noch nicht gemountet"
        $next = "Gehe zu Images und mounte eine oder mehrere Editionen."
        $step1 = "1. Images öffnen"
        $step2 = "Editionen auswählen und nacheinander oder gesammelt mounten."
        $step3 = "Danach Updates, Treiber oder ISO bauen verwenden."
    }
    elseif ($hasIso -and -not $hasIsoRoot) {
        $sourceState = "ISO gewählt"
        $sourceDetail = [string]$isoPath
        $primary = "ISO gewählt, aber noch nicht gemountet"
        $next = "ISO mounten, damit boot.wim und install.wim/esd erkannt werden."
        $step1 = "1. ISO mounten"
        $step2 = "Das Dashboard erkennt danach boot.wim und install.wim/esd automatisch."
        $step3 = "Dann in Images die gewünschte Edition mounten."
    }
    elseif ($hasIsoRoot) {
        $sourceState = if ($hasBoot) { "ISO gemountet" } else { "ISO Root aktiv" }
        $sourceDetail = [string]$isoRoot
        $primary = "ISO gemountet, Install-Image fehlt noch"
        $next = "Prüfe die ISO-Struktur oder wähle die WIM/ESD direkt."
        $step1 = "1. Quelle prüfen"
        $step2 = "Wenn install.wim/esd nicht erkannt wurde, nutze WIM/ESD wählen."
        $step3 = "Danach Images öffnen."
    }

    Set-UiText -Root $Root -Name "TxtDashSourceState" -Value $sourceState
    Set-UiText -Root $Root -Name "TxtDashSourceDetail" -Value $sourceDetail
    Set-UiText -Root $Root -Name "TxtDashPrimaryStatus" -Value $primary
    Set-UiText -Root $Root -Name "TxtDashRecommendedNext" -Value $next
    Set-UiText -Root $Root -Name "TxtDashStep1" -Value $step1
    Set-UiText -Root $Root -Name "TxtDashStep2" -Value $step2
    Set-UiText -Root $Root -Name "TxtDashStep3" -Value $step3
}
