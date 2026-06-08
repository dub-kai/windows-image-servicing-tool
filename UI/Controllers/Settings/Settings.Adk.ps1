Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CurrentAdkStatus {
    $adkRoot = [string](Get-SettingsConfigValue -Key 'AdkRoot' -Default $null)
    $winPeRoot = [string](Get-SettingsConfigValue -Key 'WinPeRoot' -Default $null)
    $oscdimgPath = [string](Get-SettingsConfigValue -Key 'OscdimgPath' -Default $null)

    return Get-AdkStatus -ConfiguredAdkRoot $adkRoot -ConfiguredWinPeRoot $winPeRoot -ConfiguredOscdimgPath $oscdimgPath
}

function Refresh-SettingsAdkUI {
    if (-not $script:ctx) { return }

    try {
        $status = Get-CurrentAdkStatus

        if ($script:ctx.TxtSettingsAdkRoot) {
            $script:ctx.TxtSettingsAdkRoot.Text = (Get-DisplayValue $status.AdkRoot)
        }

        if ($script:ctx.TxtSettingsWinPeRoot) {
            $script:ctx.TxtSettingsWinPeRoot.Text = (Get-DisplayValue $status.WinPeRoot)
        }

        if ($script:ctx.TxtSettingsOscdimgPath) {
            $script:ctx.TxtSettingsOscdimgPath.Text = (Get-DisplayValue $status.OscdimgPath)
        }

        if ($script:ctx.TxtSettingsCopypePath) {
            $script:ctx.TxtSettingsCopypePath.Text = ('copype.cmd: {0}' -f (Get-DisplayValue $status.CopypePath))
        }

        if ($script:ctx.TxtSettingsMakeWinPeMediaPath) {
            $script:ctx.TxtSettingsMakeWinPeMediaPath.Text = ('MakeWinPEMedia.cmd: {0}' -f (Get-DisplayValue $status.MakeWinPEMediaPath))
        }

        if ($script:ctx.TxtSettingsAdkSummary) {
            $parts = New-Object System.Collections.Generic.List[string]
            if ($status.HasAdkRoot) { $parts.Add('ADK Root') | Out-Null }
            if ($status.HasWinPe) { $parts.Add('WinPE') | Out-Null }
            if ($status.HasOscdimg) { $parts.Add('oscdimg') | Out-Null }
            if ($status.HasCopype) { $parts.Add('copype') | Out-Null }
            if ($status.HasMakeWinPeMedia) { $parts.Add('MakeWinPEMedia') | Out-Null }

            if ($parts.Count -gt 0) {
                $script:ctx.TxtSettingsAdkSummary.Text = (Get-UiString -Key 'AdkStatusLabel' -Args @(($parts -join ', ')))
            } else {
                $script:ctx.TxtSettingsAdkSummary.Text = Get-UiString -Key 'AdkStatusMissing'
            }
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Pick-SettingsFolderPath {
    param(
        [Parameter(Mandatory)][string]$Description,
        [string]$InitialPath = $null
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = (Get-LocalizedText -Text $Description)
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath)) {
        $dlg.SelectedPath = $InitialPath
    }

    $ok = $dlg.ShowDialog()
    if ($ok -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$dlg.SelectedPath)) { return $null }
    return [string]$dlg.SelectedPath
}

function Pick-SettingsFilePath {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Filter,
        [string]$InitialPath = $null
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = (Get-LocalizedText -Text $Title)
    $dlg.Filter = $Filter
    $dlg.CheckFileExists = $true
    $dlg.Multiselect = $false

    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath)) {
        try {
            $dlg.InitialDirectory = Split-Path -LiteralPath $InitialPath -Parent
            $dlg.FileName = Split-Path -LiteralPath $InitialPath -Leaf
        } catch {}
    }

    $ok = $dlg.ShowDialog()
    if ($ok -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$dlg.FileName)) { return $null }
    return [string]$dlg.FileName
}

function Detect-AndSaveAdkDefaults {
    $status = Get-AdkStatus

    if ($status.AdkRoot) {
        Set-SettingsConfigValue -Key 'AdkRoot' -Value ([string]$status.AdkRoot) -Persist | Out-Null
    }
    if ($status.WinPeRoot) {
        Set-SettingsConfigValue -Key 'WinPeRoot' -Value ([string]$status.WinPeRoot) -Persist | Out-Null
    }
    if ($status.OscdimgPath) {
        Set-SettingsConfigValue -Key 'OscdimgPath' -Value ([string]$status.OscdimgPath) -Persist | Out-Null
    }

    Refresh-SettingsAdkUI
    return $status
}
