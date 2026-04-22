Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:LogFilePath = $null

function Initialize-Logger {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LogDir,

        [Parameter()]
        [string]$LogFileName
    )

    if ([string]::IsNullOrWhiteSpace($LogDir)) {
        try {
            $LogDir = Get-ConfigValue -Key "LogDir"
        } catch {
            $LogDir = Join-Path (Get-Location).Path "Logs"
        }
    }

    if ([string]::IsNullOrWhiteSpace($LogFileName)) {
        $LogFileName = "WinImageAdmin_{0}.log" -f (Get-Date -Format "yyyy-MM-dd")
    }

    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $script:LogFilePath = Join-Path $LogDir $LogFileName
    return $script:LogFilePath
}

function Get-LogFilePath {
    [CmdletBinding()]
    param()

    if (-not $script:LogFilePath) {
        $null = Initialize-Logger
    }

    return $script:LogFilePath
}

function Write-LogConsoleLine {
    param(
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Line
    )

    try {
        switch ($Level) {
            "DEBUG" { Write-Host $Line -ForegroundColor DarkGray }
            "INFO"  { Write-Host $Line -ForegroundColor Gray }
            "WARN"  { Write-Host $Line -ForegroundColor Yellow }
            "ERROR" { Write-Host $Line -ForegroundColor Red }
            default { Write-Host $Line }
        }
    } catch {}
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [switch]$ToConsole
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "{0} [{1}] {2}" -f $ts, $Level, $Message

    $appDebug = $false
    try {
        $appDebug = [bool](Get-ConfigValue -Key "AppDebug" -Default $false)
    } catch {
        $appDebug = $false
    }

    $shouldWriteConsole = $ToConsole -or $appDebug -or $Level -in @("WARN","ERROR")

    $path = $null
    try {
        $path = Get-LogFilePath
    } catch {
        $path = $null
    }

    $writeOk = $false
    $lastWriteError = $null

    if (-not [string]::IsNullOrWhiteSpace($path)) {
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
            try {
                $dir = Split-Path -Path $path -Parent
                if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                }

                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::AppendAllText($path, ($line + [Environment]::NewLine), $utf8NoBom)

                $writeOk = $true
                break
            } catch {
                $lastWriteError = $_.Exception
                Start-Sleep -Milliseconds (25 * ($attempt + 1))
            }
        }
    }

    if ($shouldWriteConsole) {
        Write-LogConsoleLine -Level $Level -Line $line
    }

    if (-not $writeOk -and $lastWriteError) {
        $fallback = "{0} [WARN] Logger-Fallback: Logdatei konnte nicht beschrieben werden: {1}" -f $ts, $lastWriteError.Message
        Write-LogConsoleLine -Level "WARN" -Line $fallback
    }
}

Export-ModuleMember -Function `
    Initialize-Logger, `
    Get-LogFilePath, `
    Write-Log