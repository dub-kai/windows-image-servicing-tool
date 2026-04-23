Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force

$script:ctx = $null
$script:suppressSettingsEvents = $false

function Get-SettingsBoolValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][bool]$Default
    )

    try {
        return [bool](Get-ConfigValue -Key $Key -Default $Default)
    } catch {
        return $Default
    }
}

function Set-SettingsComboToContent {
    param(
        [Parameter(Mandatory)]$ComboBox,
        [Parameter(Mandatory)][string]$Content
    )

    if (-not $ComboBox) { return }

    foreach ($item in @($ComboBox.Items)) {
        try {
            if ([string]$item.Content -eq $Content) {
                $ComboBox.SelectedItem = $item
                return
            }
        } catch {}
    }
}

function Get-SelectedSettingsComboContent {
    param(
        [Parameter(Mandatory)]$ComboBox,
        [string]$Default = $null
    )

    if (-not $ComboBox) { return $Default }

    try {
        $selected = $ComboBox.SelectedItem
        if ($selected -and $selected.PSObject.Properties.Match('Content').Count -gt 0) {
            $text = [string]$selected.Content
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                return $text
            }
        }
    } catch {}

    return $Default
}

function Save-SettingsValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter()]$Value,
        [string]$StatusMessage = $null
    )

    try {
        Set-ConfigValue -Key $Key -Value $Value -Persist | Out-Null

        if ($Key -eq 'StartPage') {
            try { Set-AppStateValue -Key 'StartPage' -Value $Value } catch {}
        }

        if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
        if ($script:ctx.SetStatus -and -not [string]::IsNullOrWhiteSpace($StatusMessage)) {
            try { & $script:ctx.SetStatus $StatusMessage } catch {}
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Refresh-SettingsUI {
    if (-not $script:ctx) { return }

    try {
        $script:suppressSettingsEvents = $true

        if ($script:ctx.TxtSettingsMountRoot) {
            try {
                $mr = Get-MountRoot
                $script:ctx.TxtSettingsMountRoot.Text = ("MountRoot: {0}" -f (Get-DisplayValue $mr))
            } catch {
                $script:ctx.TxtSettingsMountRoot.Text = "MountRoot: -"
            }
        }

        if ($script:ctx.TxtSettingsProjectRoot) {
            try { $script:ctx.TxtSettingsProjectRoot.Text = (Get-DisplayValue (Get-ProjectRoot)) } catch { $script:ctx.TxtSettingsProjectRoot.Text = "-" }
        }

        if ($script:ctx.TxtSettingsLogFile) {
            try {
                if (Get-Command Get-LogFilePath -ErrorAction SilentlyContinue) {
                    $script:ctx.TxtSettingsLogFile.Text = (Get-DisplayValue (Get-LogFilePath))
                } else {
                    $script:ctx.TxtSettingsLogFile.Text = "-"
                }
            } catch {
                $script:ctx.TxtSettingsLogFile.Text = "-"
            }
        }

        if ($script:ctx.TxtSettingsConfigFile) {
            try {
                $script:ctx.TxtSettingsConfigFile.Text = (Get-DisplayValue (Get-ConfigFilePath))
            } catch {
                $script:ctx.TxtSettingsConfigFile.Text = "-"
            }
        }

        if ($script:ctx.CmbSettingsStartPage) {
            $startPage = [string](Get-ConfigValue -Key 'StartPage' -Default 'Dashboard')
            Set-SettingsComboToContent -ComboBox $script:ctx.CmbSettingsStartPage -Content $startPage
        }

        if ($script:ctx.ChkSettingsDriverLoadAllDefault) {
            $script:ctx.ChkSettingsDriverLoadAllDefault.IsChecked = Get-SettingsBoolValue -Key 'DriverLoadAllDefault' -Default $false
        }

        if ($script:ctx.ChkSettingsUpdatesAutoCatalogDefault) {
            $script:ctx.ChkSettingsUpdatesAutoCatalogDefault.IsChecked = Get-SettingsBoolValue -Key 'UpdatesAutoCatalogDefault' -Default $true
        }

        if ($script:ctx.ChkSettingsImageMountReadOnlyDefault) {
            $script:ctx.ChkSettingsImageMountReadOnlyDefault.IsChecked = Get-SettingsBoolValue -Key 'ImageMountReadOnlyDefault' -Default $true
        }

        if ($script:ctx.ChkSettingsAppDebug) {
            $script:ctx.ChkSettingsAppDebug.IsChecked = Get-SettingsBoolValue -Key 'AppDebug' -Default $false
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    } finally {
        $script:suppressSettingsEvents = $false
    }
}

function Initialize-SettingsController {
    param(
        [Parameter(Mandatory)] $SettingsPage,
        [Parameter(Mandatory)] [scriptblock] $SetStatus,
        [Parameter()] [scriptblock] $OnStateChanged = $null
    )

    $script:ctx = @{
        SettingsPage = $SettingsPage
        SetStatus    = $SetStatus
        OnStateChanged = $OnStateChanged

        TxtSettingsMountRoot           = $null
        BtnSettingsPickMountRoot       = $null
        BtnSettingsResetMountRoot      = $null
        CmbSettingsStartPage           = $null
        ChkSettingsDriverLoadAllDefault = $null
        ChkSettingsUpdatesAutoCatalogDefault = $null
        ChkSettingsImageMountReadOnlyDefault = $null
        ChkSettingsAppDebug            = $null

        TxtSettingsProjectRoot = $null
        TxtSettingsLogFile     = $null
        TxtSettingsConfigFile  = $null
    }

    $p = $SettingsPage

    $script:ctx.TxtSettingsMountRoot      = Find-Ui -Root $p -Name "TxtSettingsMountRoot"
    $script:ctx.BtnSettingsPickMountRoot  = Find-Ui -Root $p -Name "BtnSettingsPickMountRoot"
    $script:ctx.BtnSettingsResetMountRoot = Find-Ui -Root $p -Name "BtnSettingsResetMountRoot"
    $script:ctx.CmbSettingsStartPage      = Find-Ui -Root $p -Name "CmbSettingsStartPage"
    $script:ctx.ChkSettingsDriverLoadAllDefault = Find-Ui -Root $p -Name "ChkSettingsDriverLoadAllDefault"
    $script:ctx.ChkSettingsUpdatesAutoCatalogDefault = Find-Ui -Root $p -Name "ChkSettingsUpdatesAutoCatalogDefault"
    $script:ctx.ChkSettingsImageMountReadOnlyDefault = Find-Ui -Root $p -Name "ChkSettingsImageMountReadOnlyDefault"
    $script:ctx.ChkSettingsAppDebug       = Find-Ui -Root $p -Name "ChkSettingsAppDebug"

    $script:ctx.TxtSettingsProjectRoot = Find-Ui -Root $p -Name "TxtSettingsProjectRoot"
    $script:ctx.TxtSettingsLogFile     = Find-Ui -Root $p -Name "TxtSettingsLogFile"
    $script:ctx.TxtSettingsConfigFile  = Find-Ui -Root $p -Name "TxtSettingsConfigFile"

    if ($script:ctx.BtnSettingsPickMountRoot) {
        $script:ctx.BtnSettingsPickMountRoot.Add_Click({
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = "MountRoot wählen (lokal, NTFS empfohlen)"

                $cur = $null
                try { $cur = Get-AppStateValue -Key "MountRoot" -Default $null } catch {}
                if ($cur) { $dlg.SelectedPath = $cur }

                $ok = $dlg.ShowDialog()
                if ($ok -ne [System.Windows.Forms.DialogResult]::OK) { return }

                Set-MountRoot -Path $dlg.SelectedPath -Persist | Out-Null

                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus "Settings: MountRoot gesetzt" } catch {} }
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetMountRoot) {
        $script:ctx.BtnSettingsResetMountRoot.Add_Click({
            try {
                try { Set-AppStateValue -Key "MountRoot" -Value $null } catch {}
                try { Set-ConfigValue -Key "MountRoot" -Value $null -Persist } catch {}
                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus "Settings: MountRoot reset" } catch {} }
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.CmbSettingsStartPage) {
        $script:ctx.CmbSettingsStartPage.Add_SelectionChanged({
            if ($script:suppressSettingsEvents) { return }
            $selected = Get-SelectedSettingsComboContent -ComboBox $script:ctx.CmbSettingsStartPage -Default 'Dashboard'
            Save-SettingsValue -Key 'StartPage' -Value $selected -StatusMessage ('Settings: Startseite = {0}' -f $selected)
        })
    }

    if ($script:ctx.ChkSettingsDriverLoadAllDefault) {
        $script:ctx.ChkSettingsDriverLoadAllDefault.Add_Click({
            Save-SettingsValue -Key 'DriverLoadAllDefault' -Value ([bool]$script:ctx.ChkSettingsDriverLoadAllDefault.IsChecked) -StatusMessage 'Settings: Driver-Standard aktualisiert'
        })
    }

    if ($script:ctx.ChkSettingsUpdatesAutoCatalogDefault) {
        $script:ctx.ChkSettingsUpdatesAutoCatalogDefault.Add_Click({
            Save-SettingsValue -Key 'UpdatesAutoCatalogDefault' -Value ([bool]$script:ctx.ChkSettingsUpdatesAutoCatalogDefault.IsChecked) -StatusMessage 'Settings: Updates-Standard aktualisiert'
        })
    }

    if ($script:ctx.ChkSettingsImageMountReadOnlyDefault) {
        $script:ctx.ChkSettingsImageMountReadOnlyDefault.Add_Click({
            Save-SettingsValue -Key 'ImageMountReadOnlyDefault' -Value ([bool]$script:ctx.ChkSettingsImageMountReadOnlyDefault.IsChecked) -StatusMessage 'Settings: Mount-Standard aktualisiert'
        })
    }

    if ($script:ctx.ChkSettingsAppDebug) {
        $script:ctx.ChkSettingsAppDebug.Add_Click({
            Save-SettingsValue -Key 'AppDebug' -Value ([bool]$script:ctx.ChkSettingsAppDebug.IsChecked) -StatusMessage 'Settings: Debug-Standard aktualisiert'
        })
    }

    Refresh-SettingsUI
}

Export-ModuleMember -Function Initialize-SettingsController, Refresh-SettingsUI
