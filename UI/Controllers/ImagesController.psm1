Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath "UI\UiAsync.psm1"   -MustExist) -Force -DisableNameChecking

$script:ctx = $null
$script:isBusy = $false

function New-WorkerScript {
    param([Parameter(Mandatory)][string]$Code)
    return [scriptblock]::Create($Code)
}

$partsRoot = Join-Path $PSScriptRoot "Images"
if (-not (Test-Path -LiteralPath $partsRoot)) {
    throw "Images parts folder fehlt: $partsRoot"
}

$parts = @(
    "Images.Busy.ps1",
    "Images.View.ps1",
    "Images.Indexes.ps1",
    "Images.Mounted.ps1",
    "Images.MountOps.ps1",
    "Images.Export.ps1",
    "Images.Context.ps1"
)

foreach ($f in $parts) {
    $p = Join-Path $partsRoot $f
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Images split part fehlt: $p"
    }
    . $p
}

$required = @(
    "Initialize-ImagesController",
    "Refresh-ImagesUI",
    "Show-ImagesIndexes",
    "Refresh-MountedList",
    "New-WorkerScript",
    "Start-SaveSourceWimAsync",
    "Start-ExportSelectedIndexAsync"
)

foreach ($name in $required) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "ImagesController: Required function fehlt nach Split-Load: $name"
    }
}

Export-ModuleMember -Function Initialize-ImagesController, Refresh-ImagesUI, Show-ImagesIndexes, Refresh-MountedList
