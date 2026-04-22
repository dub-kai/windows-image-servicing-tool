Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DisplayValue {
    param([object]$Value)
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return "-" }
    return $s
}

function Normalize-PathText {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ($Path.StartsWith('\')) { return $Path } # UNC nicht anfassen
    return $Path.Replace('\\', '\')
}

function Get-ImagesViewMode {
    if (-not $script:ctx -or -not $script:ctx.CmbView -or -not $script:ctx.CmbView.SelectedItem) {
        return $null
    }

    $content = $null
    try { $content = [string]$script:ctx.CmbView.SelectedItem.Content } catch { $content = $null }

    switch ($content) {
        "ISO Install" { return "IsoInstall" }
        "ISO Boot"    { return "IsoBoot" }
        "Standalone"  { return "Standalone" }
        default       { return $null }
    }
}

function Set-ImagesViewMode {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("IsoInstall","IsoBoot","Standalone")]
        [string]$Mode
    )

    if (-not $script:ctx -or -not $script:ctx.CmbView) { return }

    $currentMode = $null
    try { $currentMode = Get-ImagesViewMode } catch { $currentMode = $null }

    if ($currentMode -eq $Mode) {
        try { Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value $Mode } catch {}
        return
    }

    $target = $null
    switch ($Mode) {
        "IsoInstall" { $target = $script:ctx.CmbItemIsoInstall }
        "IsoBoot"    { $target = $script:ctx.CmbItemIsoBoot }
        "Standalone" { $target = $script:ctx.CmbItemStandalone }
    }

    $script:isSyncingImagesView = $true
    try {
        if ($target) {
            try {
                $script:ctx.CmbView.SelectedItem = $target
                try { Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value $Mode } catch {}
                return
            } catch {}
        }

        try {
            switch ($Mode) {
                'IsoInstall' { $script:ctx.CmbView.SelectedIndex = 0 }
                'IsoBoot'    { $script:ctx.CmbView.SelectedIndex = 1 }
                'Standalone' { $script:ctx.CmbView.SelectedIndex = 2 }
            }
            try { Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value $Mode } catch {}
        } catch {}
    }
    finally {
        $script:isSyncingImagesView = $false
    }
}

function Get-ImagesPathForMode {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("IsoInstall","IsoBoot","Standalone")]
        [string]$Mode
    )

    $p = $null

    switch ($Mode) {
        "IsoInstall" {
            try { $p = Get-AppStateValue -Key "IsoInstallImagePath" -Default $null } catch { $p = $null }
            if ([string]::IsNullOrWhiteSpace([string]$p) -and $script:ctx) {
                try { $p = $script:ctx.IsoInstallPath } catch { $p = $null }
            }

            try {
                Write-Log -Level INFO -Message ("Images Path Resolve: Mode=IsoInstall; Path={0}" -f (Get-DisplayValue $p))
            } catch {}

            if (-not $p) { throw "ISO Install ist nicht verfügbar (ISO mounten)." }
            return (Normalize-PathText $p)
        }

        "IsoBoot" {
            try { $p = Get-AppStateValue -Key "BootImagePath" -Default $null } catch { $p = $null }
            if ([string]::IsNullOrWhiteSpace([string]$p) -and $script:ctx) {
                try { $p = $script:ctx.IsoBootPath } catch { $p = $null }
            }

            try {
                Write-Log -Level INFO -Message ("Images Path Resolve: Mode=IsoBoot; Path={0}" -f (Get-DisplayValue $p))
            } catch {}

            if (-not $p) { throw "ISO Boot ist nicht verfügbar (ISO mounten)." }
            return (Normalize-PathText $p)
        }

        "Standalone" {
            try { $p = Get-AppStateValue -Key "StandaloneImagePath" -Default $null } catch { $p = $null }
            if ([string]::IsNullOrWhiteSpace([string]$p) -and $script:ctx) {
                try { $p = $script:ctx.StandalonePath } catch { $p = $null }
            }

            try {
                Write-Log -Level INFO -Message ("Images Path Resolve: Mode=Standalone; Path={0}" -f (Get-DisplayValue $p))
            } catch {}

            if (-not $p) { throw "Standalone ist nicht gesetzt (WIM/ESD wählen)." }
            return (Normalize-PathText $p)
        }
    }
}

function Refresh-ImagesUI {
    if (-not $script:ctx) { return }

    try { Sync-IsoStateFromMountedMedia } catch {}

    $isoInstallPath = $null
    $isoBootPath    = $null
    $standalonePath = $null

    try { $isoInstallPath = Get-AppStateValue -Key "IsoInstallImagePath" -Default $null } catch { $isoInstallPath = $null }
    try { $isoBootPath    = Get-AppStateValue -Key "BootImagePath"       -Default $null } catch { $isoBootPath = $null }
    try { $standalonePath = Get-AppStateValue -Key "StandaloneImagePath" -Default $null } catch { $standalonePath = $null }

    if ([string]::IsNullOrWhiteSpace([string]$isoInstallPath) -and $script:ctx) {
        try { $isoInstallPath = $script:ctx.IsoInstallPath } catch {}
    }
    if ([string]::IsNullOrWhiteSpace([string]$isoBootPath) -and $script:ctx) {
        try { $isoBootPath = $script:ctx.IsoBootPath } catch {}
    }
    if ([string]::IsNullOrWhiteSpace([string]$standalonePath) -and $script:ctx) {
        try { $standalonePath = $script:ctx.StandalonePath } catch {}
    }

    try { Set-UiText -Root $script:ctx.ImagesPage -Name "TxtIsoInstall" -Value (Get-DisplayValue $isoInstallPath) } catch {}
    try { Set-UiText -Root $script:ctx.ImagesPage -Name "TxtIsoBoot"    -Value (Get-DisplayValue $isoBootPath) } catch {}
    try { Set-UiText -Root $script:ctx.ImagesPage -Name "TxtStandalone" -Value (Get-DisplayValue $standalonePath) } catch {}

    $hasIsoInstall = [bool]$isoInstallPath
    $hasIsoBoot    = [bool]$isoBootPath
    $hasStandalone = [bool]$standalonePath

    try { Set-UiEnabled -Root $script:ctx.ImagesPage -Name "CmbItemIsoInstall" -Enabled $hasIsoInstall } catch {}
    try { Set-UiEnabled -Root $script:ctx.ImagesPage -Name "CmbItemIsoBoot"    -Enabled $hasIsoBoot } catch {}
    try { Set-UiEnabled -Root $script:ctx.ImagesPage -Name "CmbItemStandalone" -Enabled $hasStandalone } catch {}

    $mode = Get-ImagesViewMode
    $ok = $false
    if ($mode -eq "IsoInstall" -and $hasIsoInstall) { $ok = $true }
    elseif ($mode -eq "IsoBoot" -and $hasIsoBoot) { $ok = $true }
    elseif ($mode -eq "Standalone" -and $hasStandalone) { $ok = $true }

    if (-not $ok) {
        if ($hasIsoInstall) {
            Set-ImagesViewMode -Mode "IsoInstall"
        }
        elseif ($hasIsoBoot) {
            Set-ImagesViewMode -Mode "IsoBoot"
        }
        elseif ($hasStandalone) {
            Set-ImagesViewMode -Mode "Standalone"
        }
        else {
            $script:isSyncingImagesView = $true
            try {
                if ($script:ctx.CmbView) {
                    $script:ctx.CmbView.SelectedIndex = -1
                }
            }
            finally {
                $script:isSyncingImagesView = $false
            }
        }
    }

    $m = Get-ImagesViewMode
    $isIso = ($m -eq "IsoInstall" -or $m -eq "IsoBoot")

    if ($script:ctx.ChkReadOnly) {
        try {
            if ($isIso) {
                $script:ctx.ChkReadOnly.IsChecked = $true
                $script:ctx.ChkReadOnly.IsEnabled = $false
            } else {
                $script:ctx.ChkReadOnly.IsEnabled = $true
            }
        } catch {}
    }

    try { Update-MountUiFromState } catch {}
    try { Update-MountedButtons } catch {}
    try { Update-SelectedIndexUi } catch {}

    try {
        Write-Log -Level INFO -Message ("Images UI Refresh: Mode={0}; IsoInstall={1}; IsoBoot={2}; Standalone={3}" -f `
            (Get-DisplayValue (Get-ImagesViewMode)),
            (Get-DisplayValue $isoInstallPath),
            (Get-DisplayValue $isoBootPath),
            (Get-DisplayValue $standalonePath))
    } catch {}
}