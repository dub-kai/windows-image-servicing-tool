[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$QuickResultPath = '',
    [string]$OutputPath = ''
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

if ([string]::IsNullOrWhiteSpace($QuickResultPath)) {
    $quickRoot = Join-Path $ProjectRoot 'Work\Temp\QuickVerification'
    $latest = Get-ChildItem -LiteralPath $quickRoot -Recurse -Filter 'quick_verification_result.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw 'No quick_verification_result.json found. Run Invoke-QuickVerification.ps1 first.'
    }
    $QuickResultPath = [string]$latest.FullName
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ProjectRoot 'Docs\ReleaseStatus.md'
}

function Read-JsonFileSafe {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Find-FirstResultPathFromOutput {
    param(
        [AllowNull()][object]$Step,
        [string]$Pattern
    )

    if (-not $Step) { return $null }
    if ($Step.PSObject.Properties.Match('Output').Count -lt 1) { return $null }

    foreach ($line in @($Step.Output)) {
        if ([string]$line -match $Pattern) {
            return [string]$Matches[1]
        }
    }
    return $null
}

$quick = Read-JsonFileSafe -Path $QuickResultPath
if (-not $quick) { throw "Could not read quick result: $QuickResultPath" }

$branch = ''
try { $branch = (& git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null) } catch {}

$navStep = $quick.Steps | Where-Object { $_.Name -eq 'NavigationStress' } | Select-Object -First 1
$warmupStep = $quick.Steps | Where-Object { $_.Name -eq 'StartupWarmup' } | Select-Object -First 1
$usbStep = $quick.Steps | Where-Object { $_.Name -eq 'UsbAcceptance' } | Select-Object -First 1
$smokeStep = $quick.Steps | Where-Object { [string]$_.Name -like 'ProjectSmoke:*' } | Select-Object -First 1

$navResult = Read-JsonFileSafe -Path (Find-FirstResultPathFromOutput -Step $navStep -Pattern 'RESULT\s+(.+navigation_stress_result\.json)')
$warmupResult = Read-JsonFileSafe -Path (Find-FirstResultPathFromOutput -Step $warmupStep -Pattern 'RESULT\s+(.+startup_warmup_result\.json)')
$usbResult = Read-JsonFileSafe -Path (Find-FirstResultPathFromOutput -Step $usbStep -Pattern 'RESULT\s+(.+usb_acceptance_result\.json)')
$smokeResult = Read-JsonFileSafe -Path (Find-FirstResultPathFromOutput -Step $smokeStep -Pattern 'RESULT\s+(.+project_smoke_result\.json)')

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Release Status') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('- Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
$lines.Add(('- Branch: `{0}`' -f $branch)) | Out-Null
$lines.Add(('- Quick result: `{0}`' -f $QuickResultPath)) | Out-Null
$lines.Add(('- Overall: {0}' -f $(if ($quick.Ok) { 'OK' } else { 'FAILED' }))) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Quick Verification') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| Step | Status | Duration |') | Out-Null
$lines.Add('| --- | --- | ---: |') | Out-Null
foreach ($step in @($quick.Steps)) {
    $lines.Add(('| {0} | {1} | {2:N1}s |' -f [string]$step.Name, $(if ($step.Ok) { 'OK' } else { 'FAILED' }), ([double]$step.DurationMs / 1000.0))) | Out-Null
}

$lines.Add('') | Out-Null
$lines.Add('## Performance Baseline') | Out-Null
$lines.Add('') | Out-Null
if ($navResult) {
    $lines.Add(('- Navigation average: {0} ms' -f [int]$navResult.AvgDurationMs)) | Out-Null
    $lines.Add(('- Navigation max: {0} ms' -f [int]$navResult.MaxDurationMs)) | Out-Null
    foreach ($page in @($navResult.PageSummary)) {
        $lines.Add(('- {0}: cold {1} ms, warm avg {2} ms, warm max {3} ms' -f [string]$page.Page, [int]$page.ColdDurationMs, [int]$page.WarmAvgDurationMs, [int]$page.WarmMaxDurationMs)) | Out-Null
    }
} else {
    $lines.Add('- Navigation result was not found.') | Out-Null
}

if ($warmupResult) {
    $metrics = $warmupResult.Metrics
    $lines.Add(('- Startup context: {0} ms' -f [int]$metrics.ContextMs)) | Out-Null
    $lines.Add(('- Startup controllers: {0} ms' -f [int]$metrics.ControllerInitMs)) | Out-Null
    $lines.Add(('- Initial navigation: {0} ms' -f [int]$metrics.InitialNavigationMs)) | Out-Null
    $lines.Add(('- Warmup wait: {0} ms, completed pages: {1}' -f [int]$metrics.WarmupWaitMs, [int]$metrics.WarmupCompletedCount)) | Out-Null
}

$lines.Add('') | Out-Null
$lines.Add('## USB Acceptance') | Out-Null
$lines.Add('') | Out-Null
if ($usbResult) {
    $lines.Add(('- Overall: {0}' -f $(if ($usbResult.Ok) { 'OK' } else { 'FAILED' }))) | Out-Null
    foreach ($step in @($usbResult.Steps)) {
        $lines.Add(('- {0}: {1}' -f [string]$step.Name, $(if ($step.Ok) { 'OK' } else { 'FAILED' }))) | Out-Null
    }
} else {
    $lines.Add('- USB acceptance result was not found.') | Out-Null
}

$lines.Add('') | Out-Null
$lines.Add('## Smoke') | Out-Null
$lines.Add('') | Out-Null
if ($smokeResult) {
    $failed = @($smokeResult.Results | Where-Object { [string]$_.Status -eq 'FAIL' })
    $skipped = @($smokeResult.Results | Where-Object { [string]$_.Status -eq 'SKIP' })
    $lines.Add(('- Failed: {0}' -f $failed.Count)) | Out-Null
    $lines.Add(('- Skipped: {0}' -f $skipped.Count)) | Out-Null
} else {
    $lines.Add('- Smoke result was not part of this quick run.') | Out-Null
}

$lines.Add('') | Out-Null
$lines.Add('## Next Gate') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('- Manual UI pass: Dashboard, Images, Media Builder, Driver, Updates, Settings.') | Out-Null
$lines.Add('- Real USB pass with a disposable stick before calling USB workflow complete.') | Out-Null
$lines.Add('- Full smoke with live/mount lifecycle only when no important mount is active.') | Out-Null

$outDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ("REPORT {0}" -f $OutputPath)
