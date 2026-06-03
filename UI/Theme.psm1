Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null } catch {}
Import-Module (Resolve-ProjectPath "Core\Config.psm1" -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force -DisableNameChecking -Global

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
            Window      = New-UiThemeBrush '#0B1120'
            Header      = New-UiThemeBrush '#0F172A'
            Sidebar     = New-UiThemeBrush '#111827'
            Content     = New-UiThemeBrush '#111827'
            Footer      = New-UiThemeBrush '#0B1120'
            Surface     = New-UiThemeBrush '#172033'
            SurfaceSoft = New-UiThemeBrush '#1F2937'
            Input       = New-UiThemeBrush '#0F172A'
            Border      = New-UiThemeBrush '#334155'
            Text        = New-UiThemeBrush '#E5E7EB'
            Muted       = New-UiThemeBrush '#CBD5E1'
            Hint        = New-UiThemeBrush '#94A3B8'
            Accent      = New-UiThemeBrush '#14B8A6'
            AccentDark  = New-UiThemeBrush '#0F766E'
            Warning     = New-UiThemeBrush '#FBBF24'
            HeaderText  = New-UiThemeBrush '#F8FAFC'
            HeaderMuted = New-UiThemeBrush '#CBD5E1'
            FooterText  = New-UiThemeBrush '#E5E7EB'
            FooterMuted = New-UiThemeBrush '#94A3B8'
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
    }
}

function Add-UiThemeChild {
    param(
        [Parameter(Mandatory)][System.Collections.Queue]$Queue,
        [AllowNull()]$Child
    )

    if ($null -ne $Child -and ($Child -isnot [string])) {
        try { $Queue.Enqueue($Child) } catch {}
    }
}

function Add-UiThemeChildren {
    param(
        [Parameter(Mandatory)][System.Collections.Queue]$Queue,
        [Parameter(Mandatory)]$Element
    )

    try { Add-UiThemeChild -Queue $Queue -Child $Element.Content } catch {}
    try { Add-UiThemeChild -Queue $Queue -Child $Element.Header } catch {}
    try { Add-UiThemeChild -Queue $Queue -Child $Element.ToolTip } catch {}
    try { Add-UiThemeChild -Queue $Queue -Child $Element.View } catch {}

    try {
        foreach ($item in @($Element.Items)) {
            Add-UiThemeChild -Queue $Queue -Child $item
        }
    } catch {}

    try {
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Element)) {
            Add-UiThemeChild -Queue $Queue -Child $child
        }
    } catch {}

    try {
        if ($Element -is [System.Windows.DependencyObject]) {
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
            for ($i = 0; $i -lt $count; $i++) {
                Add-UiThemeChild -Queue $Queue -Child ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i))
            }
        }
    } catch {}
}

function Set-UiThemeProperty {
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)][string]$PropertyName,
        [AllowNull()]$Value
    )

    if (-not $Element) { return }
    if ($Element.PSObject.Properties.Match($PropertyName).Count -lt 1) { return }
    try { $Element.$PropertyName = $Value } catch {}
}

function Set-UiThemeNamedShell {
    param(
        [Parameter(Mandatory)]$Root,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    $named = @{
        MainWindow = @{ Background = 'Window' }
        ShellHeader = @{ Background = 'Header' }
        ShellSidebar = @{ Background = 'Sidebar' }
        ShellContent = @{ Background = 'Content' }
        ShellFooter = @{ Background = 'Footer' }
        ShellStateCard = @{ Background = 'Input'; BorderBrush = 'Border' }
        TxtMainTitle = @{ Foreground = 'HeaderText' }
        TxtMainSubtitle = @{ Foreground = 'HeaderMuted' }
        TxtShellState = @{ Foreground = 'Text' }
        TxtIso = @{ Foreground = 'Muted' }
        TxtImage = @{ Foreground = 'Muted' }
        TxtStatus = @{ Foreground = 'FooterText' }
        TxtBuild = @{ Foreground = 'FooterMuted' }
    }

    foreach ($name in $named.Keys) {
        $element = $null
        try { $element = Find-Ui -Root $Root -Name $name } catch {}
        if (-not $element) { continue }

        foreach ($propertyName in $named[$name].Keys) {
            Set-UiThemeProperty -Element $element -PropertyName $propertyName -Value $Palette[$named[$name][$propertyName]]
        }
    }
}

function Apply-UiThemeToElement {
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    $typeName = ''
    $name = ''
    try { $typeName = $Element.GetType().Name } catch {}
    try { $name = [string]$Element.Name } catch {}

    switch ($typeName) {
        'Window' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Window
        }
        'Page' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value ([System.Windows.Media.Brushes]::Transparent)
        }
        'Border' {
            if ($name -eq 'BusyOverlay') {
                Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value (New-UiThemeBrush '#80000000')
            } else {
                Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Surface
            }
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'TextBlock' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'TextBox' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'ComboBox' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'ComboBoxItem' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'CheckBox' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'RadioButton' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'GroupBox' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Surface
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'ListBox' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'ListView' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'DataGrid' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
            Set-UiThemeProperty -Element $Element -PropertyName 'RowBackground' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'AlternatingRowBackground' -Value $Palette.Surface
        }
        'Frame' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value ([System.Windows.Media.Brushes]::Transparent)
        }
        'Separator' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Border
        }
    }
}

function Apply-UiTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Root,
        [ValidateSet('Light', 'Dark')]
        [string]$Theme = $(Get-UiThemeName)
    )

    if (-not $Root) { return }

    $palette = Get-UiThemePalette -Theme $Theme
    $queue = New-Object System.Collections.Queue
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    Add-UiThemeChild -Queue $queue -Child $Root

    while ($queue.Count -gt 0) {
        $element = $queue.Dequeue()
        if ($null -eq $element) { continue }

        $hash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($element)
        if (-not $seen.Add($hash)) { continue }

        Apply-UiThemeToElement -Element $element -Palette $palette
        Add-UiThemeChildren -Queue $queue -Element $element
    }

    Set-UiThemeNamedShell -Root $Root -Palette $palette
}

Set-Item -Path function:global:Get-UiThemeName -Value ${function:Get-UiThemeName} -Force
Set-Item -Path function:global:Set-UiTheme -Value ${function:Set-UiTheme} -Force
Set-Item -Path function:global:Apply-UiTheme -Value ${function:Apply-UiTheme} -Force

Export-ModuleMember -Function Get-UiThemeName, Set-UiTheme, Apply-UiTheme
