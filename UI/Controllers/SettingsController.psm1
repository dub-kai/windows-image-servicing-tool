Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "UI\UiAsync.psm1" -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "Services\AdkService.psm1" -MustExist) -Force -DisableNameChecking

$script:ctx = $null
$script:suppressSettingsEvents = $false
$script:isHealthBusy = $false

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

function Get-CurrentAdkStatus {
    $adkRoot = [string](Get-ConfigValue -Key 'AdkRoot' -Default $null)
    $winPeRoot = [string](Get-ConfigValue -Key 'WinPeRoot' -Default $null)
    $oscdimgPath = [string](Get-ConfigValue -Key 'OscdimgPath' -Default $null)

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
                $script:ctx.TxtSettingsAdkSummary.Text = ('ADK-Status: gefunden -> {0}' -f ($parts -join ', '))
            } else {
                $script:ctx.TxtSettingsAdkSummary.Text = 'ADK-Status: nichts erkannt. ADK oder WinPE Add-on fehlt noch oder Pfade sind nicht gesetzt.'
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
    $dlg.Description = $Description
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
    $dlg.Title = $Title
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
        Set-ConfigValue -Key 'AdkRoot' -Value ([string]$status.AdkRoot) -Persist | Out-Null
    }
    if ($status.WinPeRoot) {
        Set-ConfigValue -Key 'WinPeRoot' -Value ([string]$status.WinPeRoot) -Persist | Out-Null
    }
    if ($status.OscdimgPath) {
        Set-ConfigValue -Key 'OscdimgPath' -Value ([string]$status.OscdimgPath) -Persist | Out-Null
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
            $script:ctx.TxtSettingsHealthAdmin.Text = (Get-DisplayValue $Data.AdminStatus)
        }

        if ($script:ctx.TxtSettingsHealthDism) {
            $script:ctx.TxtSettingsHealthDism.Text = (Get-DisplayValue $Data.DismStatus)
        }

        if ($script:ctx.TxtSettingsHealthMountRoot) {
            $script:ctx.TxtSettingsHealthMountRoot.Text = (Get-DisplayValue $Data.MountRootStatus)
        }

        if ($script:ctx.TxtSettingsHealthDrive) {
            $script:ctx.TxtSettingsHealthDrive.Text = (Get-DisplayValue $Data.DriveStatus)
        }

        if ($script:ctx.TxtSettingsHealthMountCount) {
            $script:ctx.TxtSettingsHealthMountCount.Text = (Get-DisplayValue $Data.MountCountStatus)
        }

        if ($script:ctx.TxtSettingsHealthLog) {
            $script:ctx.TxtSettingsHealthLog.Text = (Get-DisplayValue $Data.LogStatus)
        }

        if ($script:ctx.LstSettingsHealthMounts) {
            $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
            foreach ($entry in @($Data.MountEntries)) { [void]$items.Add($entry) }
            $script:ctx.LstSettingsHealthMounts.ItemsSource = $items
        }

        Set-SettingsHealthSummary -Message $Data.Summary
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
    Set-SettingsHealthSummary -Message 'Status wird aktualisiert...'

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
        [pscustomobject]@{
            Text = ('{0} | Index {1} | {2}' -f [string]`$m.MountDir, [string]`$m.ImageIndex, [string]`$m.ReadWrite)
        }
    }
)

`$summary = if (@(`$mounts).Count -gt 0) {
    '{0} aktive Mounts erkannt.' -f @(`$mounts).Count
} else {
    'Keine aktiven Mounts erkannt.'
}

[pscustomobject]@{
    Summary          = `$summary
    AdminStatus      = `$(if (Test-HealthAdmin) { 'OK - App läuft mit Adminrechten' } else { 'Fehlt - Adminrechte werden für DISM benötigt' })
    DismStatus       = `$(if (Test-Path -LiteralPath `$dismExe) { ('OK - {0}' -f `$dismExe) } else { 'DISM nicht gefunden' })
    MountRootStatus  = `$(if (Test-Path -LiteralPath `$mountRoot) { ('OK - {0}' -f `$mountRoot) } else { ('Fehlt - {0}' -f `$mountRoot) })
    DriveStatus      = `$driveStatus
    MountCountStatus = ('{0} aktive Mounts' -f @(`$mounts).Count)
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
        Set-SettingsHealthSummary -Message 'Status konnte nicht geladen werden.'
        Show-UiError -Message $ex.Message -Title 'Health'
    }
}

function Start-SettingsUnmountAllDiscard {
    if (-not $script:ctx) { return }
    if ($script:isHealthBusy) { return }

    Set-SettingsHealthBusy -Busy $true
    Set-SettingsHealthSummary -Message 'Alle Mounts werden mit Discard unmountet...'

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

foreach (`$m in `$mounts) {
    if (`$null -eq `$m) { continue }
    `$dir = [string]`$m.MountDir
    if ([string]::IsNullOrWhiteSpace(`$dir)) { continue }
    Unmount-WimImage -MountDir `$dir -Discard | Out-Null
    `$done.Add(`$dir) | Out-Null
}

[pscustomobject]@{
    Count = @(`$done.ToArray()).Count
    Mounts = @(`$done.ToArray())
}
"@

    Start-UiTask -Label 'Settings:UnmountAllDiscard' -TimeoutSec 7200 -Work ([scriptblock]::Create($code)) -OnCompleted {
        param($result)
        Set-SettingsHealthBusy -Busy $false
        $item = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
        $count = 0
        if ($item) { try { $count = [int]$item.Count } catch { $count = 0 } }
        if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus ("Settings: {0} Mount(s) mit Discard unmounted" -f $count) } catch {} }
        Start-SettingsHealthRefresh -StatusText ('Settings: Health nach Unmount aktualisiert ({0} Mount(s))' -f $count)
    } -OnError {
        param($ex)
        Set-SettingsHealthBusy -Busy $false
        Set-SettingsHealthSummary -Message 'Unmount aller Mounts fehlgeschlagen.'
        Show-UiError -Message $ex.Message -Title 'Unmount all'
    }
}

function Start-SettingsCleanupEmptyMountDirs {
    if (-not $script:ctx) { return }
    if ($script:isHealthBusy) { return }

    Set-SettingsHealthBusy -Busy $true
    Set-SettingsHealthSummary -Message 'Leere Mount-Ordner werden bereinigt...'

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
        if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus ("Settings: {0} leere Mount-Ordner bereinigt" -f $count) } catch {} }
        Start-SettingsHealthRefresh -StatusText ('Settings: Health nach Bereinigung aktualisiert ({0} Ordner)' -f $count)
    } -OnError {
        param($ex)
        Set-SettingsHealthBusy -Busy $false
        Set-SettingsHealthSummary -Message 'Leere Mount-Ordner konnten nicht bereinigt werden.'
        Show-UiError -Message $ex.Message -Title 'Cleanup'
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

        Refresh-SettingsAdkUI

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

        TxtSettingsMountRoot = $null
        BtnSettingsPickMountRoot = $null
        BtnSettingsResetMountRoot = $null
        CmbSettingsStartPage = $null
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

        TxtSettingsProjectRoot = $null
        TxtSettingsLogFile = $null
        TxtSettingsConfigFile = $null
    }

    $p = $SettingsPage

    $script:ctx.TxtSettingsMountRoot = Find-Ui -Root $p -Name 'TxtSettingsMountRoot'
    $script:ctx.BtnSettingsPickMountRoot = Find-Ui -Root $p -Name 'BtnSettingsPickMountRoot'
    $script:ctx.BtnSettingsResetMountRoot = Find-Ui -Root $p -Name 'BtnSettingsResetMountRoot'
    $script:ctx.CmbSettingsStartPage = Find-Ui -Root $p -Name 'CmbSettingsStartPage'
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

    $script:ctx.TxtSettingsProjectRoot = Find-Ui -Root $p -Name 'TxtSettingsProjectRoot'
    $script:ctx.TxtSettingsLogFile = Find-Ui -Root $p -Name 'TxtSettingsLogFile'
    $script:ctx.TxtSettingsConfigFile = Find-Ui -Root $p -Name 'TxtSettingsConfigFile'

    if ($script:ctx.BtnSettingsPickMountRoot) {
        $script:ctx.BtnSettingsPickMountRoot.Add_Click({
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = "MountRoot wählen (lokal, NTFS empfohlen)"

                $cur = $null
                try { $cur = Get-AppStateValue -Key 'MountRoot' -Default $null } catch {}
                if ($cur) { $dlg.SelectedPath = $cur }

                $ok = $dlg.ShowDialog()
                if ($ok -ne [System.Windows.Forms.DialogResult]::OK) { return }

                Set-MountRoot -Path $dlg.SelectedPath -Persist | Out-Null

                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus 'Settings: MountRoot gesetzt' } catch {} }
                Start-SettingsHealthRefresh -StatusText 'Settings: Health nach MountRoot-Änderung aktualisiert'
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetMountRoot) {
        $script:ctx.BtnSettingsResetMountRoot.Add_Click({
            try {
                try { Set-AppStateValue -Key 'MountRoot' -Value $null } catch {}
                try { Set-ConfigValue -Key 'MountRoot' -Value $null -Persist } catch {}
                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus 'Settings: MountRoot reset' } catch {} }
                Start-SettingsHealthRefresh -StatusText 'Settings: Health nach MountRoot-Reset aktualisiert'
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

    if ($script:ctx.BtnSettingsDetectAdk) {
        $script:ctx.BtnSettingsDetectAdk.Add_Click({
            try {
                $status = Detect-AndSaveAdkDefaults
                if ($script:ctx.SetStatus) {
                    $msg = if ($status.HasAdkRoot) { 'Settings: ADK automatisch erkannt' } else { 'Settings: ADK nicht gefunden' }
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
                $initial = [string](Get-ConfigValue -Key 'AdkRoot' -Default $null)
                $picked = Pick-SettingsFolderPath -Description 'ADK-Ordner wählen' -InitialPath $initial
                if (-not $picked) { return }
                Save-SettingsValue -Key 'AdkRoot' -Value $picked -StatusMessage 'Settings: ADK-Ordner gesetzt'
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsPickWinPeRoot) {
        $script:ctx.BtnSettingsPickWinPeRoot.Add_Click({
            try {
                $initial = [string](Get-ConfigValue -Key 'WinPeRoot' -Default $null)
                $picked = Pick-SettingsFolderPath -Description 'WinPE-Ordner wählen' -InitialPath $initial
                if (-not $picked) { return }
                Save-SettingsValue -Key 'WinPeRoot' -Value $picked -StatusMessage 'Settings: WinPE-Ordner gesetzt'
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsPickOscdimgPath) {
        $script:ctx.BtnSettingsPickOscdimgPath.Add_Click({
            try {
                $initial = [string](Get-ConfigValue -Key 'OscdimgPath' -Default $null)
                $picked = Pick-SettingsFilePath -Title 'oscdimg.exe wählen' -Filter 'oscdimg.exe|oscdimg.exe|Executables (*.exe)|*.exe|Alle Dateien (*.*)|*.*' -InitialPath $initial
                if (-not $picked) { return }
                Save-SettingsValue -Key 'OscdimgPath' -Value $picked -StatusMessage 'Settings: oscdimg.exe gesetzt'
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetAdkRoot) {
        $script:ctx.BtnSettingsResetAdkRoot.Add_Click({
            try {
                Save-SettingsValue -Key 'AdkRoot' -Value $null -StatusMessage 'Settings: ADK-Ordner zurückgesetzt'
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetWinPeRoot) {
        $script:ctx.BtnSettingsResetWinPeRoot.Add_Click({
            try {
                Save-SettingsValue -Key 'WinPeRoot' -Value $null -StatusMessage 'Settings: WinPE-Ordner zurückgesetzt'
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetOscdimgPath) {
        $script:ctx.BtnSettingsResetOscdimgPath.Add_Click({
            try {
                Save-SettingsValue -Key 'OscdimgPath' -Value $null -StatusMessage 'Settings: oscdimg.exe zurückgesetzt'
                Refresh-SettingsUI
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
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
            Start-SettingsHealthRefresh -StatusText 'Settings: Health nach Debug-Änderung aktualisiert'
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

    Refresh-SettingsUI
    Set-SettingsHealthBusy -Busy $false
    Start-SettingsHealthRefresh -StatusText 'Health: Initial geladen'
}

Export-ModuleMember -Function Initialize-SettingsController, Refresh-SettingsUI
