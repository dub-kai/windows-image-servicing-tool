[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputDir
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

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\ModuleImport'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("module_import_{0}" -f $stamp)
$resultPath = Join-Path $runDir 'module_import_result.json'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$modules = @(
    'Core\Bootstrap.psm1',
    'Core\Config.psm1',
    'Core\Logger.psm1',
    'Core\AppState.psm1',
    'Core\JobHistory.psm1',
    'Services\DismService.psm1',
    'Services\MountedWimService.psm1',
    'Services\WimInfoService.psm1',
    'Services\AdkService.psm1',
    'Services\IsoDetectService.psm1',
    'Services\IsoBuildService.psm1',
    'Services\ImageCompositionService.psm1',
    'Services\WindowsUpdateCatalogService.psm1',
    'Services\UpdateService.psm1',
    'UI\UiHelpers.psm1',
    'UI\UiAsync.psm1',
    'UI\Localization.psm1',
    'UI\Theme.psm1',
    'UI\Notifications.psm1',
    'UI\Xaml.psm1',
    'UI\Controllers\ImagesController.psm1',
    'UI\Controllers\DashboardController.psm1',
    'UI\Controllers\SettingsController.psm1',
    'UI\Controllers\DriverController.psm1',
    'UI\Controllers\UpdatesController.psm1',
    'UI\Controllers\MediaBuilderController.psm1',
    'UI\MainWindow.psm1'
)

$steps = New-Object System.Collections.Generic.List[object]
$startedAt = Get-Date
$ok = $true
$errorText = $null

try {
    Set-Location -LiteralPath $ProjectRoot
    Import-Module (Join-Path $ProjectRoot 'Core\Bootstrap.psm1') -Global -Force -DisableNameChecking
    Set-ProjectRoot -Path $ProjectRoot | Out-Null

    foreach ($module in $modules) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $stepOk = $true
        $stepError = ''
        try {
            Import-Module (Resolve-ProjectPath $module -MustExist) -Global -Force -DisableNameChecking
        } catch {
            $stepOk = $false
            $stepError = $_.Exception.Message
            $ok = $false
        } finally {
            $sw.Stop()
        }

        $steps.Add([pscustomobject]@{
            Module     = $module
            Ok         = $stepOk
            DurationMs = [int]$sw.ElapsedMilliseconds
            Error      = $stepError
        }) | Out-Null

        Write-Host ("{0}: {1}ms {2}" -f $module, [int]$sw.ElapsedMilliseconds, $(if ($stepOk) { 'OK' } else { 'FAIL' }))

        if (-not $stepOk) {
            throw "Module import failed: $module - $stepError"
        }
    }
} catch {
    $ok = $false
    $errorText = $_.Exception.Message
}

$allSteps = @($steps.ToArray())
$result = [pscustomobject]@{
    Ok            = $ok
    Error         = $errorText
    StartedAt     = $startedAt.ToString('o')
    FinishedAt    = (Get-Date).ToString('o')
    ProjectRoot   = $ProjectRoot
    OutputDir     = $runDir
    ResultPath    = $resultPath
    ModuleCount   = $allSteps.Count
    TotalMs       = if ($allSteps.Count -gt 0) { [int](($allSteps | Measure-Object DurationMs -Sum).Sum) } else { 0 }
    MaxDurationMs = if ($allSteps.Count -gt 0) { [int](($allSteps | Measure-Object DurationMs -Maximum).Maximum) } else { 0 }
    Steps         = $allSteps
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("RESULT {0}" -f $resultPath)

if (-not $ok) { exit 1 }
exit 0
