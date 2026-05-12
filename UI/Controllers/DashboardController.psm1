Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking -Global
try { Import-Module (Resolve-ProjectPath "Core\JobHistory.psm1" -MustExist) -Force -DisableNameChecking -Global } catch {}
try { Import-Module (Resolve-ProjectPath "Services\AdkService.psm1" -MustExist) -Force -DisableNameChecking -Global } catch {}

# shared controller context
$script:ctx = $null

# Split parts live next to this controller: UI\Controllers\Dashboard\*.ps1
$partsRoot = Join-Path $PSScriptRoot "Dashboard"
if (-not (Test-Path -LiteralPath $partsRoot)) {
    throw "Dashboard parts folder fehlt: $partsRoot"
}

$parts = @(
    "Dashboard.Helpers.ps1",
    "Dashboard.AutoDetect.ps1",
    "Dashboard.Overview.ps1",
    "Dashboard.UI.ps1",
    "Dashboard.Context.ps1"
)

foreach ($f in $parts) {
    $p = Join-Path $partsRoot $f
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Dashboard split part fehlt: $p"
    }
    . $p
}

# Sanity: required public entrypoints must exist after dot-sourcing
$required = @(
    "Initialize-DashboardController",
    "Refresh-DashboardUI"
)

foreach ($name in $required) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "DashboardController: Required function fehlt nach Split-Load: $name"
    }
}

Export-ModuleMember -Function Initialize-DashboardController, Refresh-DashboardUI
