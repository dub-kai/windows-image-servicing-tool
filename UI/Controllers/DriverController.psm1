Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ctx = $null
$script:isBusy = $false
$script:suppressMountSelectionReload = $false
$script:reloadPending = $false

$uiRoot = Split-Path -Parent $PSScriptRoot

Import-Module (Join-Path $uiRoot "UiHelpers.psm1") -Force
Import-Module (Join-Path $uiRoot "UiAsync.psm1")   -Force

$driverDir = Join-Path $PSScriptRoot "Driver"

$parts = @(
    "Driver.Helpers.ps1",
    "Driver.Busy.ps1",
    "Driver.Selection.ps1",
    "Driver.Dialogs.ps1",
    "Driver.List.ps1",
    "Driver.Mounts.ps1",
    "Driver.Actions.ps1",
    "Driver.Context.ps1",
    "Driver.Events.ps1"
)

foreach ($part in $parts) {
    $path = Join-Path $driverDir $part
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Driver controller part nicht gefunden: $path"
    }

    . $path
}

Export-ModuleMember -Function Initialize-DriverController, Refresh-DriverUI, Refresh-DriverMountedList, Request-DriversReload