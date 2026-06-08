[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputDir,
    [int]$WarmupTimeoutMs = 5000
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

if ($WarmupTimeoutMs -lt 1000) { $WarmupTimeoutMs = 1000 }

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\StartupWarmup'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("startup_warmup_{0}" -f $stamp)
$resultPath = Join-Path $runDir 'startup_warmup_result.json'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Import-StartupWarmupModules {
    Import-Module (Join-Path $ProjectRoot 'Core\Bootstrap.psm1') -Global -Force -DisableNameChecking
    Set-ProjectRoot -Path $ProjectRoot | Out-Null

    foreach ($module in @(
        'UI\UiHelpers.psm1',
        'UI\UiAsync.psm1',
        'Core\Config.psm1',
        'Core\Logger.psm1',
        'Core\AppState.psm1',
        'Core\JobHistory.psm1',
        'UI\Localization.psm1',
        'UI\Theme.psm1',
        'UI\Notifications.psm1',
        'UI\Xaml.psm1',
        'UI\Controllers\ImagesController.psm1',
        'UI\Controllers\DashboardController.psm1',
        'UI\Controllers\SettingsController.psm1',
        'UI\Controllers\DriverController.psm1',
        'UI\Controllers\UpdatesController.psm1',
        'UI\Controllers\MediaBuilderController.psm1'
    )) {
        Import-Module (Resolve-ProjectPath $module -MustExist) -Global -Force -DisableNameChecking
    }
}

function Invoke-StartupDispatcherPump {
    param(
        [Parameter(Mandatory)]$Dispatcher,
        [int]$Milliseconds = 250
    )

    if ($Milliseconds -lt 1) { return }

    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $timer = New-Object System.Windows.Threading.DispatcherTimer(
        [System.Windows.Threading.DispatcherPriority]::Background,
        $Dispatcher
    )
    $timer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
    $timer.Add_Tick({
        try { $timer.Stop() } catch {}
        $frame.Continue = $false
    }.GetNewClosure())
    $timer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

$startedAt = Get-Date
$ctx = $null
$ok = $false
$errorText = $null
$metrics = [ordered]@{}

try {
    Set-Location -LiteralPath $ProjectRoot
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Import-StartupWarmupModules
    $sw.Stop()
    $metrics.ModuleImportMs = [int]$sw.ElapsedMilliseconds

    $partsRoot = Join-Path $ProjectRoot 'UI\MainWindow'
    foreach ($part in @(
        'MainWindow.Context.ps1',
        'MainWindow.NavState.ps1',
        'MainWindow.Controllers.ps1',
        'MainWindow.Navigation.ps1',
        'MainWindow.Start.ps1'
    )) {
        . (Join-Path $partsRoot $part)
    }

    $sw.Restart()
    $ctx = New-MainWindowContext
    $ctx.Window.ShowInTaskbar = $false
    $ctx.Window.WindowState = [System.Windows.WindowState]::Minimized
    $sw.Stop()
    $metrics.ContextMs = [int]$sw.ElapsedMilliseconds

    $sw.Restart()
    $ctx = Initialize-MainWindowControllers -Ctx $ctx
    $ctx = Initialize-MainWindowNavigation -Ctx $ctx
    $sw.Stop()
    $metrics.ControllerInitMs = [int]$sw.ElapsedMilliseconds

    $ctx.Window.Show()
    $ctx.Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    $sw.Restart()
    Invoke-MainWindowInitialNavigation -Ctx $ctx
    $ctx.Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    $sw.Stop()
    $metrics.InitialNavigationMs = [int]$sw.ElapsedMilliseconds

    $sw.Restart()
    Start-MainWindowPageWarmup -Ctx $ctx -InitialDelayMs 100 -IntervalMs 120
    $deadline = (Get-Date).AddMilliseconds($WarmupTimeoutMs)
    do {
        Invoke-StartupDispatcherPump -Dispatcher $ctx.Window.Dispatcher -Milliseconds 150
        $completedCount = 0
        try { $completedCount = @($ctx.PageWarmupCompleted.Keys).Count } catch {}
    } while ($completedCount -lt 5 -and (Get-Date) -lt $deadline)
    $sw.Stop()
    $metrics.WarmupWaitMs = [int]$sw.ElapsedMilliseconds

    $completed = @()
    try { $completed = @($ctx.PageWarmupCompleted.Keys | Sort-Object) } catch {}
    $metrics.WarmupCompletedCount = [int]$completed.Count
    $metrics.WarmupCompleted = $completed

    if ($completed.Count -lt 5) {
        throw ("Only {0}/5 warmup pages completed within {1}ms." -f $completed.Count, $WarmupTimeoutMs)
    }

    $ok = $true
} catch {
    $errorText = $_.Exception.Message
} finally {
    try {
        if ($ctx -and $ctx.Window) {
            $ctx.Window.Close()
        }
    } catch {}
}

$result = [pscustomobject]@{
    Ok          = $ok
    Error       = $errorText
    StartedAt   = $startedAt.ToString('o')
    FinishedAt  = (Get-Date).ToString('o')
    ProjectRoot = $ProjectRoot
    OutputDir   = $runDir
    ResultPath  = $resultPath
    Metrics     = [pscustomobject]$metrics
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("RESULT {0}" -f $resultPath)
Write-Host ("StartupWarmup: context={0}ms controllers={1}ms initial={2}ms warmup={3}ms completed={4}" -f $metrics.ContextMs, $metrics.ControllerInitMs, $metrics.InitialNavigationMs, $metrics.WarmupWaitMs, $metrics.WarmupCompletedCount)

if (-not $ok) { exit 1 }
exit 0
