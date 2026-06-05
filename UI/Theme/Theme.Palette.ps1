Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:brushConverter = New-Object System.Windows.Media.BrushConverter

function New-UiThemeBrush {
    param([Parameter(Mandatory)][string]$Color)

    return $script:brushConverter.ConvertFromString($Color)
}

function Get-UiThemeName {
    [CmdletBinding()]
    param()

    $value = $null
    try { $value = Get-ConfigValue -Key 'UiTheme' -Default 'Light' } catch {}
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return 'Light' }
    if ([string]$value -eq 'Dark') { return 'Dark' }
    return 'Light'
}

function Set-UiTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Light', 'Dark')]
        [string]$Theme
    )

    Set-ConfigValue -Key 'UiTheme' -Value $Theme -Persist | Out-Null
    return $Theme
}

function Get-UiThemePalette {
    param([string]$Theme = $(Get-UiThemeName))

    if ($Theme -eq 'Dark') {
        return @{
            Window      = New-UiThemeBrush '#0E1111'
            Header      = New-UiThemeBrush '#0B2A27'
            Sidebar     = New-UiThemeBrush '#151918'
            Content     = New-UiThemeBrush '#111513'
            Footer      = New-UiThemeBrush '#0B0F0E'
            Surface     = New-UiThemeBrush '#1A211F'
            SurfaceSoft = New-UiThemeBrush '#202A26'
            Input       = New-UiThemeBrush '#101413'
            Border      = New-UiThemeBrush '#33413D'
            Text        = New-UiThemeBrush '#ECEDE8'
            Muted       = New-UiThemeBrush '#C6D0CB'
            Hint        = New-UiThemeBrush '#98A49F'
            Accent      = New-UiThemeBrush '#2DD4BF'
            AccentDark  = New-UiThemeBrush '#0F766E'
            Warning     = New-UiThemeBrush '#F59E0B'
            HeaderText  = New-UiThemeBrush '#F8FAF7'
            HeaderMuted = New-UiThemeBrush '#BFD7D1'
            FooterText  = New-UiThemeBrush '#E7ECE9'
            FooterMuted = New-UiThemeBrush '#9CAAA5'
            Overlay     = New-UiThemeBrush '#88000000'
            ButtonText  = New-UiThemeBrush '#F8FAF7'
        }
    }

    return @{
        Window      = New-UiThemeBrush '#E8EEF2'
        Header      = New-UiThemeBrush '#13283B'
        Sidebar     = New-UiThemeBrush '#F2F6F9'
        Content     = New-UiThemeBrush '#EEF3F6'
        Footer      = New-UiThemeBrush '#102131'
        Surface     = New-UiThemeBrush '#F7FAFC'
        SurfaceSoft = New-UiThemeBrush '#EEF6FF'
        Input       = New-UiThemeBrush '#FFFFFF'
        Border      = New-UiThemeBrush '#D5DEE6'
        Text        = New-UiThemeBrush '#0F172A'
        Muted       = New-UiThemeBrush '#374151'
        Hint        = New-UiThemeBrush '#64748B'
        Accent      = New-UiThemeBrush '#0F766E'
        AccentDark  = New-UiThemeBrush '#115E59'
        Warning     = New-UiThemeBrush '#92400E'
        HeaderText  = New-UiThemeBrush '#FFFFFF'
        HeaderMuted = New-UiThemeBrush '#B7C5D2'
        FooterText  = New-UiThemeBrush '#E5E7EB'
        FooterMuted = New-UiThemeBrush '#97A7B7'
        Overlay     = New-UiThemeBrush '#66000000'
        ButtonText  = New-UiThemeBrush '#FFFFFF'
    }
}
