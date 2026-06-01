Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Wir speichern die Config als Hashtable im Modul-Scope.
$script:Config = $null
$script:ConfigFilePath = $null

function ConvertTo-HashtableRecursive {
    [CmdletBinding()]
    param(
        [Parameter()]
        $InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[[string]$key] = ConvertTo-HashtableRecursive -InputObject $InputObject[$key]
        }
        return $hash
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$list.Add((ConvertTo-HashtableRecursive -InputObject $item))
        }
        return @($list.ToArray())
    }

    $psProps = $null
    try { $psProps = @($InputObject.PSObject.Properties) } catch { $psProps = @() }
    if ($InputObject -is [psobject] -and @($psProps).Count -gt 0) {
        $hash = @{}
        foreach ($prop in $psProps) {
            $hash[[string]$prop.Name] = ConvertTo-HashtableRecursive -InputObject $prop.Value
        }
        return $hash
    }

    return $InputObject
}

function Get-ConfigFilePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectRoot
    )

    if ($script:ConfigFilePath) {
        return $script:ConfigFilePath
    }

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        try { $ProjectRoot = Get-ProjectRoot } catch { $ProjectRoot = (Get-Location).Path }
    }

    $workDir = Join-Path $ProjectRoot "Work"
    $cfgDir = Join-Path $workDir "Config"
    if (-not (Test-Path -LiteralPath $cfgDir)) {
        $null = New-Item -ItemType Directory -Path $cfgDir -Force
    }

    $script:ConfigFilePath = Join-Path $cfgDir "user-settings.json"
    return $script:ConfigFilePath
}

function Import-UserConfigOverrides {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectRoot
    )

    $path = Get-ConfigFilePath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @{}
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{}
        }

        $parsed = $raw | ConvertFrom-Json
        $hash = ConvertTo-HashtableRecursive -InputObject $parsed
        if ($hash -is [hashtable]) {
            return $hash
        }
    } catch {
        try {
            Write-Warning ("Config konnte nicht geladen werden: {0}" -f $_.Exception.Message)
        } catch {}
    }

    return @{}
}

function Test-ConfigKeyPersistable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $persistableKeys = @(
        "StartPage",
        "UiLanguage",
        "AppDebug",
        "MountRoot",
        "NotificationsEnabled",
        "NotificationMinimumDurationSec",
        "DriverLoadAllDefault",
        "UpdatesAutoCatalogDefault",
        "ImageMountReadOnlyDefault",
        "AdkRoot",
        "WinPeRoot",
        "OscdimgPath",
        "DismTimeoutSec",
        "DismLockTimeoutSec",
        "DismUnmountCommitTimeoutSec",
        "DismUnmountCommitRetryCount",
        "DismUnmountCommitRetryDelaySec",
        "MountedWimRefreshQuietPeriodSec",
        "BatchUnmountStepDelaySec"
    )

    return ($persistableKeys -contains [string]$Key)
}

function New-DefaultConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectRoot
    )

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        try { $ProjectRoot = Get-ProjectRoot } catch { $ProjectRoot = (Get-Location).Path }
    }

    $logDir   = Join-Path $ProjectRoot "Logs"
    $workDir  = Join-Path $ProjectRoot "Work"
    $mountDir = Join-Path $workDir "Mounts"

    return @{
        StartPage                 = "Dashboard"
        UiLanguage                = "de"
        AppDebug                  = $false
        NotificationsEnabled      = $true
        NotificationMinimumDurationSec = 20
        DriverLoadAllDefault      = $false
        UpdatesAutoCatalogDefault = $true
        ImageMountReadOnlyDefault = $true
        AdkRoot                   = $null
        WinPeRoot                 = $null
        OscdimgPath               = $null

        ProjectRoot      = $ProjectRoot
        LogDir           = $logDir
        WorkDir          = $workDir
        DefaultMountRoot = $mountDir

        DismTimeoutSec   = 900
        DismLockTimeoutSec = 1800
        DismUnmountCommitTimeoutSec = 7200
        DismUnmountCommitRetryCount = 3
        DismUnmountCommitRetryDelaySec = 12
        MountedWimRefreshQuietPeriodSec = 15
        BatchUnmountStepDelaySec = 4
        JobHistoryMaxEntries = 250
        IsoMountRetry    = @{
            Count = 25
            DelayMs = 200
        }
    }
}

function Initialize-Config {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Overrides
    )

    $base = New-DefaultConfig
    $persisted = Import-UserConfigOverrides -ProjectRoot $base["ProjectRoot"]

    foreach ($k in $persisted.Keys) {
        $base[$k] = $persisted[$k]
    }

    if ($Overrides) {
        foreach ($k in $Overrides.Keys) {
            $base[$k] = $Overrides[$k]
        }
    }

    $script:Config = $base
    return $script:Config
}

function Get-Config {
    [CmdletBinding()]
    param()

    if (-not $script:Config) {
        $null = Initialize-Config
    }
    return $script:Config
}

function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        $Default = $null
    )

    $cfg = Get-Config
    if ($cfg.ContainsKey($Key)) { return $cfg[$Key] }
    return $Default
}

function Save-Config {
    [CmdletBinding()]
    param()

    $cfg = Get-Config
    $path = Get-ConfigFilePath -ProjectRoot $cfg["ProjectRoot"]

    $persisted = [ordered]@{}
    foreach ($key in ($cfg.Keys | Sort-Object)) {
        if (-not (Test-ConfigKeyPersistable -Key ([string]$key))) { continue }
        $persisted[[string]$key] = $cfg[$key]
    }

    # ConvertTo-Json must receive the dictionary as a single input object.
    $json = ConvertTo-Json -InputObject $persisted -Depth 8
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($true))
    return $path
}

function Set-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        $Value,

        [switch]$Persist
    )

    $cfg = Get-Config
    $cfg[$Key] = $Value

    if ($Persist) {
        $null = Save-Config
    }

    return $Value
}

Export-ModuleMember -Function `
    Get-ConfigFilePath, `
    New-DefaultConfig, `
    Initialize-Config, `
    Get-Config, `
    Get-ConfigValue, `
    Set-ConfigValue, `
    Save-Config
