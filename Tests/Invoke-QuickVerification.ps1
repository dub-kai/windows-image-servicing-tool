[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputDir,
    [int]$NavigationCycles = 2,
    [int]$StepTimeoutSec = 180,
    [switch]$IncludeSmoke,
    [ValidateSet('Basic', 'Full')]
    [string]$SmokeScope = 'Basic'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        try { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $scriptRoot = '' }
    }
    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        throw 'ProjectRoot could not be resolved automatically. Pass -ProjectRoot.'
    }
    $ProjectRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
}

if ($NavigationCycles -lt 1) { $NavigationCycles = 1 }
if ($StepTimeoutSec -lt 30) { $StepTimeoutSec = 30 }

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\QuickVerification'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("quick_verification_{0}" -f $stamp)
$resultPath = Join-Path $runDir 'quick_verification_result.json'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Invoke-QuickVerificationStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ("== {0} ==" -f $Name)
    $outPath = Join-Path $runDir ("{0}_stdout.log" -f $Name)
    $errPath = Join-Path $runDir ("{0}_stderr.log" -f $Name)
    $timedOut = $false
    $proc = $null

    try {
        $proc = Start-Process `
            -FilePath $exe `
            -ArgumentList $Arguments `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $outPath `
            -RedirectStandardError $errPath

        $completed = $proc.WaitForExit([Math]::Max(1, $StepTimeoutSec) * 1000)
        if (-not $completed) {
            $timedOut = $true
            try {
                Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f [int]$proc.Id) |
                    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            } catch {}
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            try { $proc.WaitForExit(3000) | Out-Null } catch {}
        }
    } catch {
        $timedOut = $false
        $err = $_.Exception.Message
        Set-Content -LiteralPath $errPath -Value $err -Encoding UTF8
    } finally {
        $sw.Stop()
    }

    $output = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($outPath, $errPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
                $output.Add([string]$line) | Out-Null
            }
        }
    }

    if ($timedOut) {
        $output.Add(("TIMEOUT after {0}s" -f $StepTimeoutSec)) | Out-Null
    }

    $exitCode = if ($timedOut) {
        124
    } elseif ($proc) {
        try { [int]$proc.ExitCode } catch { 1 }
    } else {
        1
    }

    foreach ($line in @($output.ToArray())) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host $line
        }
    }

    [pscustomobject]@{
        Name       = $Name
        Ok         = ($exitCode -eq 0)
        ExitCode   = $exitCode
        DurationMs = [int]$sw.ElapsedMilliseconds
        TimedOut   = [bool]$timedOut
        Output     = @($output.ToArray())
    }
}

$startedAt = Get-Date
$steps = New-Object System.Collections.Generic.List[object]

$common = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass')
$steps.Add((Invoke-QuickVerificationStep -Name 'ModuleImport' -Arguments ($common + @('-File', (Join-Path $ProjectRoot 'Tests\Invoke-ModuleImportTest.ps1'), '-ProjectRoot', $ProjectRoot, '-OutputDir', (Join-Path $runDir 'ModuleImport'))))) | Out-Null
$steps.Add((Invoke-QuickVerificationStep -Name 'ThemeScan' -Arguments ($common + @('-File', (Join-Path $ProjectRoot 'Tests\Invoke-ThemeScanTest.ps1'), '-ProjectRoot', $ProjectRoot, '-OutputDir', (Join-Path $runDir 'ThemeScan'), '-MaxIssues', '0')))) | Out-Null
$steps.Add((Invoke-QuickVerificationStep -Name 'UsbAcceptance' -Arguments ($common + @('-File', (Join-Path $ProjectRoot 'Tests\Invoke-UsbAcceptanceTest.ps1'), '-ProjectRoot', $ProjectRoot, '-OutputDir', (Join-Path $runDir 'UsbAcceptance'))))) | Out-Null
$steps.Add((Invoke-QuickVerificationStep -Name 'DismHints' -Arguments ($common + @('-File', (Join-Path $ProjectRoot 'Tests\Invoke-DismHintTest.ps1'), '-ProjectRoot', $ProjectRoot)))) | Out-Null
$steps.Add((Invoke-QuickVerificationStep -Name 'NavigationStress' -Arguments ($common + @('-File', (Join-Path $ProjectRoot 'Tests\Invoke-NavigationStressTest.ps1'), '-ProjectRoot', $ProjectRoot, '-OutputDir', (Join-Path $runDir 'NavigationStress'), '-Cycles', ([string]$NavigationCycles), '-PauseMs', '80')))) | Out-Null
$steps.Add((Invoke-QuickVerificationStep -Name 'StartupWarmup' -Arguments ($common + @('-File', (Join-Path $ProjectRoot 'Tests\Invoke-StartupWarmupTest.ps1'), '-ProjectRoot', $ProjectRoot, '-OutputDir', (Join-Path $runDir 'StartupWarmup'), '-WarmupTimeoutMs', '6000')))) | Out-Null

if ($IncludeSmoke) {
    $smokeArgs = $common + @(
        '-File', (Join-Path $ProjectRoot 'Tests\Invoke-ProjectSmokeTest.ps1'),
        '-ProjectRoot', $ProjectRoot,
        '-OutputDir', (Join-Path $runDir 'ProjectSmoke'),
        '-Scope', $SmokeScope,
        '-SkipMountLifecycle',
        '-SkipFeatureMount',
        '-SkipLiveCatalog',
        '-GuiStartupSeconds', '8'
    )
    $steps.Add((Invoke-QuickVerificationStep -Name ("ProjectSmoke:{0}" -f $SmokeScope) -Arguments $smokeArgs)) | Out-Null
}

$allSteps = @($steps.ToArray())
$ok = (@($allSteps | Where-Object { -not $_.Ok }).Count -eq 0)
$result = [pscustomobject]@{
    Ok            = $ok
    StartedAt     = $startedAt.ToString('o')
    FinishedAt    = (Get-Date).ToString('o')
    ProjectRoot   = $ProjectRoot
    OutputDir     = $runDir
    ResultPath    = $resultPath
    StepCount     = $allSteps.Count
    IncludeSmoke  = [bool]$IncludeSmoke
    SmokeScope    = $SmokeScope
    StepTimeoutSec = [int]$StepTimeoutSec
    TotalMs       = if ($allSteps.Count -gt 0) { [int](($allSteps | Measure-Object DurationMs -Sum).Sum) } else { 0 }
    FailedSteps   = @($allSteps | Where-Object { -not $_.Ok } | Select-Object -ExpandProperty Name)
    Steps         = $allSteps
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("RESULT {0}" -f $resultPath)

if (-not $ok) { exit 1 }
exit 0
