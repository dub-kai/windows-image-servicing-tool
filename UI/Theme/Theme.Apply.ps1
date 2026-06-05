Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
        ShellBusyOverlay = @{ Background = 'Overlay' }
        ShellBusyCard = @{ Background = 'Input'; BorderBrush = 'Border' }
        TxtMainTitle = @{ Foreground = 'HeaderText' }
        TxtMainSubtitle = @{ Foreground = 'HeaderMuted' }
        TxtShellBusyMessage = @{ Foreground = 'Text' }
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
            if ($name -in @('BusyOverlay', 'ShellBusyOverlay')) {
                Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Overlay
            } else {
                Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Surface
            }
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'TextBlock' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'Button' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.AccentDark
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.ButtonText
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.AccentDark
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
        'GridViewColumnHeader' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.SurfaceSoft
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'DataGridColumnHeader' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.SurfaceSoft
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'ProgressBar' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.SurfaceSoft
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Accent
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
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
