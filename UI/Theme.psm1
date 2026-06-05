Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null } catch {}
Import-Module (Resolve-ProjectPath "Core\Config.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking -Global

$themePartsRoot = Join-Path $PSScriptRoot "Theme"
if (-not (Test-Path -LiteralPath $themePartsRoot)) { throw "Theme parts folder fehlt: $themePartsRoot" }

$themeParts = @(
    "Theme.Palette.ps1",
    "Theme.Apply.ps1"
)

foreach ($file in $themeParts) {
    $path = Join-Path $themePartsRoot $file
    if (-not (Test-Path -LiteralPath $path)) { throw "Theme split part fehlt: $path" }
    . $path
}

Set-Item -Path function:global:Get-UiThemeName -Value ${function:Get-UiThemeName} -Force
Set-Item -Path function:global:Set-UiTheme -Value ${function:Set-UiTheme} -Force
Set-Item -Path function:global:Apply-UiTheme -Value ${function:Apply-UiTheme} -Force

Export-ModuleMember -Function Get-UiThemeName, Set-UiTheme, Apply-UiTheme
