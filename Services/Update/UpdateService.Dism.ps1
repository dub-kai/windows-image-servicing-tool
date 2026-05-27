function Write-UpdateLog {
    param(
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $cmd = Get-Command Write-Log -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            Write-Log -Level $Level -Message $Message
            return
        } catch {}
    }
}

function Get-UpdatesDismPath {
    $sysnative = Join-Path $env:WINDIR 'Sysnative\dism.exe'
    if (Test-Path -LiteralPath $sysnative) { return $sysnative }

    $system32 = Join-Path $env:WINDIR 'System32\dism.exe'
    return $system32
}

function Import-UpdatesDismService {
    $cmd = Get-Command Invoke-Dism -ErrorAction SilentlyContinue
    if ($cmd) { return }

    $dismServicePath = $null
    try {
        if (Get-Command Resolve-ProjectPath -ErrorAction SilentlyContinue) {
            $dismServicePath = Resolve-ProjectPath 'Services\DismService.psm1' -MustExist
        }
    } catch {
        $dismServicePath = $null
    }

    if ([string]::IsNullOrWhiteSpace($dismServicePath)) {
        $candidate = Join-Path $PSScriptRoot '..\DismService.psm1'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $dismServicePath = $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace($dismServicePath) -or -not (Test-Path -LiteralPath $dismServicePath -PathType Leaf)) {
        throw 'Invoke-Dism ist nicht verfügbar und DismService.psm1 konnte nicht gefunden werden.'
    }

    Import-Module $dismServicePath -Global -Force -DisableNameChecking | Out-Null
}

function ConvertTo-UpdatesDismResult {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$ArgString
    )

    $stdout = ''
    $stderr = ''
    try { $stdout = [string]$Result.StdOut } catch {}
    try { $stderr = [string]$Result.StdErr } catch {}

    $combined = (($stdout, $stderr) -join "`r`n").Trim()

    $durationMs = 0
    try { $durationMs = [int]$Result.DurationMs } catch { $durationMs = 0 }

    return [pscustomobject]@{
        ExitCode   = [int]$Result.ExitCode
        StdOut     = $stdout
        StdErr     = $stderr
        Text       = $combined
        Args       = $ArgString
        Arguments  = $ArgString
        DurationMs = $durationMs
    }
}

function Test-UpdatesDismNeedsRemount {
    param(
        [int]$ExitCode,
        [AllowEmptyString()][string]$Text
    )

    $blob = [string]$Text

    if ($ExitCode -eq -1051655916) { return $true }
    if ($blob -match '0xc1510114') { return $true }
    if ($blob -match 'needs to be remounted') { return $true }
    if ($blob -match 'Remount the Wim') { return $true }

    return $false
}

function Invoke-UpdatesDismRemount {
    param(
        [Parameter(Mandatory)][string]$MountDir
    )

    if ([string]::IsNullOrWhiteSpace($MountDir)) {
        throw 'Remount nicht moeglich: MountDir ist leer.'
    }

    Import-UpdatesDismService

    $args = @(
        '/Remount-Image',
        ('/MountDir:"{0}"' -f $MountDir)
    )
    $argString = '/English ' + ($args -join ' ')

    Write-UpdateLog -Level WARN -Message ("Updates: DISM-Remount wird versucht fuer {0}" -f $MountDir)
    $raw = Invoke-Dism -Arguments $args -EnsureEnglish -TimeoutSec 1800
    $result = ConvertTo-UpdatesDismResult -Result $raw -ArgString $argString

    if ($result.ExitCode -ne 0) {
        $msg = [string]$result.Text
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = "DISM /Remount-Image fehlgeschlagen mit ExitCode $($result.ExitCode)."
        }

        Write-UpdateLog -Level ERROR -Message ("Updates: DISM-Remount fehlgeschlagen ({0}ms) fuer {1} | ExitCode={2}" -f $result.DurationMs, $MountDir, $result.ExitCode)
        throw ("{0}`nArgs={1}`nExitCode={2}" -f $msg, $argString, $result.ExitCode)
    }

    Write-UpdateLog -Level INFO -Message ("Updates: DISM-Remount erfolgreich ({0}ms) fuer {1}" -f $result.DurationMs, $MountDir)

    return $result
}

function Invoke-UpdatesDism {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$RetryCount = 0,
        [int]$RetryDelayMs = 1200,
        [string]$RetryPrefix = 'Updates',
        [string]$MountDir = '',
        [bool]$AllowAutoRemount = $true
    )

    Import-UpdatesDismService

    $argString = ($Arguments -join ' ')

    for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
        $raw = Invoke-Dism -Arguments $Arguments -EnsureEnglish
        $result = ConvertTo-UpdatesDismResult -Result $raw -ArgString $argString

        if ($result.ExitCode -eq 0) {
            return $result
        }

        $shouldAutoRemount = (
            $AllowAutoRemount -and
            -not [string]::IsNullOrWhiteSpace($MountDir) -and
            (Test-UpdatesDismNeedsRemount -ExitCode $result.ExitCode -Text $result.Text)
        )

        if ($shouldAutoRemount) {
            Write-UpdateLog -Level WARN -Message ("DISM ExitCode={0} ({1}ms) Args={2} | Remount-Recovery wird versucht" -f $result.ExitCode, $result.DurationMs, $argString)
        }

        if ($result.ExitCode -eq 183 -and $attempt -lt $RetryCount) {
            Write-UpdateLog -Level WARN -Message ("{0}: DISM busy (183), Retry {1}/{2} fuer Args={3}" -f $RetryPrefix, ($attempt + 1), $RetryCount, $argString)
            Start-Sleep -Milliseconds $RetryDelayMs
            continue
        }

        if ($shouldAutoRemount) {
            Write-UpdateLog -Level WARN -Message ("{0}: Mount muss remounted werden. Automatischer Remount fuer {1}." -f $RetryPrefix, $MountDir)

            $null = Invoke-UpdatesDismRemount -MountDir $MountDir
            Start-Sleep -Milliseconds 800

            $retryResult = Invoke-UpdatesDism `
                -Arguments $Arguments `
                -RetryCount $RetryCount `
                -RetryDelayMs $RetryDelayMs `
                -RetryPrefix $RetryPrefix `
                -MountDir $MountDir `
                -AllowAutoRemount $false

            return $retryResult
        }

        $msg = [string]$result.Text
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = "DISM fehlgeschlagen mit ExitCode $($result.ExitCode)."
        }

        throw ("{0}`nArgs={1}`nExitCode={2}" -f $msg, $argString, $result.ExitCode)
    }

    throw "DISM-Aufruf unerwartet beendet."
}

function Get-UpdatesLogRoot {
    try {
        $root = Resolve-ProjectPath "Work\Logs\Updates"
        $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction SilentlyContinue
        return $root
    } catch {
        return $null
    }
}

function Save-UpdatesDebugText {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [AllowEmptyString()][string]$Text
    )

    $root = Get-UpdatesLogRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $file = Join-Path $root ("{0}_{1}.txt" -f $Prefix, $stamp)
    [System.IO.File]::WriteAllText($file, $Text, [System.Text.Encoding]::UTF8)

    Write-UpdateLog -Level INFO -Message ("Updates: Debug-Datei geschrieben: {0}" -f $file)
    return $file
}
