Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Variable -Name UiThemeStyleCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:UiThemeStyleCache = @{}
}

function Get-UiThemeStyleCacheKey {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    $parts = @(
        $Name,
        [string]$Palette.Window,
        [string]$Palette.Surface,
        [string]$Palette.SurfaceSoft,
        [string]$Palette.Input,
        [string]$Palette.Border,
        [string]$Palette.Text,
        [string]$Palette.Hint,
        [string]$Palette.Accent,
        [string]$Palette.AccentDark,
        [string]$Palette.ButtonText
    )

    return ($parts -join '|')
}

function Get-UiThemeCachedStyle {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Palette,
        [Parameter(Mandatory)][scriptblock]$Factory
    )

    $key = Get-UiThemeStyleCacheKey -Name $Name -Palette $Palette
    if ($script:UiThemeStyleCache.ContainsKey($key)) {
        return $script:UiThemeStyleCache[$key]
    }

    $style = & $Factory
    $script:UiThemeStyleCache[$key] = $style
    return $style
}
