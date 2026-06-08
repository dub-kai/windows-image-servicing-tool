Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        [string]$StatusText = $(Get-UiString -Key 'HealthLoaded')
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

function Start-SettingsDeferredHealthRefresh {
    param(
        [string]$StatusText = $(Get-UiString -Key 'HealthLoaded'),
        [int]$DelayMs = 650
    )

    if (-not $script:ctx) { return }

    $page = $null
    try { $page = $script:ctx.Page } catch {}
    if (-not $page) {
        try { $page = $script:ctx.SettingsPage } catch {}
    }
    if (-not $page -or -not $page.Dispatcher) {
        Start-SettingsHealthRefresh -StatusText $StatusText
        return
    }

    try {
        if ($script:settingsDeferredHealthTimer) {
            try { $script:settingsDeferredHealthTimer.Stop() } catch {}
            $script:settingsDeferredHealthTimer = $null
        }

        $timer = New-Object System.Windows.Threading.DispatcherTimer(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
            $page.Dispatcher
        )
        $timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(100, $DelayMs))
        $timer.Add_Tick({
            try {
                $script:settingsDeferredHealthTimer.Stop()
                $script:settingsDeferredHealthTimer = $null
                Start-SettingsHealthRefresh -StatusText $StatusText
            } catch {
                try { Write-Log -Level WARN -Message ("Settings: deferred health refresh failed: {0}" -f $_.Exception.Message) } catch {}
            }
        }.GetNewClosure())

        $script:settingsDeferredHealthTimer = $timer
        $timer.Start()
    } catch {
        try { Write-Log -Level WARN -Message ("Settings: deferred health refresh could not start: {0}" -f $_.Exception.Message) } catch {}
        Start-SettingsHealthRefresh -StatusText $StatusText
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
