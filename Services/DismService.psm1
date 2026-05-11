Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:DismMutexName = 'Local\WinImageAdmin_DismMutex'

function Get-DismChildProcessIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ParentId,
        [Parameter()][System.Collections.Generic.HashSet[int]]$Seen
    )

    if (-not $Seen) {
        $Seen = New-Object 'System.Collections.Generic.HashSet[int]'
    }

    $ids = New-Object System.Collections.Generic.List[int]
    try {
        $children = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $ParentId))
        foreach ($child in $children) {
            $childId = [int]$child.ProcessId
            if ($Seen.Add($childId)) {
                [void]$ids.Add($childId)
                foreach ($nested in @(Get-DismChildProcessIds -ParentId $childId -Seen $Seen)) {
                    [void]$ids.Add([int]$nested)
                }
            }
        }
    } catch {}

    return @($ids.ToArray())
}

function Stop-DismProcessTree {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

    $ids = New-Object System.Collections.Generic.List[int]
    try {
        foreach ($childId in @(Get-DismChildProcessIds -ParentId ([int]$Process.Id))) {
            [void]$ids.Add([int]$childId)
        }
    } catch {}

    try { [void]$ids.Add([int]$Process.Id) } catch {}

    foreach ($id in @($ids.ToArray() | Sort-Object -Descending -Unique)) {
        try { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Get-DismTextTail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxChars = 700
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        $content = $reader.ReadToEnd()
        if ([string]::IsNullOrEmpty($content)) { return '' }
        if ($content.Length -le $MaxChars) { return $content }
        return $content.Substring($content.Length - $MaxChars)
    } catch {
        return ''
    } finally {
        if ($reader) {
            try { $reader.Dispose() } catch {}
        } elseif ($stream) {
            try { $stream.Dispose() } catch {}
        }
    }
}

function Invoke-Dism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [int]$TimeoutSec = 900,

        [switch]$EnsureEnglish,

        [Parameter()]
        [scriptblock]$OnHeartbeat,

        [int]$HeartbeatIntervalSec = 5
    )

    if ($PSBoundParameters.ContainsKey("TimeoutSec") -eq $false) {
        try { $TimeoutSec = [int](Get-ConfigValue -Key "DismTimeoutSec" -Default 900) } catch { $TimeoutSec = 900 }
    }

    $args = @()
    if ($EnsureEnglish) {
        if ($Arguments -notcontains "/English") {
            $args += "/English"
        }
    }
    $args += $Arguments

    $exe = Join-Path $env:WINDIR "System32\dism.exe"
    if (-not (Test-Path -LiteralPath $exe)) { $exe = "dism.exe" }

    $argLine = ($args -join " ")

    $lockTimeoutSec = 1800
    try { $lockTimeoutSec = [int](Get-ConfigValue -Key "DismLockTimeoutSec" -Default 1800) } catch { $lockTimeoutSec = 1800 }
    if ($lockTimeoutSec -lt 30) { $lockTimeoutSec = 30 }

    $mutex = $null
    $lockAcquired = $false
    $lockStart = [DateTime]::UtcNow
    $proc = $null
    $stdoutPath = $null
    $stderrPath = $null
    $scriptPath = $null

    if ($HeartbeatIntervalSec -lt 1) { $HeartbeatIntervalSec = 1 }

    try {
        try { Write-Log -Level DEBUG -Message ("DISM: {0} {1}" -f $exe, $argLine) } catch {}

        $mutex = New-Object System.Threading.Mutex($false, $script:DismMutexName)

        try {
            $lockAcquired = $mutex.WaitOne([int]($lockTimeoutSec * 1000))
        } catch [System.Threading.AbandonedMutexException] {
            $lockAcquired = $true
        }

        if (-not $lockAcquired) {
            try {
                Write-Log -Level ERROR -Message ("DISM Mutex Timeout nach {0}s: {1}" -f $lockTimeoutSec, $argLine) -ToConsole
            } catch {}
            throw "DISM Mutex Timeout nach ${lockTimeoutSec}s (Command: $argLine)"
        }

        $lockWaitMs = [int]([DateTime]::UtcNow - $lockStart).TotalMilliseconds
        if ($lockWaitMs -gt 250) {
            try {
                Write-Log -Level DEBUG -Message ("DISM Mutex acquired after {0}ms: {1}" -f $lockWaitMs, $argLine)
            } catch {}
        }

        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()
        $scriptPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.ps1')

        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }

        $argLiteral = ($args | ForEach-Object {
            "'" + ([string]$_).Replace("'", "''") + "'"
        }) -join ', '

        $scriptContent = @"
`$ErrorActionPreference = 'Stop'
`$exe = '$($exe.Replace("'", "''"))'
`$argv = @($argLiteral)
& `$exe @argv 1> '$($stdoutPath.Replace("'", "''"))' 2> '$($stderrPath.Replace("'", "''"))'
exit `$LASTEXITCODE
"@
        [System.IO.File]::WriteAllText($scriptPath, $scriptContent, [System.Text.Encoding]::UTF8)

        $psArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $scriptPath.Replace('"','""') + '"'))

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $psExe
        $pinfo.Arguments = ($psArgs -join ' ')
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $pinfo

        $start = [DateTime]::UtcNow
        $null = $proc.Start()
        try { $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch {}

        $timeoutMs = [int]($TimeoutSec * 1000)
        $deadline = [DateTime]::UtcNow.AddMilliseconds($timeoutMs)
        $lastHeartbeat = [DateTime]::UtcNow.AddYears(-1)
        while (-not $proc.HasExited) {
            if ([DateTime]::UtcNow -ge $deadline) {
                try { Write-Log -Level ERROR -Message ("DISM Timeout nach {0}s: {1}" -f $TimeoutSec, $argLine) -ToConsole } catch {}
                try { Stop-DismProcessTree -Process $proc } catch {}
                try { $proc.WaitForExit() } catch {}
                throw "DISM Timeout nach ${TimeoutSec}s (Command: $argLine)"
            }

            if ($OnHeartbeat -and ([DateTime]::UtcNow - $lastHeartbeat).TotalSeconds -ge $HeartbeatIntervalSec) {
                try {
                    $stdoutTail = if ($stdoutPath) { Get-DismTextTail -Path $stdoutPath -MaxChars 700 } else { '' }
                    $stderrTail = if ($stderrPath) { Get-DismTextTail -Path $stderrPath -MaxChars 700 } else { '' }

                    & $OnHeartbeat ([pscustomobject]@{
                        ProcessId    = $proc.Id
                        StartedUtc   = $start
                        ElapsedSec   = [int]([DateTime]::UtcNow - $start).TotalSeconds
                        StdOutTail   = $stdoutTail
                        StdErrTail   = $stderrTail
                        Arguments    = $argLine
                    })
                } catch {}
                $lastHeartbeat = [DateTime]::UtcNow
            }

            Start-Sleep -Milliseconds 100
            try { $proc.Refresh() } catch {}
        }

        try { $proc.Refresh() } catch {}

        $stdout = ''
        $stderr = ''
        if ($stdoutPath -and (Test-Path -LiteralPath $stdoutPath)) {
            $stdout = [System.IO.File]::ReadAllText($stdoutPath, [System.Text.Encoding]::UTF8)
        }
        if ($stderrPath -and (Test-Path -LiteralPath $stderrPath)) {
            $stderr = [System.IO.File]::ReadAllText($stderrPath, [System.Text.Encoding]::UTF8)
        }

        $end = [DateTime]::UtcNow
        $durMs = [int]($end - $start).TotalMilliseconds
        $code = $null
        try { $code = $proc.ExitCode } catch { $code = $null }
        if ($null -eq $code) { $code = -1 }

        if ($code -ne 0) {
            if ($code -eq 183) {
                try {
                    Write-Log -Level WARN -Message ("DISM ExitCode={0} ({1}ms) Args={2}" -f $code, $durMs, $argLine)
                } catch {}
            } else {
                try {
                    Write-Log -Level ERROR -Message ("DISM ExitCode={0} ({1}ms) Args={2}" -f $code, $durMs, $argLine) -ToConsole
                } catch {}
            }
        } else {
            try {
                Write-Log -Level DEBUG -Message ("DISM OK ({0}ms) Args={1}" -f $durMs, $argLine)
            } catch {}
        }

        return [pscustomobject]@{
            ExitCode   = $code
            StdOut     = $stdout
            StdErr     = $stderr
            DurationMs = $durMs
            FileName   = $exe
            Arguments  = $argLine
        }
    }
    finally {
        if ($proc) {
            try { $proc.Dispose() } catch {}
        }

        if ($stdoutPath -and (Test-Path -LiteralPath $stdoutPath)) {
            try { Remove-Item -LiteralPath $stdoutPath -Force } catch {}
        }

        if ($stderrPath -and (Test-Path -LiteralPath $stderrPath)) {
            try { Remove-Item -LiteralPath $stderrPath -Force } catch {}
        }

        if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
            try { Remove-Item -LiteralPath $scriptPath -Force } catch {}
        }

        if ($lockAcquired -and $mutex) {
            try { $mutex.ReleaseMutex() } catch {}
        }

        if ($mutex) {
            try { $mutex.Dispose() } catch {}
        }
    }
}

Export-ModuleMember -Function Invoke-Dism
