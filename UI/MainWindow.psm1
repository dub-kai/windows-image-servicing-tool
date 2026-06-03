Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\UiAsync.psm1"   -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "Core\Config.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\Localization.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\Notifications.psm1" -MustExist) -Force -DisableNameChecking -Global

Import-Module (Resolve-ProjectPath "UI\Controllers\ImagesController.psm1"    -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "UI\Controllers\DashboardController.psm1" -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "UI\Controllers\SettingsController.psm1"  -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "UI\Controllers\DriverController.psm1"    -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "UI\Controllers\UpdatesController.psm1"   -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "UI\Controllers\MediaBuilderController.psm1" -MustExist) -Force -DisableNameChecking

$partsRoot = Join-Path $PSScriptRoot "MainWindow"
if (-not (Test-Path -LiteralPath $partsRoot)) { throw "MainWindow parts folder fehlt: $partsRoot" }

$parts = @(
    "MainWindow.Context.ps1",
    "MainWindow.Controllers.ps1",
    "MainWindow.Navigation.ps1",
    "MainWindow.Start.ps1"
)

foreach ($f in $parts) {
    $p = Join-Path $partsRoot $f
    if (-not (Test-Path -LiteralPath $p)) { throw "MainWindow split part fehlt: $p" }
    . $p
}

if (-not (Get-Command Start-MainWindow -ErrorAction SilentlyContinue)) {
    throw "MainWindow: Start-MainWindow fehlt nach Split-Load."
}

Export-ModuleMember -Function Start-MainWindow
