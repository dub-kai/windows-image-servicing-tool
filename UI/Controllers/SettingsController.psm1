Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\UiAsync.psm1" -MustExist) -Force -DisableNameChecking -Global
$script:configModule = Get-Module -Name 'Config' | Select-Object -First 1
if (-not $script:configModule) {
    $script:configModule = Import-Module (Resolve-ProjectPath "Core\Config.psm1" -MustExist) -DisableNameChecking -Global -PassThru
}
Import-Module (Resolve-ProjectPath "UI\Localization.psm1" -MustExist) -Force -DisableNameChecking -Global
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

function Set-SettingsHealthBusy {
    param([Parameter(Mandatory)][bool]$Busy)

    $script:isHealthBusy = $Busy
    if (-not $script:ctx) { return }

    foreach ($name in @(
        'BtnSettingsHealthRefresh',
        'BtnSettingsUnmountAllDiscard',
        'BtnSettingsCleanupEmptyMountDirs'
    )) {
        $el = $script:ctx[$name]
        if ($el -and $el.PSObject.Properties.Match('IsEnabled').Count -gt 0) {
            try { $el.IsEnabled = (-not $Busy) } catch {}
        }
    }
}

function Set-SettingsHealthSummary {
    param([string]$Message)

    if (-not $script:ctx -or -not $script:ctx.TxtSettingsHealthSummary) { return }
    try { $script:ctx.TxtSettingsHealthSummary.Text = (Get-DisplayValue $Message) } catch {}
}

function Show-SettingsHealthData {
    param([Parameter(Mandatory)]$Data)

    if (-not $script:ctx) { return }

    try {
        if ($script:ctx.TxtSettingsHealthAdmin) {
            $script:ctx.TxtSettingsHealthAdmin.Text = (Get-DisplayValue (Get-LocalizedText -Text ([string]$Data.AdminStatus)))
        }

        if ($script:ctx.TxtSettingsHealthDism) {
            $script:ctx.TxtSettingsHealthDism.Text = (Get-DisplayValue (Get-LocalizedText -Text ([string]$Data.DismStatus)))
        }

        if ($script:ctx.TxtSettingsHealthMountRoot) {
            $script:ctx.TxtSettingsHealthMountRoot.Text = (Get-DisplayValue (Get-LocalizedText -Text ([string]$Data.MountRootStatus)))
        }

        if ($script:ctx.TxtSettingsHealthDrive) {
            $script:ctx.TxtSettingsHealthDrive.Text = (Get-DisplayValue (Get-LocalizedText -Text ([string]$Data.DriveStatus)))
        }

        if ($script:ctx.TxtSettingsHealthMountCount) {
            $script:ctx.TxtSettingsHealthMountCount.Text = (Get-DisplayValue (Get-LocalizedText -Text ([string]$Data.MountCountStatus)))
        }

        if ($script:ctx.TxtSettingsHealthLog) {
            $script:ctx.TxtSettingsHealthLog.Text = (Get-DisplayValue $Data.LogStatus)
        }

        if ($script:ctx.LstSettingsHealthMounts) {
            $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
            foreach ($entry in @($Data.MountEntries)) { [void]$items.Add($entry) }
            $script:ctx.LstSettingsHealthMounts.ItemsSource = $items
        }

        Set-SettingsHealthSummary -Message (Get-LocalizedText -Text ([string]$Data.Summary))
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Start-SettingsHealthRefresh {
    param(
        [string]$StatusText = 'Health: Status aktualisiert'
    )

    if (-not $script:ctx) { return }
    if ($script:isHealthBusy) { return }

    Set-SettingsHealthBusy -Busy $true
    Set-SettingsHealthSummary -Message (Get-UiString -Key 'HealthLoading')

    $projectRoot = Get-ProjectRoot
    $safeProjectRoot = $projectRoot.Replace("'", "''")
    $coreBoot    = (Resolve-ProjectPath "Core\Bootstrap.psm1" -MustExist)
    $coreCfg     = (Resolve-ProjectPath "Core\Config.psm1" -MustExist)
    $coreLog     = (Resolve-ProjectPath "Core\Logger.psm1" -MustExist)
    $svcDism     = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist)
    $svcMount    = (Resolve-ProjectPath "Services\MountService.psm1" -MustExist)
    $svcMounted  = (Resolve-ProjectPath "Services\MountedWimService.psm1" -MustExist)

    $safeBoot   = $coreBoot.Replace("'", "''")
    $safeCfg    = $coreCfg.Replace("'", "''")
    $safeLog    = $coreLog.Replace("'", "''")
    $safeDism   = $svcDism.Replace("'", "''")
    $safeMount  = $svcMount.Replace("'", "''")
    $safeMntSvc = $svcMounted.Replace("'", "''")

    $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$safeBoot' -Force -DisableNameChecking
Set-ProjectRoot -Path '$safeProjectRoot' | Out-Null
Import-Module '$safeCfg' -Force -DisableNameChecking
Import-Module '$safeLog' -Force -DisableNameChecking
Import-Module '$safeDism' -Force -DisableNameChecking
Import-Module '$safeMount' -Force -DisableNameChecking
Import-Module '$safeMntSvc' -Force -DisableNameChecking

function Test-HealthAdmin {
    try {
        `$id = [Security.Principal.WindowsIdentity]::GetCurrent()
        `$p  = New-Object Security.Principal.WindowsPrincipal(`$id)
        return `$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return `$false
    }
}

`$mountRoot = Get-MountRoot
`$mounts = @()
try { `$mounts = @(Get-MountedWimList) } catch { `$mounts = @() }
`$activeMounts = @(`$mounts | Where-Object {
    `$registryOnly = `$false
    if (`$_.PSObject.Properties.Match('RegistryOnly').Count -gt 0) {
        try { `$registryOnly = [bool]`$_.RegistryOnly } catch { `$registryOnly = `$false }
    }
    -not `$registryOnly
})
`$registryRests = @(`$mounts | Where-Object {
    `$registryOnly = `$false
    if (`$_.PSObject.Properties.Match('RegistryOnly').Count -gt 0) {
        try { `$registryOnly = [bool]`$_.RegistryOnly } catch { `$registryOnly = `$false }
    }
    `$registryOnly
})

`$dismExe = Join-Path `$env:WINDIR 'System32\dism.exe'
if (-not (Test-Path -LiteralPath `$dismExe)) { `$dismExe = 'dism.exe' }

`$driveStatus = 'Unbekannt'
try {
    `$rootPath = [System.IO.Path]::GetPathRoot(`$mountRoot)
    `$drive = New-Object System.IO.DriveInfo(`$rootPath)
    `$freeGb = [Math]::Round((`$drive.AvailableFreeSpace / 1GB), 2)
    `$totalGb = [Math]::Round((`$drive.TotalSize / 1GB), 2)
    `$driveStatus = ('{0}: {1} GB frei von {2} GB' -f `$drive.Name.TrimEnd('\'), `$freeGb, `$totalGb)
} catch {
    `$driveStatus = 'Freier Platz konnte nicht gelesen werden.'
}

`$mountEntries = @(
    foreach (`$m in `$mounts) {
        `$health = ''
        `$action = ''
        `$registryOnly = `$false
        if (`$m.PSObject.Properties.Match('Health').Count -gt 0) { `$health = [string]`$m.Health }
        if (`$m.PSObject.Properties.Match('RecommendedAction').Count -gt 0) { `$action = [string]`$m.RecommendedAction }
        if (`$m.PSObject.Properties.Match('RegistryOnly').Count -gt 0) { try { `$registryOnly = [bool]`$m.RegistryOnly } catch { `$registryOnly = `$false } }

        [pscustomobject]@{
            Text = if (`$registryOnly) {
                ('{0} | {1} | {2}' -f [string]`$m.MountDir, `$health, `$action)
            } else {
                ('{0} | Index {1} | {2} | {3}' -f [string]`$m.MountDir, [string]`$m.ImageIndex, [string]`$m.ReadWrite, `$health)
            }
        }
    }
)

`$summary = if (@(`$activeMounts).Count -gt 0 -or @(`$registryRests).Count -gt 0) {
    '{0} aktive Mounts, {1} Registry-Rest(e) erkannt.' -f @(`$activeMounts).Count, @(`$registryRests).Count
} else {
    'Keine aktiven Mounts erkannt.'
}

[pscustomobject]@{
    Summary          = `$summary
    AdminStatus      = `$(if (Test-HealthAdmin) { 'OK - App läuft mit Adminrechten' } else { 'Fehlt - Adminrechte werden für DISM benötigt' })
    DismStatus       = `$(if (Test-Path -LiteralPath `$dismExe) { ('OK - {0}' -f `$dismExe) } else { 'DISM nicht gefunden' })
    MountRootStatus  = `$(if (Test-Path -LiteralPath `$mountRoot) { ('OK - {0}' -f `$mountRoot) } else { ('Fehlt - {0}' -f `$mountRoot) })
    DriveStatus      = `$driveStatus
    MountCountStatus = ('{0} aktive Mounts, {1} Registry-Rest(e)' -f @(`$activeMounts).Count, @(`$registryRests).Count)
    LogStatus        = (Get-LogFilePath)
    MountEntries     = `$mountEntries
}
"@

    Start-UiTask -Label 'Settings:HealthRefresh' -Work ([scriptblock]::Create($code)) -OnCompleted {
        param($result)
        Set-SettingsHealthBusy -Busy $false
        $item = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
        if ($item) {
            Show-SettingsHealthData -Data $item
        }
        if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus $StatusText } catch {} }
    } -OnError {
        param($ex)
        Set-SettingsHealthBusy -Busy $false
        Set-SettingsHealthSummary -Message (Get-UiString -Key 'HealthLoadFailed')
        Show-UiError -Message $ex.Message -Title (Get-UiString -Key 'HealthTitle')
    }
}

function Start-SettingsUnmountAllDiscard {
    if (-not $script:ctx) { return }
    if ($script:isHealthBusy) { return }

    Set-SettingsHealthBusy -Busy $true
    Set-SettingsHealthSummary -Message (Get-UiString -Key 'HealthUnmountingAll')

    $projectRoot = Get-ProjectRoot
    $safeProjectRoot = $projectRoot.Replace("'", "''")
    $coreBoot    = (Resolve-ProjectPath "Core\Bootstrap.psm1" -MustExist)
    $coreCfg     = (Resolve-ProjectPath "Core\Config.psm1" -MustExist)
    $coreLog     = (Resolve-ProjectPath "Core\Logger.psm1" -MustExist)
    $svcDism     = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist)
    $svcMount    = (Resolve-ProjectPath "Services\MountService.psm1" -MustExist)
    $svcMounted  = (Resolve-ProjectPath "Services\MountedWimService.psm1" -MustExist)

    $safeBoot   = $coreBoot.Replace("'", "''")
    $safeCfg    = $coreCfg.Replace("'", "''")
    $safeLog    = $coreLog.Replace("'", "''")
    $safeDism   = $svcDism.Replace("'", "''")
    $safeMount  = $svcMount.Replace("'", "''")
    $safeMntSvc = $svcMounted.Replace("'", "''")

    $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$safeBoot' -Force -DisableNameChecking
Set-ProjectRoot -Path '$safeProjectRoot' | Out-Null
Import-Module '$safeCfg' -Force -DisableNameChecking
Import-Module '$safeLog' -Force -DisableNameChecking
Import-Module '$safeDism' -Force -DisableNameChecking
Import-Module '$safeMount' -Force -DisableNameChecking
Import-Module '$safeMntSvc' -Force -DisableNameChecking

`$mounts = @(Get-MountedWimList)
`$done = New-Object System.Collections.Generic.List[string]
`$skippedRegistry = New-Object System.Collections.Generic.List[string]

foreach (`$m in `$mounts) {
    if (`$null -eq `$m) { continue }
    `$dir = [string]`$m.MountDir
    if ([string]::IsNullOrWhiteSpace(`$dir)) { continue }

    `$registryOnly = `$false
    if (`$m.PSObject.Properties.Match('RegistryOnly').Count -gt 0) {
        try { `$registryOnly = [bool]`$m.RegistryOnly } catch { `$registryOnly = `$false }
    }

    `$canDiscard = `$true
    if (`$m.PSObject.Properties.Match('CanDiscard').Count -gt 0) {
        try { `$canDiscard = [bool]`$m.CanDiscard } catch { `$canDiscard = `$false }
    }

    if (`$registryOnly -or -not `$canDiscard) {
        `$skippedRegistry.Add(`$dir) | Out-Null
        continue
    }

    Unmount-WimImage -MountDir `$dir -Discard | Out-Null
    `$done.Add(`$dir) | Out-Null
}

`$cleanupRan = `$false
`$cleanupOk = `$false
`$cleanupError = `$null
if (`$skippedRegistry.Count -gt 0) {
    `$cleanupRan = `$true
    try {
        Repair-WimMountRegistry -TimeoutSec 900 | Out-Null
        `$cleanupOk = `$true
    } catch {
        `$cleanupError = `$_.Exception.Message
    }
}

[pscustomobject]@{
    Count              = @(`$done.ToArray()).Count
    Mounts             = @(`$done.ToArray())
    RegistryRestCount  = @(`$skippedRegistry.ToArray()).Count
    RegistryRests      = @(`$skippedRegistry.ToArray())
    CleanupRan         = `$cleanupRan
    CleanupOk          = `$cleanupOk
    CleanupError       = `$cleanupError
}
"@

    Start-UiTask -Label 'Settings:UnmountAllDiscard' -TimeoutSec 7200 -Work ([scriptblock]::Create($code)) -OnCompleted {
        param($result)
        Set-SettingsHealthBusy -Busy $false
        $item = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
        $count = 0
        if ($item) { try { $count = [int]$item.Count } catch { $count = 0 } }
        $registryRestCount = 0
        if ($item) { try { $registryRestCount = [int]$item.RegistryRestCount } catch { $registryRestCount = 0 } }
        $cleanupRan = $false
        if ($item) { try { $cleanupRan = [bool]$item.CleanupRan } catch { $cleanupRan = $false } }
        $cleanupOk = $false
        if ($item) { try { $cleanupOk = [bool]$item.CleanupOk } catch { $cleanupOk = $false } }

        $statusText = Get-UiString -Key 'SettingsUnmountCompleted' -Args @($count)
        if ($cleanupRan -and $cleanupOk) {
            $statusText = Get-UiString -Key 'SettingsUnmountCompletedWithCleanup' -Args @($count, $registryRestCount)
        } elseif ($cleanupRan) {
            $statusText = Get-UiString -Key 'SettingsUnmountCleanupFailed' -Args @($count, $registryRestCount)
        }

        $refreshText = if ($cleanupRan) {
            Get-UiString -Key 'SettingsHealthAfterUnmountWithCleanup' -Args @($count, $registryRestCount)
        } else {
            Get-UiString -Key 'SettingsHealthAfterUnmount' -Args @($count)
        }

        if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus $statusText } catch {} }
        Start-SettingsHealthRefresh -StatusText $refreshText
    } -OnError {
        param($ex)
        Set-SettingsHealthBusy -Busy $false
        Set-SettingsHealthSummary -Message (Get-UiString -Key 'HealthLoadFailed')
        Show-UiError -Message $ex.Message -Title (Get-UiString -Key 'UnmountAllTitle')
    }
}

function Start-SettingsCleanupEmptyMountDirs {
    if (-not $script:ctx) { return }
    if ($script:isHealthBusy) { return }

    Set-SettingsHealthBusy -Busy $true
    Set-SettingsHealthSummary -Message (Get-UiString -Key 'HealthCleanupDirs')

    $projectRoot = Get-ProjectRoot
    $safeProjectRoot = $projectRoot.Replace("'", "''")
    $coreBoot    = (Resolve-ProjectPath "Core\Bootstrap.psm1" -MustExist)
    $coreCfg     = (Resolve-ProjectPath "Core\Config.psm1" -MustExist)
    $coreLog     = (Resolve-ProjectPath "Core\Logger.psm1" -MustExist)
    $svcMount    = (Resolve-ProjectPath "Services\MountService.psm1" -MustExist)

    $safeBoot  = $coreBoot.Replace("'", "''")
    $safeCfg   = $coreCfg.Replace("'", "''")
    $safeLog   = $coreLog.Replace("'", "''")
    $safeMount = $svcMount.Replace("'", "''")

    $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$safeBoot' -Force -DisableNameChecking
Set-ProjectRoot -Path '$safeProjectRoot' | Out-Null
Import-Module '$safeCfg' -Force -DisableNameChecking
Import-Module '$safeLog' -Force -DisableNameChecking
Import-Module '$safeMount' -Force -DisableNameChecking

function Test-WorkerPathWithinRoot {
    param(
        [Parameter(Mandatory)][string]`$RootPath,
        [Parameter(Mandatory)][string]`$CandidatePath
    )

    `$rootFull = [System.IO.Path]::GetFullPath(`$RootPath).TrimEnd('\')
    `$candFull = [System.IO.Path]::GetFullPath(`$CandidatePath).TrimEnd('\')

    if (`$candFull -eq `$rootFull) { return `$true }
    return `$candFull.StartsWith(`$rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

`$mountRoot = Get-MountRoot
if (-not (Test-Path -LiteralPath `$mountRoot)) {
    [pscustomobject]@{
        RemovedCount = 0
        RemovedPaths = @()
    }
    return
}

`$dirs = @(Get-ChildItem -LiteralPath `$mountRoot -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object { `$_.FullName.Length } -Descending)
`$removed = New-Object System.Collections.Generic.List[string]

foreach (`$dir in `$dirs) {
    if (`$null -eq `$dir) { continue }
    `$path = [string]`$dir.FullName
    if (-not (Test-WorkerPathWithinRoot -RootPath `$mountRoot -CandidatePath `$path)) { continue }

    `$children = @(Get-ChildItem -LiteralPath `$path -Force -ErrorAction SilentlyContinue)
    if (@(`$children).Count -gt 0) { continue }

    Remove-Item -LiteralPath `$path -Force
    `$removed.Add(`$path) | Out-Null
}

[pscustomobject]@{
    RemovedCount = @(`$removed.ToArray()).Count
    RemovedPaths = @(`$removed.ToArray())
}
"@

    Start-UiTask -Label 'Settings:CleanupEmptyMountDirs' -Work ([scriptblock]::Create($code)) -OnCompleted {
        param($result)
        Set-SettingsHealthBusy -Busy $false
        $item = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
        $count = 0
        if ($item) { try { $count = [int]$item.RemovedCount } catch { $count = 0 } }
        if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'SettingsCleanupCompleted' -Args @($count)) } catch {} }
        Start-SettingsHealthRefresh -StatusText (Get-UiString -Key 'SettingsHealthAfterCleanup' -Args @($count))
    } -OnError {
        param($ex)
        Set-SettingsHealthBusy -Busy $false
        Set-SettingsHealthSummary -Message (Get-UiString -Key 'HealthLoadFailed')
        Show-UiError -Message $ex.Message -Title (Get-UiString -Key 'CleanupTitle')
    }
}

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

        if ($script:ctx.CmbSettingsStartPage) {
            $startPage = [string](Get-SettingsConfigValue -Key 'StartPage' -Default 'Dashboard')
            Set-SettingsComboToTag -ComboBox $script:ctx.CmbSettingsStartPage -Tag $startPage
        }

        if ($script:ctx.CmbSettingsLanguage) {
            $language = [string](Get-SettingsConfigValue -Key 'UiLanguage' -Default 'de')
            Set-SettingsComboToTag -ComboBox $script:ctx.CmbSettingsLanguage -Tag $language
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

        TxtSettingsMountRoot = $null
        BtnSettingsPickMountRoot = $null
        BtnSettingsResetMountRoot = $null
        CmbSettingsStartPage = $null
        CmbSettingsLanguage = $null
        ChkSettingsDriverLoadAllDefault = $null
        ChkSettingsUpdatesAutoCatalogDefault = $null
        ChkSettingsImageMountReadOnlyDefault = $null
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
    $script:ctx.ChkSettingsDriverLoadAllDefault = Find-Ui -Root $p -Name 'ChkSettingsDriverLoadAllDefault'
    $script:ctx.ChkSettingsUpdatesAutoCatalogDefault = Find-Ui -Root $p -Name 'ChkSettingsUpdatesAutoCatalogDefault'
    $script:ctx.ChkSettingsImageMountReadOnlyDefault = Find-Ui -Root $p -Name 'ChkSettingsImageMountReadOnlyDefault'
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

    Refresh-SettingsUI
    Set-SettingsHealthBusy -Busy $false
    Start-SettingsHealthRefresh -StatusText (Get-UiString -Key 'HealthInitiallyLoaded')
}

Export-ModuleMember -Function Initialize-SettingsController, Refresh-SettingsUI
