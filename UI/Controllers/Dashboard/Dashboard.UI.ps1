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

    $sourceState = Get-UiString -Key 'DashboardNoSource'
    $sourceDetail = Get-UiString -Key 'DashboardNoSourceDetail'
    $primary = Get-UiString -Key 'DashboardNoWorkSource'
    $next = Get-UiString -Key 'DashboardNoWorkSourceNext'
    $step1 = Get-UiString -Key 'DashboardStepChooseSource'
    $step2 = Get-UiString -Key 'DashboardStepChooseIsoOrStandalone'
    $step3 = Get-UiString -Key 'DashboardStepMountEdition'

    if ($mountCount -gt 0) {
        $sourceState = if ($hasInstall -or $hasStandalone) { Get-UiString -Key 'DashboardSourceWithMounts' } else { Get-UiString -Key 'DashboardMountsActive' }
        $sourceDetail = Get-UiString -Key 'DashboardActiveMountsDetailFormat' -Args @($mountCount)
        $primary = Get-UiString -Key 'DashboardMountsReadyFormat' -Args @($mountCount)
        $next = Get-UiString -Key 'DashboardNextMounted'
        $step1 = Get-UiString -Key 'DashboardStepIntegrate'
        $step2 = Get-UiString -Key 'DashboardStepUseUpdatesDriver'
        $step3 = Get-UiString -Key 'DashboardStepCommitDiscard'
    }
    elseif ($hasInstall -or $hasStandalone) {
        $sourceState = if ($hasStandalone) { Get-UiString -Key 'DashboardStandaloneReady' } else { Get-UiString -Key 'DashboardIsoReady' }
        $sourceDetail = if ($hasStandalone) { [string]$standalone } else { [string]$installPath }
        $primary = Get-UiString -Key 'DashboardSourceReadyNotMounted'
        $next = Get-UiString -Key 'DashboardNextOpenImages'
        $step1 = Get-UiString -Key 'DashboardStepOpenImages'
        $step2 = Get-UiString -Key 'DashboardStepSelectEditions'
        $step3 = Get-UiString -Key 'DashboardStepUseAfterMount'
    }
    elseif ($hasIso -and -not $hasIsoRoot) {
        $sourceState = Get-UiString -Key 'DashboardIsoSelected'
        $sourceDetail = [string]$isoPath
        $primary = Get-UiString -Key 'DashboardIsoSelectedNotMounted'
        $next = Get-UiString -Key 'DashboardNextMountIso'
        $step1 = Get-UiString -Key 'DashboardStepMountIso'
        $step2 = Get-UiString -Key 'DashboardStepIsoDetectsImages'
        $step3 = Get-UiString -Key 'DashboardStepMountEditionShort'
    }
    elseif ($hasIsoRoot) {
        $sourceState = if ($hasBoot) { Get-UiString -Key 'DashboardIsoMounted' } else { Get-UiString -Key 'DashboardIsoRootActive' }
        $sourceDetail = [string]$isoRoot
        $primary = Get-UiString -Key 'DashboardIsoMountedInstallMissing'
        $next = Get-UiString -Key 'DashboardNextCheckIsoStructure'
        $step1 = Get-UiString -Key 'DashboardStepCheckSource'
        $step2 = Get-UiString -Key 'DashboardStepChooseWimIfMissing'
        $step3 = Get-UiString -Key 'DashboardStepOpenImagesShort'
    }

    Set-UiText -Root $Root -Name "TxtDashSourceState" -Value $sourceState
    Set-UiText -Root $Root -Name "TxtDashSourceDetail" -Value $sourceDetail
    Set-UiText -Root $Root -Name "TxtDashPrimaryStatus" -Value $primary
    Set-UiText -Root $Root -Name "TxtDashRecommendedNext" -Value $next
    Set-UiText -Root $Root -Name "TxtDashStep1" -Value $step1
    Set-UiText -Root $Root -Name "TxtDashStep2" -Value $step2
    Set-UiText -Root $Root -Name "TxtDashStep3" -Value $step3
}
