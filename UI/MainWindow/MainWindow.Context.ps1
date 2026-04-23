function New-MainWindowContext {
    [CmdletBinding()]
    param()

    $window = Import-XamlFile -RelativePath "UI\MainWindow.xaml"

    Initialize-UiAsync -Window $window

    $bannerPath = Resolve-ProjectPath "UI\Assets\banner.png"
    $banner = New-BitmapImageFromFile -FilePath $bannerPath
    if ($banner) {
        $img = Find-Ui -Root $window -Name "ImgBanner"
        if ($img -and $img.PSObject.Properties.Match("Source").Count -gt 0) { $img.Source = $banner }
        Write-Log -Level INFO -Message ("UI: Banner geladen: {0}" -f $bannerPath)
    }

    $frame     = Find-Ui -Root $window -Name "MainFrame"
    $txtStatus = Find-Ui -Root $window -Name "TxtStatus"
    $txtBuild  = Find-Ui -Root $window -Name "TxtBuild"

    if ($txtBuild -and $txtBuild.PSObject.Properties.Match("Text").Count -gt 0) {
        $txtBuild.Text = "v1.8 (Updates groundwork)"
    }

    $dashboardPage = Import-XamlFile -RelativePath "UI\Pages\Dashboard.xaml"
    $imagesPage    = Import-XamlFile -RelativePath "UI\Pages\Images.xaml"
    $driverPage    = Import-XamlFile -RelativePath "UI\Pages\Driver.xaml"
    $updatesPage   = Import-XamlFile -RelativePath "UI\Pages\Updates.xaml"
    $settingsPage  = Import-XamlFile -RelativePath "UI\Pages\Settings.xaml"

    $setStatus = {
        param([string]$t)
        if ($txtStatus -and $txtStatus.PSObject.Properties.Match("Text").Count -gt 0) { $txtStatus.Text = $t }
    }.GetNewClosure()

    return [pscustomobject]@{
        Window        = $window
        Frame         = $frame
        StartPage     = (Get-ConfigValue -Key 'StartPage' -Default 'Dashboard')
        DashboardPage = $dashboardPage
        ImagesPage    = $imagesPage
        DriverPage    = $driverPage
        UpdatesPage   = $updatesPage
        SettingsPage  = $settingsPage
        SetStatus     = $setStatus

        OnStateChanged = $null

        NavigateDashboard = $null
        NavigateImages    = $null
        NavigateDriver    = $null
        NavigateUpdates   = $null
        NavigateSettings  = $null
    }
}
