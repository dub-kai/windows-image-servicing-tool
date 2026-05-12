function Refresh-DashboardUI {
    if (-not $script:ctx) { return }
    $p = $script:ctx.DashboardPage

    Refresh-DashboardHealthOverview -Root $p
    Refresh-DashboardJobOverview -Root $p

    Set-UiText -Root $p -Name "TxtIsoPath"        -Value (Get-AppStateValue -Key "IsoPath" -Default $null)
    Set-UiText -Root $p -Name "TxtIsoRoot"        -Value (Get-AppStateValue -Key "IsoRoot" -Default $null)
    Set-UiText -Root $p -Name "TxtBootPath"       -Value (Get-AppStateValue -Key "BootImagePath" -Default $null)
    Set-UiText -Root $p -Name "TxtIsoInstallPath" -Value (Get-AppStateValue -Key "IsoInstallImagePath" -Default $null)

    $standalone = Get-AppStateValue -Key "StandaloneImagePath" -Default $null
    $panel = Find-Ui -Root $p -Name "PanelStandalone"
    $txt   = Find-Ui -Root $p -Name "TxtStandaloneImagePath"

    if ($panel -and $panel.PSObject.Properties.Match("Visibility").Count -gt 0) {
        $panel.Visibility = if ($standalone) { "Visible" } else { "Collapsed" }
    }
    if ($txt -and $txt.PSObject.Properties.Match("Text").Count -gt 0) {
        $txt.Text = (Get-DisplayValue $standalone)
    }
}
