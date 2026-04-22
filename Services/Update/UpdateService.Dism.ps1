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

    $dism = Get-UpdatesDismPath
    $argString = "/English /Remount-Image /MountDir:`"$MountDir`""

    Write-UpdateLog -Level WARN -Message ("Updates: DISM-Remount wird versucht fuer {0}" -f $MountDir)
    Write-UpdateLog -Level DEBUG -Message ("DISM: {0} {1}" -f $dism, $argString)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $dism
    $psi.Arguments = $argString
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = $proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $sw.Stop()

    $exitCode = $proc.ExitCode
    $combined = (($stdout, $stderr) -join "`r`n").Trim()

    if ($exitCode -ne 0) {
        $msg = $combined
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = "DISM /Remount-Image fehlgeschlagen mit ExitCode $exitCode."
        }

        Write-UpdateLog -Level ERROR -Message ("Updates: DISM-Remount fehlgeschlagen ({0}ms) fuer {1} | ExitCode={2}" -f $sw.ElapsedMilliseconds, $MountDir, $exitCode)
        throw ("{0}`nArgs={1}`nExitCode={2}" -f $msg, $argString, $exitCode)
    }

    Write-UpdateLog -Level INFO -Message ("Updates: DISM-Remount erfolgreich ({0}ms) fuer {1}" -f $sw.ElapsedMilliseconds, $MountDir)

    return [pscustomobject]@{
        ExitCode = $exitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Text     = $combined
        Args     = $argString
    }
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

    $dism = Get-UpdatesDismPath
    $argString = ($Arguments -join ' ')

    for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
        Write-UpdateLog -Level DEBUG -Message ("DISM: {0} {1}" -f $dism, $argString)

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $dism
        $psi.Arguments = $argString
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = $proc.Start()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        $sw.Stop()

        $exitCode = $proc.ExitCode
        $combined = (($stdout, $stderr) -join "`r`n").Trim()

        if ($exitCode -eq 0) {
            Write-UpdateLog -Level DEBUG -Message ("DISM OK ({0}ms) Args={1}" -f $sw.ElapsedMilliseconds, $argString)
            return [pscustomobject]@{
                ExitCode = $exitCode
                StdOut   = $stdout
                StdErr   = $stderr
                Text     = $combined
                Args     = $argString
            }
        }

        Write-UpdateLog -Level ERROR -Message ("DISM ExitCode={0} ({1}ms) Args={2}" -f $exitCode, $sw.ElapsedMilliseconds, $argString)

        if ($exitCode -eq 183 -and $attempt -lt $RetryCount) {
            Write-UpdateLog -Level WARN -Message ("{0}: DISM busy (183), Retry {1}/{2} fuer Args={3}" -f $RetryPrefix, ($attempt + 1), $RetryCount, $argString)
            Start-Sleep -Milliseconds $RetryDelayMs
            continue
        }

        if (
            $AllowAutoRemount -and
            -not [string]::IsNullOrWhiteSpace($MountDir) -and
            (Test-UpdatesDismNeedsRemount -ExitCode $exitCode -Text $combined)
        ) {
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

        $msg = $combined
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = "DISM fehlgeschlagen mit ExitCode $exitCode."
        }

        throw ("{0}`nArgs={1}`nExitCode={2}" -f $msg, $argString, $exitCode)
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