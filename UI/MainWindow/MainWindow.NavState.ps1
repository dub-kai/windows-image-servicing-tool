Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-MainWindowSolidBrush {
    param([Parameter(Mandatory)][string]$Color)

    return ([System.Windows.Media.BrushConverter]::new().ConvertFromString($Color))
}

function Set-MainWindowActiveNav {
    param(
        [Parameter(Mandatory)][object]$Ctx,
        [Parameter(Mandatory)][string]$Key
    )

    $window = $null
    try { $window = $Ctx.Window } catch {}
    if (-not $window) { return }

    $dark = $false
    try { $dark = ((Get-UiThemeName) -eq 'Dark') } catch {}

    $normalBackground = if ($dark) { New-MainWindowSolidBrush '#1A211F' } else { New-MainWindowSolidBrush '#FFFFFF' }
    $normalForeground = if ($dark) { New-MainWindowSolidBrush '#ECEDE8' } else { New-MainWindowSolidBrush '#0F172A' }
    $normalBorder = if ($dark) { New-MainWindowSolidBrush '#33413D' } else { New-MainWindowSolidBrush '#D5DEE6' }
    $activeBackground = if ($dark) { New-MainWindowSolidBrush '#0F766E' } else { New-MainWindowSolidBrush '#0F766E' }
    $activeForeground = New-MainWindowSolidBrush '#FFFFFF'
    $activeBorder = if ($dark) { New-MainWindowSolidBrush '#2DD4BF' } else { New-MainWindowSolidBrush '#0F766E' }

    $navButtons = @{
        Dashboard = 'BtnDashboard'
        Images    = 'BtnImages'
        Media     = 'BtnMedia'
        Driver    = 'BtnDriver'
        Updates   = 'BtnUpdates'
        Settings  = 'BtnSettings'
    }

    foreach ($navKey in $navButtons.Keys) {
        $button = $null
        try { $button = $window.FindName($navButtons[$navKey]) } catch {}
        if (-not $button) { continue }

        $isActive = ([string]$navKey -eq [string]$Key)
        try { $button.Background = if ($isActive) { $activeBackground } else { $normalBackground } } catch {}
        try { $button.Foreground = if ($isActive) { $activeForeground } else { $normalForeground } } catch {}
        try { $button.BorderBrush = if ($isActive) { $activeBorder } else { $normalBorder } } catch {}
        try { $button.FontWeight = if ($isActive) { [System.Windows.FontWeights]::Bold } else { [System.Windows.FontWeights]::SemiBold } } catch {}
    }

    try {
        if ($Ctx.SetStatus -is [scriptblock]) {
            $label = Get-UiString -Key ('ShellPage{0}' -f $Key)
            & $Ctx.SetStatus (Get-UiString -Key 'ShellPageStatusFormat' -Args @($label))
        }
    } catch {}
}
