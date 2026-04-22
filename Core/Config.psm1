Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Wir speichern die Config als Hashtable im Modul-Scope.
$script:Config = $null

function New-DefaultConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectRoot
    )

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        # Bootstrap liefert das; falls Bootstrap noch nicht importiert: fallback.
        try { $ProjectRoot = Get-ProjectRoot } catch { $ProjectRoot = (Get-Location).Path }
    }

    $logDir   = Join-Path $ProjectRoot "Logs"
    $workDir  = Join-Path $ProjectRoot "Work"
    $mountDir = Join-Path $workDir "Mounts"

    return @{
        # Allgemein
        StartPage        = "Dashboard"
        AppDebug         = $false

        # Pfade (alles relativ zum ProjectRoot)
        ProjectRoot      = $ProjectRoot
        LogDir           = $logDir
        WorkDir          = $workDir
        DefaultMountRoot = $mountDir

        # DISM / Mount / ISO
        DismTimeoutSec   = 900
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

function Set-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        $Value
    )

    $cfg = Get-Config
    $cfg[$Key] = $Value
    return $Value
}

Export-ModuleMember -Function `
    New-DefaultConfig, `
    Initialize-Config, `
    Get-Config, `
    Get-ConfigValue, `
    Set-ConfigValue
