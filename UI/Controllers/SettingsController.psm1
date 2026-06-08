Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\UiAsync.psm1" -MustExist) -Force -DisableNameChecking -Global
$script:configModule = Get-Module -Name 'Config' | Select-Object -First 1
if (-not $script:configModule) {
    $script:configModule = Import-Module (Resolve-ProjectPath "Core\Config.psm1" -MustExist) -DisableNameChecking -Global -PassThru
}
Import-Module (Resolve-ProjectPath "UI\Localization.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\Theme.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\Notifications.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "Services\AdkService.psm1" -MustExist) -Force -DisableNameChecking -Global

$script:getConfigValueCommand = $null
$script:setConfigValueCommand = $null
$script:getConfigFilePathCommand = $null

try { $script:getConfigValueCommand = $script:configModule.ExportedCommands['Get-ConfigValue'] } catch {}
try { $script:setConfigValueCommand = $script:configModule.ExportedCommands['Set-ConfigValue'] } catch {}
try { $script:getConfigFilePathCommand = $script:configModule.ExportedCommands['Get-ConfigFilePath'] } catch {}

$script:ctx = $null
$script:suppressSettingsEvents = $false
$script:isHealthBusy = $false
$script:settingsDeferredHealthTimer = $null

function Get-SettingsConfigValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter()]$Default = $null
    )

    if (-not $script:getConfigValueCommand) {
        throw "Get-ConfigValue ist nicht verfügbar."
    }

    return (& $script:getConfigValueCommand -Key $Key -Default $Default)
}

function Set-SettingsConfigValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter()]$Value,
        [switch]$Persist
    )

    if (-not $script:setConfigValueCommand) {
        throw "Set-ConfigValue ist nicht verfügbar."
    }

    return (& $script:setConfigValueCommand -Key $Key -Value $Value -Persist:$Persist)
}

function Get-SettingsConfigFilePath {
    param()

    if (-not $script:getConfigFilePathCommand) {
        throw "Get-ConfigFilePath ist nicht verfügbar."
    }

    return (& $script:getConfigFilePathCommand)
}

function Get-SettingsBoolValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][bool]$Default
    )

    try {
        return [bool](Get-SettingsConfigValue -Key $Key -Default $Default)
    } catch {
        return $Default
    }
}

function Set-SettingsComboToTag {
    param(
        [Parameter(Mandatory)]$ComboBox,
        [Parameter(Mandatory)][string]$Tag
    )

    if (-not $ComboBox) { return }

    foreach ($item in @($ComboBox.Items)) {
        try {
            if ([string]$item.Tag -eq $Tag) {
                $ComboBox.SelectedItem = $item
                return
            }
        } catch {}
    }
}

function Get-SelectedSettingsComboTag {
    param(
        [Parameter(Mandatory)]$ComboBox,
        [string]$Default = $null
    )

    if (-not $ComboBox) { return $Default }

    try {
        $selected = $ComboBox.SelectedItem
        if ($selected -and $selected.PSObject.Properties.Match('Tag').Count -gt 0) {
            $text = [string]$selected.Tag
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                return $text
            }
        }
    } catch {}

    return $Default
}

function Get-UiLanguageLabel {
    param(
        [Parameter(Mandatory)][string]$LanguageCode
    )

    switch ($LanguageCode) {
        'en' { return (Get-UiString -Key 'SettingsLangEnglish') }
        default { return (Get-UiString -Key 'SettingsLangGerman') }
    }
}

function Save-SettingsValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter()]$Value,
        [string]$StatusMessage = $null
    )

    try {
        Set-SettingsConfigValue -Key $Key -Value $Value -Persist | Out-Null

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

function Get-SettingsIntValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][int]$Default,
        [Parameter()][int]$Min = 0,
        [Parameter()][int]$Max = 2147483647
    )

    $value = $Default
    try { $value = [int](Get-SettingsConfigValue -Key $Key -Default $Default) } catch { $value = $Default }
    if ($value -lt $Min) { return $Min }
    if ($value -gt $Max) { return $Max }
    return $value
}

function Set-SettingsTextBoxInt {
    param(
        $TextBox,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][int]$Default,
        [Parameter()][int]$Min = 0,
        [Parameter()][int]$Max = 2147483647
    )

    if (-not $TextBox) { return }
    $TextBox.Text = [string](Get-SettingsIntValue -Key $Key -Default $Default -Min $Min -Max $Max)
}

function Get-SettingsTextBoxInt {
    param(
        $TextBox,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][int]$Min,
        [Parameter(Mandatory)][int]$Max
    )

    $raw = ''
    try { $raw = [string]$TextBox.Text } catch { $raw = '' }

    $value = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$value)) {
        throw ("{0}: Bitte eine ganze Zahl eingeben." -f $Label)
    }

    if ($value -lt $Min -or $value -gt $Max) {
        throw (Get-UiString -Key 'SettingsIntRangeFormat' -Args @($Label, $Min, $Max))
    }

    return $value
}

. (Resolve-ProjectPath "UI\Controllers\Settings\Settings.DismBatch.ps1" -MustExist)

. (Resolve-ProjectPath "UI\Controllers\Settings\Settings.Adk.ps1" -MustExist)

. (Resolve-ProjectPath "UI\Controllers\Settings\Settings.Health.ps1" -MustExist)

. (Resolve-ProjectPath "UI\Controllers\Settings\Settings.Logs.ps1" -MustExist)

function Refresh-SettingsUI {
    if (-not $script:ctx) { return }

    try {
        $script:suppressSettingsEvents = $true

        if ($script:ctx.TxtSettingsMountRoot) {
            try {
                $mr = Get-MountRoot
                $script:ctx.TxtSettingsMountRoot.Text = (Get-UiString -Key 'SettingsMountRootLabel' -Args @((Get-DisplayValue $mr)))
            } catch {
                $script:ctx.TxtSettingsMountRoot.Text = (Get-UiString -Key 'SettingsMountRootLabel' -Args @('-'))
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
                $script:ctx.TxtSettingsConfigFile.Text = (Get-DisplayValue (Get-SettingsConfigFilePath))
            } catch {
                $script:ctx.TxtSettingsConfigFile.Text = "-"
            }
        }

        Refresh-SettingsAdkUI
        Refresh-SettingsLogsUI
        Refresh-SettingsDismBatchUI

        if ($script:ctx.CmbSettingsStartPage) {
            $startPage = [string](Get-SettingsConfigValue -Key 'StartPage' -Default 'Dashboard')
            Set-SettingsComboToTag -ComboBox $script:ctx.CmbSettingsStartPage -Tag $startPage
        }

        if ($script:ctx.CmbSettingsLanguage) {
            $language = [string](Get-SettingsConfigValue -Key 'UiLanguage' -Default 'de')
            Set-SettingsComboToTag -ComboBox $script:ctx.CmbSettingsLanguage -Tag $language
        }

        if ($script:ctx.ChkSettingsDarkMode) {
            $script:ctx.ChkSettingsDarkMode.IsChecked = ((Get-UiThemeName) -eq 'Dark')
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

        if ($script:ctx.ChkSettingsNotificationsEnabled) {
            $script:ctx.ChkSettingsNotificationsEnabled.IsChecked = Get-SettingsBoolValue -Key 'NotificationsEnabled' -Default $true
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

        TxtSettingsMountRoot = $null
        BtnSettingsPickMountRoot = $null
        BtnSettingsResetMountRoot = $null
        CmbSettingsStartPage = $null
        CmbSettingsLanguage = $null
        ChkSettingsDarkMode = $null
        ChkSettingsDriverLoadAllDefault = $null
        ChkSettingsUpdatesAutoCatalogDefault = $null
        ChkSettingsImageMountReadOnlyDefault = $null
        ChkSettingsNotificationsEnabled = $null
        BtnSettingsTestNotification = $null
        ChkSettingsAppDebug = $null

        BtnSettingsDetectAdk = $null
        BtnSettingsPickAdkRoot = $null
        BtnSettingsPickWinPeRoot = $null
        BtnSettingsPickOscdimgPath = $null
        BtnSettingsResetAdkRoot = $null
        BtnSettingsResetWinPeRoot = $null
        BtnSettingsResetOscdimgPath = $null
        TxtSettingsAdkSummary = $null
        TxtSettingsAdkRoot = $null
        TxtSettingsWinPeRoot = $null
        TxtSettingsOscdimgPath = $null
        TxtSettingsCopypePath = $null
        TxtSettingsMakeWinPeMediaPath = $null

        BtnSettingsHealthRefresh = $null
        BtnSettingsUnmountAllDiscard = $null
        BtnSettingsCleanupEmptyMountDirs = $null
        TxtSettingsHealthSummary = $null
        TxtSettingsHealthAdmin = $null
        TxtSettingsHealthDism = $null
        TxtSettingsHealthMountRoot = $null
        TxtSettingsHealthDrive = $null
        TxtSettingsHealthMountCount = $null
        TxtSettingsHealthLog = $null
        LstSettingsHealthMounts = $null

        BtnSettingsLogsRefresh = $null
        BtnSettingsOpenLogFolder = $null
        BtnSettingsOpenCurrentLog = $null
        BtnSettingsOpenDismLog = $null
        BtnSettingsCleanupOldLogs = $null
        TxtSettingsLogsSummary = $null
        TxtSettingsAppLogPath = $null
        TxtSettingsDismLogPath = $null
        CmbSettingsLogPreviewSource = $null
        LstSettingsLogFiles = $null
        TxtSettingsLogPreviewTitle = $null
        TxtSettingsLogPreview = $null

        TxtSettingsDismTimeoutSec = $null
        TxtSettingsDismLockTimeoutSec = $null
        TxtSettingsDismUnmountCommitTimeoutSec = $null
        TxtSettingsDismUnmountCommitRetryCount = $null
        TxtSettingsDismUnmountCommitRetryDelaySec = $null
        TxtSettingsMountedWimRefreshQuietPeriodSec = $null
        TxtSettingsBatchUnmountStepDelaySec = $null
        BtnSettingsSaveDismBatch = $null
        BtnSettingsResetDismBatch = $null
        TxtSettingsDismBatchHint = $null

        TxtSettingsProjectRoot = $null
        TxtSettingsLogFile = $null
        TxtSettingsConfigFile = $null
    }

    $p = $SettingsPage

    $script:ctx.TxtSettingsMountRoot = Find-Ui -Root $p -Name 'TxtSettingsMountRoot'
    $script:ctx.BtnSettingsPickMountRoot = Find-Ui -Root $p -Name 'BtnSettingsPickMountRoot'
    $script:ctx.BtnSettingsResetMountRoot = Find-Ui -Root $p -Name 'BtnSettingsResetMountRoot'
    $script:ctx.CmbSettingsStartPage = Find-Ui -Root $p -Name 'CmbSettingsStartPage'
    $script:ctx.CmbSettingsLanguage = Find-Ui -Root $p -Name 'CmbSettingsLanguage'
    $script:ctx.ChkSettingsDarkMode = Find-Ui -Root $p -Name 'ChkSettingsDarkMode'
    $script:ctx.ChkSettingsDriverLoadAllDefault = Find-Ui -Root $p -Name 'ChkSettingsDriverLoadAllDefault'
    $script:ctx.ChkSettingsUpdatesAutoCatalogDefault = Find-Ui -Root $p -Name 'ChkSettingsUpdatesAutoCatalogDefault'
    $script:ctx.ChkSettingsImageMountReadOnlyDefault = Find-Ui -Root $p -Name 'ChkSettingsImageMountReadOnlyDefault'
    $script:ctx.ChkSettingsNotificationsEnabled = Find-Ui -Root $p -Name 'ChkSettingsNotificationsEnabled'
    $script:ctx.BtnSettingsTestNotification = Find-Ui -Root $p -Name 'BtnSettingsTestNotification'
    $script:ctx.ChkSettingsAppDebug = Find-Ui -Root $p -Name 'ChkSettingsAppDebug'
    $script:ctx.BtnSettingsDetectAdk = Find-Ui -Root $p -Name 'BtnSettingsDetectAdk'
    $script:ctx.BtnSettingsPickAdkRoot = Find-Ui -Root $p -Name 'BtnSettingsPickAdkRoot'
    $script:ctx.BtnSettingsPickWinPeRoot = Find-Ui -Root $p -Name 'BtnSettingsPickWinPeRoot'
    $script:ctx.BtnSettingsPickOscdimgPath = Find-Ui -Root $p -Name 'BtnSettingsPickOscdimgPath'
    $script:ctx.BtnSettingsResetAdkRoot = Find-Ui -Root $p -Name 'BtnSettingsResetAdkRoot'
    $script:ctx.BtnSettingsResetWinPeRoot = Find-Ui -Root $p -Name 'BtnSettingsResetWinPeRoot'
    $script:ctx.BtnSettingsResetOscdimgPath = Find-Ui -Root $p -Name 'BtnSettingsResetOscdimgPath'
    $script:ctx.TxtSettingsAdkSummary = Find-Ui -Root $p -Name 'TxtSettingsAdkSummary'
    $script:ctx.TxtSettingsAdkRoot = Find-Ui -Root $p -Name 'TxtSettingsAdkRoot'
    $script:ctx.TxtSettingsWinPeRoot = Find-Ui -Root $p -Name 'TxtSettingsWinPeRoot'
    $script:ctx.TxtSettingsOscdimgPath = Find-Ui -Root $p -Name 'TxtSettingsOscdimgPath'
    $script:ctx.TxtSettingsCopypePath = Find-Ui -Root $p -Name 'TxtSettingsCopypePath'
    $script:ctx.TxtSettingsMakeWinPeMediaPath = Find-Ui -Root $p -Name 'TxtSettingsMakeWinPeMediaPath'

    $script:ctx.BtnSettingsHealthRefresh = Find-Ui -Root $p -Name 'BtnSettingsHealthRefresh'
    $script:ctx.BtnSettingsUnmountAllDiscard = Find-Ui -Root $p -Name 'BtnSettingsUnmountAllDiscard'
    $script:ctx.BtnSettingsCleanupEmptyMountDirs = Find-Ui -Root $p -Name 'BtnSettingsCleanupEmptyMountDirs'
    $script:ctx.TxtSettingsHealthSummary = Find-Ui -Root $p -Name 'TxtSettingsHealthSummary'
    $script:ctx.TxtSettingsHealthAdmin = Find-Ui -Root $p -Name 'TxtSettingsHealthAdmin'
    $script:ctx.TxtSettingsHealthDism = Find-Ui -Root $p -Name 'TxtSettingsHealthDism'
    $script:ctx.TxtSettingsHealthMountRoot = Find-Ui -Root $p -Name 'TxtSettingsHealthMountRoot'
    $script:ctx.TxtSettingsHealthDrive = Find-Ui -Root $p -Name 'TxtSettingsHealthDrive'
    $script:ctx.TxtSettingsHealthMountCount = Find-Ui -Root $p -Name 'TxtSettingsHealthMountCount'
    $script:ctx.TxtSettingsHealthLog = Find-Ui -Root $p -Name 'TxtSettingsHealthLog'
    $script:ctx.LstSettingsHealthMounts = Find-Ui -Root $p -Name 'LstSettingsHealthMounts'

    $script:ctx.BtnSettingsLogsRefresh = Find-Ui -Root $p -Name 'BtnSettingsLogsRefresh'
    $script:ctx.BtnSettingsOpenLogFolder = Find-Ui -Root $p -Name 'BtnSettingsOpenLogFolder'
    $script:ctx.BtnSettingsOpenCurrentLog = Find-Ui -Root $p -Name 'BtnSettingsOpenCurrentLog'
    $script:ctx.BtnSettingsOpenDismLog = Find-Ui -Root $p -Name 'BtnSettingsOpenDismLog'
    $script:ctx.BtnSettingsCleanupOldLogs = Find-Ui -Root $p -Name 'BtnSettingsCleanupOldLogs'
    $script:ctx.TxtSettingsLogsSummary = Find-Ui -Root $p -Name 'TxtSettingsLogsSummary'
    $script:ctx.TxtSettingsAppLogPath = Find-Ui -Root $p -Name 'TxtSettingsAppLogPath'
    $script:ctx.TxtSettingsDismLogPath = Find-Ui -Root $p -Name 'TxtSettingsDismLogPath'
    $script:ctx.CmbSettingsLogPreviewSource = Find-Ui -Root $p -Name 'CmbSettingsLogPreviewSource'
    $script:ctx.LstSettingsLogFiles = Find-Ui -Root $p -Name 'LstSettingsLogFiles'
    $script:ctx.TxtSettingsLogPreviewTitle = Find-Ui -Root $p -Name 'TxtSettingsLogPreviewTitle'
    $script:ctx.TxtSettingsLogPreview = Find-Ui -Root $p -Name 'TxtSettingsLogPreview'

    $script:ctx.TxtSettingsDismTimeoutSec = Find-Ui -Root $p -Name 'TxtSettingsDismTimeoutSec'
    $script:ctx.TxtSettingsDismLockTimeoutSec = Find-Ui -Root $p -Name 'TxtSettingsDismLockTimeoutSec'
    $script:ctx.TxtSettingsDismUnmountCommitTimeoutSec = Find-Ui -Root $p -Name 'TxtSettingsDismUnmountCommitTimeoutSec'
    $script:ctx.TxtSettingsDismUnmountCommitRetryCount = Find-Ui -Root $p -Name 'TxtSettingsDismUnmountCommitRetryCount'
    $script:ctx.TxtSettingsDismUnmountCommitRetryDelaySec = Find-Ui -Root $p -Name 'TxtSettingsDismUnmountCommitRetryDelaySec'
    $script:ctx.TxtSettingsMountedWimRefreshQuietPeriodSec = Find-Ui -Root $p -Name 'TxtSettingsMountedWimRefreshQuietPeriodSec'
    $script:ctx.TxtSettingsBatchUnmountStepDelaySec = Find-Ui -Root $p -Name 'TxtSettingsBatchUnmountStepDelaySec'
    $script:ctx.BtnSettingsSaveDismBatch = Find-Ui -Root $p -Name 'BtnSettingsSaveDismBatch'
    $script:ctx.BtnSettingsResetDismBatch = Find-Ui -Root $p -Name 'BtnSettingsResetDismBatch'
    $script:ctx.TxtSettingsDismBatchHint = Find-Ui -Root $p -Name 'TxtSettingsDismBatchHint'

    $script:ctx.TxtSettingsProjectRoot = Find-Ui -Root $p -Name 'TxtSettingsProjectRoot'
    $script:ctx.TxtSettingsLogFile = Find-Ui -Root $p -Name 'TxtSettingsLogFile'
    $script:ctx.TxtSettingsConfigFile = Find-Ui -Root $p -Name 'TxtSettingsConfigFile'

    if ($script:ctx.BtnSettingsPickMountRoot) {
        $script:ctx.BtnSettingsPickMountRoot.Add_Click({
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = (Get-UiString -Key 'DialogMountRoot')

                $cur = $null
                try { $cur = Get-AppStateValue -Key 'MountRoot' -Default $null } catch {}
                if ($cur) { $dlg.SelectedPath = $cur }

                $ok = $dlg.ShowDialog()
                if ($ok -ne [System.Windows.Forms.DialogResult]::OK) { return }

                Set-MountRoot -Path $dlg.SelectedPath -Persist | Out-Null

                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'SettingsMountRootSet') } catch {} }
                Start-SettingsHealthRefresh -StatusText (Get-UiString -Key 'SettingsHealthAfterMountRootChange')
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetMountRoot) {
        $script:ctx.BtnSettingsResetMountRoot.Add_Click({
            try {
                try { Set-AppStateValue -Key 'MountRoot' -Value $null } catch {}
                try { Set-SettingsConfigValue -Key 'MountRoot' -Value $null -Persist } catch {}
                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'SettingsMountRootReset') } catch {} }
                Start-SettingsHealthRefresh -StatusText (Get-UiString -Key 'SettingsHealthAfterMountRootReset')
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.CmbSettingsStartPage) {
        $script:ctx.CmbSettingsStartPage.Add_SelectionChanged({
            if ($script:suppressSettingsEvents) { return }
            $selected = Get-SelectedSettingsComboTag -ComboBox $script:ctx.CmbSettingsStartPage -Default 'Dashboard'
            Save-SettingsValue -Key 'StartPage' -Value $selected -StatusMessage (Get-UiString -Key 'SettingsStartPageStatus' -Args @($selected))
        })
    }

    if ($script:ctx.CmbSettingsLanguage) {
        $script:ctx.CmbSettingsLanguage.Add_SelectionChanged({
            if ($script:suppressSettingsEvents) { return }
            $selected = Get-SelectedSettingsComboTag -ComboBox $script:ctx.CmbSettingsLanguage -Default 'de'
            Set-UiLanguage -Language $selected | Out-Null
            Refresh-SettingsUI
            if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
            if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'SettingsLanguageStatus' -Args @((Get-UiLanguageLabel -LanguageCode $selected))) } catch {} }
        })
    }

    if ($script:ctx.ChkSettingsDarkMode) {
        $script:ctx.ChkSettingsDarkMode.Add_Click({
            if ($script:suppressSettingsEvents) { return }
            $theme = if ([bool]$script:ctx.ChkSettingsDarkMode.IsChecked) { 'Dark' } else { 'Light' }
            Set-UiTheme -Theme $theme | Out-Null
            if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
            $labelKey = if ($theme -eq 'Dark') { 'SettingsThemeDark' } else { 'SettingsThemeLight' }
            if ($script:ctx.SetStatus) {
                try { & $script:ctx.SetStatus (Get-UiString -Key 'SettingsThemeUpdated' -Args @((Get-UiString -Key $labelKey))) } catch {}
            }
        })
    }

    if ($script:ctx.BtnSettingsDetectAdk) {
        $script:ctx.BtnSettingsDetectAdk.Add_Click({
            try {
                $status = Detect-AndSaveAdkDefaults
                if ($script:ctx.SetStatus) {
                    $msg = if ($status.HasAdkRoot) { Get-UiString -Key 'SettingsAdkDetected' } else { Get-UiString -Key 'SettingsAdkNotFound' }
                    try { & $script:ctx.SetStatus $msg } catch {}
                }
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsPickAdkRoot) {
        $script:ctx.BtnSettingsPickAdkRoot.Add_Click({
            try {
                $initial = [string](Get-SettingsConfigValue -Key 'AdkRoot' -Default $null)
                $picked = Pick-SettingsFolderPath -Description (Get-UiString -Key 'DialogAdkFolder') -InitialPath $initial
                if (-not $picked) { return }
                Save-SettingsValue -Key 'AdkRoot' -Value $picked -StatusMessage (Get-UiString -Key 'SettingsAdkRootSet')
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsPickWinPeRoot) {
        $script:ctx.BtnSettingsPickWinPeRoot.Add_Click({
            try {
                $initial = [string](Get-SettingsConfigValue -Key 'WinPeRoot' -Default $null)
                $picked = Pick-SettingsFolderPath -Description (Get-UiString -Key 'DialogWinPeFolder') -InitialPath $initial
                if (-not $picked) { return }
                Save-SettingsValue -Key 'WinPeRoot' -Value $picked -StatusMessage (Get-UiString -Key 'SettingsWinPeRootSet')
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsPickOscdimgPath) {
        $script:ctx.BtnSettingsPickOscdimgPath.Add_Click({
            try {
                $initial = [string](Get-SettingsConfigValue -Key 'OscdimgPath' -Default $null)
                $picked = Pick-SettingsFilePath -Title (Get-UiString -Key 'DialogOscdimg') -Filter 'oscdimg.exe|oscdimg.exe|Executables (*.exe)|*.exe|Alle Dateien (*.*)|*.*' -InitialPath $initial
                if (-not $picked) { return }
                Save-SettingsValue -Key 'OscdimgPath' -Value $picked -StatusMessage (Get-UiString -Key 'SettingsOscdimgSet')
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetAdkRoot) {
        $script:ctx.BtnSettingsResetAdkRoot.Add_Click({
            try {
                Save-SettingsValue -Key 'AdkRoot' -Value $null -StatusMessage (Get-UiString -Key 'SettingsAdkRootReset')
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetWinPeRoot) {
        $script:ctx.BtnSettingsResetWinPeRoot.Add_Click({
            try {
                Save-SettingsValue -Key 'WinPeRoot' -Value $null -StatusMessage (Get-UiString -Key 'SettingsWinPeRootReset')
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetOscdimgPath) {
        $script:ctx.BtnSettingsResetOscdimgPath.Add_Click({
            try {
                Save-SettingsValue -Key 'OscdimgPath' -Value $null -StatusMessage (Get-UiString -Key 'SettingsOscdimgReset')
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.ChkSettingsDriverLoadAllDefault) {
        $script:ctx.ChkSettingsDriverLoadAllDefault.Add_Click({
            Save-SettingsValue -Key 'DriverLoadAllDefault' -Value ([bool]$script:ctx.ChkSettingsDriverLoadAllDefault.IsChecked) -StatusMessage (Get-UiString -Key 'SettingsDriverDefaultsUpdated')
        })
    }

    if ($script:ctx.ChkSettingsUpdatesAutoCatalogDefault) {
        $script:ctx.ChkSettingsUpdatesAutoCatalogDefault.Add_Click({
            Save-SettingsValue -Key 'UpdatesAutoCatalogDefault' -Value ([bool]$script:ctx.ChkSettingsUpdatesAutoCatalogDefault.IsChecked) -StatusMessage (Get-UiString -Key 'SettingsUpdatesDefaultsUpdated')
        })
    }

    if ($script:ctx.ChkSettingsImageMountReadOnlyDefault) {
        $script:ctx.ChkSettingsImageMountReadOnlyDefault.Add_Click({
            Save-SettingsValue -Key 'ImageMountReadOnlyDefault' -Value ([bool]$script:ctx.ChkSettingsImageMountReadOnlyDefault.IsChecked) -StatusMessage (Get-UiString -Key 'SettingsMountDefaultsUpdated')
        })
    }

    if ($script:ctx.ChkSettingsNotificationsEnabled) {
        $script:ctx.ChkSettingsNotificationsEnabled.Add_Click({
            $enabled = [bool]$script:ctx.ChkSettingsNotificationsEnabled.IsChecked
            Save-SettingsValue -Key 'NotificationsEnabled' -Value $enabled -StatusMessage (Get-UiString -Key 'SettingsNotificationsUpdated')
            if ($enabled) {
                try { Initialize-AppNotifications -ProjectRoot (Get-ProjectRoot) | Out-Null } catch {}
            }
        })
    }

    if ($script:ctx.BtnSettingsTestNotification) {
        $script:ctx.BtnSettingsTestNotification.Add_Click({
            try {
                if ($script:ctx.ChkSettingsNotificationsEnabled -and $script:ctx.ChkSettingsNotificationsEnabled.IsChecked -ne $true) {
                    $script:ctx.ChkSettingsNotificationsEnabled.IsChecked = $true
                    Save-SettingsValue -Key 'NotificationsEnabled' -Value $true -StatusMessage (Get-UiString -Key 'SettingsNotificationsUpdated')
                }

                $shown = Show-AppToastNotification -Title (Get-UiString -Key 'NotificationTestTitle') -Message (Get-UiString -Key 'NotificationTestMessage') -Level Info
                $statusKey = if ($shown) { 'SettingsTestNotificationSent' } else { 'SettingsTestNotificationFailed' }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key $statusKey) } catch {} }

                if (-not $shown) {
                    Show-UiInfo -Title (Get-UiString -Key 'StaticInfoTitle') -Message (Get-UiString -Key 'SettingsTestNotificationFailed')
                }
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.ChkSettingsAppDebug) {
        $script:ctx.ChkSettingsAppDebug.Add_Click({
            Save-SettingsValue -Key 'AppDebug' -Value ([bool]$script:ctx.ChkSettingsAppDebug.IsChecked) -StatusMessage (Get-UiString -Key 'SettingsDebugUpdated')
            Start-SettingsHealthRefresh -StatusText (Get-UiString -Key 'SettingsHealthAfterDebugChange')
        })
    }

    if ($script:ctx.BtnSettingsHealthRefresh) {
        $script:ctx.BtnSettingsHealthRefresh.Add_Click({
            Start-SettingsHealthRefresh
        })
    }

    if ($script:ctx.BtnSettingsUnmountAllDiscard) {
        $script:ctx.BtnSettingsUnmountAllDiscard.Add_Click({
            Start-SettingsUnmountAllDiscard
        })
    }

    if ($script:ctx.BtnSettingsCleanupEmptyMountDirs) {
        $script:ctx.BtnSettingsCleanupEmptyMountDirs.Add_Click({
            Start-SettingsCleanupEmptyMountDirs
        })
    }

    if ($script:ctx.BtnSettingsLogsRefresh) {
        $script:ctx.BtnSettingsLogsRefresh.Add_Click({
            Refresh-SettingsLogsUI
            if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'LogsRefreshed') } catch {} }
        })
    }

    if ($script:ctx.BtnSettingsOpenLogFolder) {
        $script:ctx.BtnSettingsOpenLogFolder.Add_Click({
            try {
                Open-SettingsPath -Path (Get-SettingsLogDirectory)
            } catch {
                Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'LogsTitle')
            }
        })
    }

    if ($script:ctx.BtnSettingsOpenCurrentLog) {
        $script:ctx.BtnSettingsOpenCurrentLog.Add_Click({
            try {
                Open-SettingsPath -Path (Get-SettingsCurrentLogPath)
            } catch {
                Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'LogsTitle')
            }
        })
    }

    if ($script:ctx.BtnSettingsOpenDismLog) {
        $script:ctx.BtnSettingsOpenDismLog.Add_Click({
            try {
                Open-SettingsPath -Path (Get-SettingsDismLogPath)
            } catch {
                Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'LogsTitle')
            }
        })
    }

    if ($script:ctx.BtnSettingsCleanupOldLogs) {
        $script:ctx.BtnSettingsCleanupOldLogs.Add_Click({
            try {
                $retentionDays = 30
                if (-not (Confirm-SettingsLogCleanup -RetentionDays $retentionDays)) {
                    if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'LogsCleanupCancelled') } catch {} }
                    return
                }

                $result = Remove-SettingsOldAppLogs -RetentionDays $retentionDays
                Refresh-SettingsLogsUI
                if ($script:ctx.SetStatus) {
                    try {
                        & $script:ctx.SetStatus (Get-UiString -Key 'LogsCleanupCompleted' -Args @(
                            [int]$result.RemovedCount,
                            (Format-SettingsByteSize -Bytes ([int64]$result.RemovedBytes))
                        ))
                    } catch {}
                }
            } catch {
                Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'LogsCleanupTitle')
            }
        })
    }

    if ($script:ctx.CmbSettingsLogPreviewSource) {
        $script:ctx.CmbSettingsLogPreviewSource.Add_SelectionChanged({
            if ($script:suppressSettingsEvents) { return }
            Refresh-SettingsLogsUI
        })
    }

    if ($script:ctx.BtnSettingsSaveDismBatch) {
        $script:ctx.BtnSettingsSaveDismBatch.Add_Click({
            try {
                Save-SettingsDismBatchValues
            } catch {
                Show-UiError -Message $_.Exception.Message -Title 'DISM & Batch'
            }
        })
    }

    if ($script:ctx.BtnSettingsResetDismBatch) {
        $script:ctx.BtnSettingsResetDismBatch.Add_Click({
            try {
                Reset-SettingsDismBatchValues
            } catch {
                Show-UiError -Message $_.Exception.Message -Title 'DISM & Batch'
            }
        })
    }

    Refresh-SettingsUI
    Set-SettingsHealthBusy -Busy $false
    Start-SettingsDeferredHealthRefresh -StatusText (Get-UiString -Key 'HealthInitiallyLoaded') -DelayMs 650
}

Export-ModuleMember -Function Initialize-SettingsController, Refresh-SettingsUI
