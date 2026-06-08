[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [int]$Cycles = 4,
    [int]$PauseMs = 120,
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

if ($Cycles -lt 1) { $Cycles = 1 }
if ($PauseMs -lt 0) { $PauseMs = 0 }

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\NavigationStress'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("nav_stress_{0}" -f $stamp)
$resultPath = Join-Path $runDir 'navigation_stress_result.json'
$progressPath = Join-Path $runDir 'navigation_stress_progress.log'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Write-NavigationStressLine {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $progressPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Import-NavigationStressModules {
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

Set-Location -LiteralPath $ProjectRoot
$steps = New-Object System.Collections.Generic.List[object]
$startedAt = Get-Date
$ctx = $null
$ok = $false
$errorText = $null

try {
    Write-NavigationStressLine 'Navigation stress test started.'
    Write-NavigationStressLine ("ProjectRoot={0}" -f $ProjectRoot)
    Write-NavigationStressLine ("Cycles={0}; PauseMs={1}" -f $Cycles, $PauseMs)

    Import-NavigationStressModules
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

    $ctx = New-MainWindowContext
    $ctx.Window.ShowInTaskbar = $false
    $ctx.Window.WindowState = [System.Windows.WindowState]::Minimized
    $ctx = Initialize-MainWindowControllers -Ctx $ctx
    $ctx = Initialize-MainWindowNavigation -Ctx $ctx
    $ctx.Window.Show()
    $ctx.Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    $actions = @(
        @{ Name = 'Dashboard'; Action = $ctx.NavigateDashboard },
        @{ Name = 'Images'; Action = $ctx.NavigateImages },
        @{ Name = 'Media'; Action = $ctx.NavigateMedia },
        @{ Name = 'Driver'; Action = $ctx.NavigateDriver },
        @{ Name = 'Updates'; Action = $ctx.NavigateUpdates },
        @{ Name = 'Settings'; Action = $ctx.NavigateSettings }
    )

    for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
        foreach ($item in $actions) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $stepOk = $true
            $stepError = ''
            try {
                & ([scriptblock]$item.Action)
                $ctx.Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
                if ($PauseMs -gt 0) {
                    Start-Sleep -Milliseconds $PauseMs
                }
                $ctx.Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
            } catch {
                $stepOk = $false
                $stepError = $_.Exception.Message
            } finally {
                $sw.Stop()
            }

            $steps.Add([pscustomobject]@{
                Cycle      = $cycle
                Page       = [string]$item.Name
                Ok         = $stepOk
                DurationMs = [int]$sw.ElapsedMilliseconds
                Error      = $stepError
            }) | Out-Null

            Write-NavigationStressLine ("{0}/{1} {2}: {3}ms {4}" -f $cycle, $Cycles, [string]$item.Name, [int]$sw.ElapsedMilliseconds, $(if ($stepOk) { 'OK' } else { 'FAIL' }))

            if (-not $stepOk) {
                throw "Navigation stress failed: $($item.Name) cycle $cycle - $stepError"
            }
        }
    }

    $ok = $true
    Write-NavigationStressLine 'Navigation stress test completed successfully.'
} catch {
    $errorText = $_.Exception.Message
    Write-NavigationStressLine ("FAIL {0}" -f $errorText)
} finally {
    try {
        if ($ctx -and $ctx.Window) {
            $ctx.Window.Close()
        }
    } catch {}
}

$allSteps = @($steps.ToArray())
$result = [pscustomobject]@{
    Ok            = $ok
    Error         = $errorText
    StartedAt     = $startedAt.ToString('o')
    FinishedAt    = (Get-Date).ToString('o')
    ProjectRoot   = $ProjectRoot
    OutputDir     = $runDir
    ProgressPath  = $progressPath
    ResultPath    = $resultPath
    Cycles        = $Cycles
    PauseMs       = $PauseMs
    StepCount     = $allSteps.Count
    MaxDurationMs = if ($allSteps.Count -gt 0) { [int](($allSteps | Measure-Object DurationMs -Maximum).Maximum) } else { 0 }
    AvgDurationMs = if ($allSteps.Count -gt 0) { [int](($allSteps | Measure-Object DurationMs -Average).Average) } else { 0 }
    Steps         = $allSteps
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-NavigationStressLine ("RESULT {0}" -f $resultPath)

if (-not $ok) { exit 1 }
exit 0
