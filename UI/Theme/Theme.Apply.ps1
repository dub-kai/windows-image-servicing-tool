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

function New-UiThemeSetter {
    param(
        [Parameter(Mandatory)]$Property,
        [AllowNull()]$Value
    )

    return New-Object System.Windows.Setter($Property, $Value)
}

function New-UiThemeStyle {
    param(
        [Parameter(Mandatory)][type]$TargetType,
        [Parameter(Mandatory)][object[]]$Setters
    )

    $style = New-Object System.Windows.Style($TargetType)
    foreach ($setter in @($Setters)) {
        if ($setter) { [void]$style.Setters.Add($setter) }
    }
    return $style
}

function New-UiThemeTrigger {
    param(
        [Parameter(Mandatory)]$Property,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][object[]]$Setters
    )

    $trigger = New-Object System.Windows.Trigger
    $trigger.Property = $Property
    $trigger.Value = $Value
    foreach ($setter in @($Setters)) {
        if ($setter) { [void]$trigger.Setters.Add($setter) }
    }
    return $trigger
}

function Add-UiThemeStyleTrigger {
    param(
        [Parameter(Mandatory)][System.Windows.Style]$Style,
        [AllowNull()]$Trigger
    )

    if ($Trigger) {
        try { [void]$Style.Triggers.Add($Trigger) } catch {}
    }
}

function Set-UiThemeResource {
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)]$Key,
        [AllowNull()]$Value
    )

    try { $Element.Resources[$Key] = $Value } catch {}
}

function Set-UiThemeSystemColorResources {
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::WindowBrushKey) -Value $Palette.Input
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::WindowTextBrushKey) -Value $Palette.Text
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::ControlBrushKey) -Value $Palette.Input
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::ControlTextBrushKey) -Value $Palette.Text
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::ControlDarkBrushKey) -Value $Palette.Border
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::ControlLightBrushKey) -Value $Palette.Surface
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::ControlLightLightBrushKey) -Value $Palette.SurfaceSoft
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::GrayTextBrushKey) -Value $Palette.Hint
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::HighlightBrushKey) -Value $Palette.AccentDark
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::HighlightTextBrushKey) -Value $Palette.ButtonText
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::InactiveSelectionHighlightBrushKey) -Value $Palette.SurfaceSoft
    Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::InactiveSelectionHighlightTextBrushKey) -Value $Palette.Text
    try { Set-UiThemeResource -Element $Element -Key ([System.Windows.SystemColors]::ScrollBarBrushKey) -Value $Palette.SurfaceSoft } catch {}
}

function Set-UiThemeButtonResources {
    param(
        [Parameter(Mandatory)]$Button,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeSystemColorResources -Element $Button -Palette $Palette

    try {
        $style = Get-UiThemeCachedStyle -Name 'Button' -Palette $Palette -Factory {
            $styleLocal = New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.Button]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.AccentDark),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.ButtonText),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.AccentDark),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::PaddingProperty) -Value (New-Object System.Windows.Thickness(10, 4, 10, 4)))
                )

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.Control]::IsEnabledProperty) `
                -Value $false `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.SurfaceSoft),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Hint),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border)
                ))

            return $styleLocal
        }

        $Button.Style = $style
    } catch {}
}

function Set-UiThemeComboBoxStyles {
    param(
        [Parameter(Mandatory)]$ComboBox,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeSystemColorResources -Element $ComboBox -Palette $Palette

    foreach ($entry in @(
        @{ Key = 'ComboBox.Static.Background'; Value = $Palette.Input },
        @{ Key = 'ComboBox.Static.Border'; Value = $Palette.Border },
        @{ Key = 'ComboBox.Static.Glyph'; Value = $Palette.Text },
        @{ Key = 'ComboBox.MouseOver.Background'; Value = $Palette.SurfaceSoft },
        @{ Key = 'ComboBox.MouseOver.Border'; Value = $Palette.AccentDark },
        @{ Key = 'ComboBox.MouseOver.Glyph'; Value = $Palette.Text },
        @{ Key = 'ComboBox.Pressed.Background'; Value = $Palette.SurfaceSoft },
        @{ Key = 'ComboBox.Pressed.Border'; Value = $Palette.AccentDark },
        @{ Key = 'ComboBox.Pressed.Glyph'; Value = $Palette.Text },
        @{ Key = 'ComboBox.Disabled.Background'; Value = $Palette.SurfaceSoft },
        @{ Key = 'ComboBox.Disabled.Border'; Value = $Palette.Border },
        @{ Key = 'ComboBox.Disabled.Foreground'; Value = $Palette.Hint },
        @{ Key = 'ComboBox.Disabled.Glyph'; Value = $Palette.Hint },
        @{ Key = 'ComboBox.Static.Editable.Background'; Value = $Palette.Input },
        @{ Key = 'ComboBox.Static.Editable.Border'; Value = $Palette.Border },
        @{ Key = 'ComboBox.MouseOver.Editable.Background'; Value = $Palette.Input },
        @{ Key = 'ComboBox.MouseOver.Editable.Border'; Value = $Palette.AccentDark },
        @{ Key = 'ComboBox.Disabled.Editable.Background'; Value = $Palette.SurfaceSoft },
        @{ Key = 'ComboBox.Disabled.Editable.Border'; Value = $Palette.Border }
    )) {
        try { Set-UiThemeResource -Element $ComboBox -Key ([string]$entry.Key) -Value $entry.Value } catch {}
    }

    try {
        $comboStyle = Get-UiThemeCachedStyle -Name 'ComboBox' -Palette $Palette -Factory {
            $styleLocal = New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.ComboBox]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.Input),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border)
                )

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.Control]::IsEnabledProperty) `
                -Value $false `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.SurfaceSoft),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Hint),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border)
                ))

            return $styleLocal
        }

        $ComboBox.Style = $comboStyle
    } catch {}

    try {
        $itemStyle = Get-UiThemeCachedStyle -Name 'ComboBoxItem' -Palette $Palette -Factory {
            $styleLocal = New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.ComboBoxItem]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.Input),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::PaddingProperty) -Value (New-Object System.Windows.Thickness(8, 4, 8, 4)))
                )

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.ComboBoxItem]::IsSelectedProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.AccentDark),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.ButtonText),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.AccentDark)
                ))

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.Control]::IsMouseOverProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.SurfaceSoft),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text)
                ))

            return $styleLocal
        }

        $ComboBox.ItemContainerStyle = $itemStyle
    } catch {}
}

function Set-UiThemeTextBoxResources {
    param(
        [Parameter(Mandatory)]$TextBox,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeSystemColorResources -Element $TextBox -Palette $Palette

    foreach ($entry in @(
        @{ Key = 'TextBox.Static.Background'; Value = $Palette.Input },
        @{ Key = 'TextBox.Static.Border'; Value = $Palette.Border },
        @{ Key = 'TextBox.MouseOver.Border'; Value = $Palette.AccentDark },
        @{ Key = 'TextBox.Focus.Border'; Value = $Palette.AccentDark },
        @{ Key = 'TextBox.Disabled.Background'; Value = $Palette.SurfaceSoft },
        @{ Key = 'TextBox.Disabled.Border'; Value = $Palette.Border }
    )) {
        try { Set-UiThemeResource -Element $TextBox -Key ([string]$entry.Key) -Value $entry.Value } catch {}
    }

    try { $TextBox.SelectionBrush = $Palette.AccentDark } catch {}
    try { $TextBox.SelectionTextBrush = $Palette.ButtonText } catch {}
}

function Set-UiThemeInputResources {
    param(
        [Parameter(Mandatory)]$Input,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeSystemColorResources -Element $Input -Palette $Palette

    foreach ($entry in @(
        @{ Key = 'TextBox.Static.Background'; Value = $Palette.Input },
        @{ Key = 'TextBox.Static.Border'; Value = $Palette.Border },
        @{ Key = 'TextBox.MouseOver.Border'; Value = $Palette.AccentDark },
        @{ Key = 'TextBox.Focus.Border'; Value = $Palette.AccentDark },
        @{ Key = 'TextBox.Disabled.Background'; Value = $Palette.SurfaceSoft },
        @{ Key = 'TextBox.Disabled.Border'; Value = $Palette.Border }
    )) {
        try { Set-UiThemeResource -Element $Input -Key ([string]$entry.Key) -Value $entry.Value } catch {}
    }
}

function Set-UiThemeToolTipResources {
    param(
        [Parameter(Mandatory)]$ToolTip,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeSystemColorResources -Element $ToolTip -Palette $Palette
    Set-UiThemeProperty -Element $ToolTip -PropertyName 'Background' -Value $Palette.Input
    Set-UiThemeProperty -Element $ToolTip -PropertyName 'Foreground' -Value $Palette.Text
    Set-UiThemeProperty -Element $ToolTip -PropertyName 'BorderBrush' -Value $Palette.Border
}

function Set-UiThemeToggleResources {
    param(
        [Parameter(Mandatory)]$Toggle,
        [Parameter(Mandatory)][hashtable]$Palette,
        [Parameter(Mandatory)][string]$Prefix
    )

    Set-UiThemeSystemColorResources -Element $Toggle -Palette $Palette

    foreach ($entry in @(
        @{ Key = "$Prefix.Static.Background"; Value = $Palette.Input },
        @{ Key = "$Prefix.Static.Border"; Value = $Palette.Border },
        @{ Key = "$Prefix.Static.Glyph"; Value = $Palette.ButtonText },
        @{ Key = "$Prefix.MouseOver.Background"; Value = $Palette.SurfaceSoft },
        @{ Key = "$Prefix.MouseOver.Border"; Value = $Palette.AccentDark },
        @{ Key = "$Prefix.MouseOver.Glyph"; Value = $Palette.ButtonText },
        @{ Key = "$Prefix.Pressed.Background"; Value = $Palette.SurfaceSoft },
        @{ Key = "$Prefix.Pressed.Border"; Value = $Palette.AccentDark },
        @{ Key = "$Prefix.Pressed.Glyph"; Value = $Palette.ButtonText },
        @{ Key = "$Prefix.Disabled.Background"; Value = $Palette.SurfaceSoft },
        @{ Key = "$Prefix.Disabled.Border"; Value = $Palette.Border },
        @{ Key = "$Prefix.Disabled.Glyph"; Value = $Palette.Hint },
        @{ Key = "$Prefix.Disabled.Foreground"; Value = $Palette.Hint }
    )) {
        try { Set-UiThemeResource -Element $Toggle -Key ([string]$entry.Key) -Value $entry.Value } catch {}
    }
}

function Set-UiThemeListBoxStyles {
    param(
        [Parameter(Mandatory)]$ListBox,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeSystemColorResources -Element $ListBox -Palette $Palette

    try {
        $itemStyle = Get-UiThemeCachedStyle -Name 'ListBoxItem' -Palette $Palette -Factory {
            $styleLocal = New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.ListBoxItem]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.Input),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::PaddingProperty) -Value (New-Object System.Windows.Thickness(6, 3, 6, 3)))
                )

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.ListBoxItem]::IsSelectedProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.AccentDark),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.ButtonText),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.AccentDark)
                ))

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.Control]::IsMouseOverProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.SurfaceSoft),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text)
                ))

            return $styleLocal
        }

        $ListBox.ItemContainerStyle = $itemStyle
    } catch {}
}

function Set-UiThemeListViewStyles {
    param(
        [Parameter(Mandatory)]$ListView,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    Set-UiThemeSystemColorResources -Element $ListView -Palette $Palette

    try {
        $itemStyle = Get-UiThemeCachedStyle -Name 'ListViewItem' -Palette $Palette -Factory {
            $styleLocal = New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.ListViewItem]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.Input),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border)
                )

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.ListViewItem]::IsSelectedProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.AccentDark),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.ButtonText),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.AccentDark)
                ))

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.Control]::IsMouseOverProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.SurfaceSoft),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text)
                ))

            return $styleLocal
        }

        $ListView.ItemContainerStyle = $itemStyle
    } catch {}

    try {
        $view = $ListView.View
        if ($view -is [System.Windows.Controls.GridView]) {
            $view.ColumnHeaderContainerStyle = Get-UiThemeCachedStyle -Name 'GridViewColumnHeader' -Palette $Palette -Factory {
                New-UiThemeStyle `
                    -TargetType ([System.Windows.Controls.GridViewColumnHeader]) `
                    -Setters @(
                        (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.SurfaceSoft),
                        (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                        (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border),
                        (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderThicknessProperty) -Value (New-Object System.Windows.Thickness(0, 0, 1, 1))),
                        (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::FontWeightProperty) -Value ([System.Windows.FontWeights]::SemiBold)),
                        (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty) -Value ([System.Windows.HorizontalAlignment]::Left))
                    )
            }
        }
    } catch {}
}

function Set-UiThemeDataGridStyles {
    param(
        [Parameter(Mandatory)]$DataGrid,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    try {
        $DataGrid.ColumnHeaderStyle = Get-UiThemeCachedStyle -Name 'DataGridColumnHeader' -Palette $Palette -Factory {
            New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.Primitives.DataGridColumnHeader]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.SurfaceSoft),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderThicknessProperty) -Value (New-Object System.Windows.Thickness(0, 0, 0, 1))),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::FontWeightProperty) -Value ([System.Windows.FontWeights]::SemiBold)),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty) -Value ([System.Windows.HorizontalAlignment]::Left))
                )
        }
    } catch {}

    try {
        $rowStyle = Get-UiThemeCachedStyle -Name 'DataGridRow' -Palette $Palette -Factory {
            $styleLocal = New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.DataGridRow]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.Input),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border)
                )

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.DataGridRow]::IsSelectedProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.AccentDark),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.ButtonText),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.AccentDark)
                ))

            return $styleLocal
        }

        $DataGrid.RowStyle = $rowStyle
    } catch {}

    try {
        $cellStyle = Get-UiThemeCachedStyle -Name 'DataGridCell' -Palette $Palette -Factory {
            $styleLocal = New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.DataGridCell]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value ([System.Windows.Media.Brushes]::Transparent)),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.Text),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.Border)
                )

            Add-UiThemeStyleTrigger -Style $styleLocal -Trigger (New-UiThemeTrigger `
                -Property ([System.Windows.Controls.DataGridCell]::IsSelectedProperty) `
                -Value $true `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $Palette.AccentDark),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $Palette.ButtonText),
                    (New-UiThemeSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value $Palette.AccentDark)
                ))

            return $styleLocal
        }

        $DataGrid.CellStyle = $cellStyle
    } catch {}

    try {
        $textStyle = Get-UiThemeCachedStyle -Name 'DataGridTextBlock' -Palette $Palette -Factory {
            New-UiThemeStyle `
                -TargetType ([System.Windows.Controls.TextBlock]) `
                -Setters @(
                    (New-UiThemeSetter -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -Value $Palette.Text)
                )
        }

        foreach ($column in @($DataGrid.Columns)) {
            if ($column -and $column.PSObject.Properties.Match('ElementStyle').Count -gt 0) {
                $column.ElementStyle = $textStyle
            }
        }
    } catch {}
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
        'Label' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'Button' {
            Set-UiThemeButtonResources -Button $Element -Palette $Palette
        }
        'RepeatButton' {
            Set-UiThemeButtonResources -Button $Element -Palette $Palette
        }
        'TextBox' {
            Set-UiThemeTextBoxResources -TextBox $Element -Palette $Palette
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'PasswordBox' {
            Set-UiThemeInputResources -Input $Element -Palette $Palette
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'RichTextBox' {
            Set-UiThemeInputResources -Input $Element -Palette $Palette
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'ComboBox' {
            Set-UiThemeSystemColorResources -Element $Element -Palette $Palette
            Set-UiThemeComboBoxStyles -ComboBox $Element -Palette $Palette
        }
        'ComboBoxItem' {
            Set-UiThemeSystemColorResources -Element $Element -Palette $Palette
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'CheckBox' {
            Set-UiThemeToggleResources -Toggle $Element -Palette $Palette -Prefix 'CheckBox'
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'RadioButton' {
            Set-UiThemeToggleResources -Toggle $Element -Palette $Palette -Prefix 'RadioButton'
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'GroupBox' {
            Set-UiThemeSystemColorResources -Element $Element -Palette $Palette
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Surface
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'TabControl' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Surface
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'TabItem' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.SurfaceSoft
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'ListBox' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
            Set-UiThemeListBoxStyles -ListBox $Element -Palette $Palette
        }
        'ScrollViewer' {
            Set-UiThemeSystemColorResources -Element $Element -Palette $Palette
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
        }
        'ScrollBar' {
            Set-UiThemeSystemColorResources -Element $Element -Palette $Palette
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.SurfaceSoft
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Border
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'Thumb' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Border
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.AccentDark
        }
        'Track' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.SurfaceSoft
        }
        'ListView' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
            Set-UiThemeListViewStyles -ListView $Element -Palette $Palette
        }
        'DataGrid' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
            Set-UiThemeProperty -Element $Element -PropertyName 'RowBackground' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'AlternatingRowBackground' -Value $Palette.Surface
            Set-UiThemeProperty -Element $Element -PropertyName 'HorizontalGridLinesBrush' -Value $Palette.Border
            Set-UiThemeProperty -Element $Element -PropertyName 'VerticalGridLinesBrush' -Value $Palette.Border
            Set-UiThemeDataGridStyles -DataGrid $Element -Palette $Palette
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
        'ToolTip' {
            Set-UiThemeToolTipResources -ToolTip $Element -Palette $Palette
        }
        'Menu' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Surface
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'MenuItem' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Surface
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
        }
        'ContextMenu' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Input
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.Text
            Set-UiThemeProperty -Element $Element -PropertyName 'BorderBrush' -Value $Palette.Border
        }
        'StatusBar' {
            Set-UiThemeProperty -Element $Element -PropertyName 'Background' -Value $Palette.Footer
            Set-UiThemeProperty -Element $Element -PropertyName 'Foreground' -Value $Palette.FooterText
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
