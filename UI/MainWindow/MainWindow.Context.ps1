function New-MainWindowContext {
    [CmdletBinding()]
    param()

    $window = Import-XamlFile -RelativePath "UI\MainWindow.xaml"
    Set-MainWindowWorkAreaLayout -Window $window

    Initialize-UiAsync -Window $window
    try { Initialize-AppNotifications -ProjectRoot (Get-ProjectRoot) | Out-Null } catch {}

    try {
        $window.Dispatcher.add_UnhandledException({
            param($sender, $eventArgs)
            try {
                $msg = "UI Dispatcher Exception: {0}" -f $eventArgs.Exception.Message
                Write-Log -Level ERROR -Message $msg -ToConsole
                if ($eventArgs.Exception.StackTrace) {
                    Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $eventArgs.Exception.StackTrace)
                }
            } catch {}
            try { $eventArgs.Handled = $true } catch {}
            try { Show-UiError -Message $eventArgs.Exception.Message } catch {}
        })
    } catch {}

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
        $txtBuild.Text = "v1.9 (Media Builder)"
    }

    $dashboardPage = Import-XamlFile -RelativePath "UI\Pages\Dashboard.xaml"
    $imagesPage    = Import-XamlFile -RelativePath "UI\Pages\Images.xaml"
    $mediaPage     = Import-XamlFile -RelativePath "UI\Pages\MediaBuilder.xaml"
    $driverPage    = Import-XamlFile -RelativePath "UI\Pages\Driver.xaml"
    $updatesPage   = Import-XamlFile -RelativePath "UI\Pages\Updates.xaml"
    $settingsPage  = Import-XamlFile -RelativePath "UI\Pages\Settings.xaml"
    $applyLocalization = ${function:Apply-LocalizationToRoot}
    $getUiString = ${function:Get-UiString}
    $getLocalizedText = ${function:Get-LocalizedText}
    $refreshLocalization = {
        & $applyLocalization -Root $window

        foreach ($page in @(
            $dashboardPage,
            $imagesPage,
            $mediaPage,
            $driverPage,
            $updatesPage,
            $settingsPage
        )) {
            if ($page) {
                & $applyLocalization -Root $page
            }
        }
    }.GetNewClosure()

    & $refreshLocalization

    $setStatus = {
        param([string]$t)
        $displayText = if ([string]::IsNullOrWhiteSpace($t)) { & $getUiString -Key 'ShellReady' } else { & $getLocalizedText -Text $t }
        if ($txtStatus -and $txtStatus.PSObject.Properties.Match("Text").Count -gt 0) { $txtStatus.Text = $displayText }
    }.GetNewClosure()

    return [pscustomobject]@{
        Window        = $window
        Frame         = $frame
        StartPage     = (Get-ConfigValue -Key 'StartPage' -Default 'Dashboard')
        DashboardPage = $dashboardPage
        ImagesPage    = $imagesPage
        MediaPage     = $mediaPage
        DriverPage    = $driverPage
        UpdatesPage   = $updatesPage
        SettingsPage  = $settingsPage
        SetStatus     = $setStatus

        OnStateChanged = {
            & $refreshLocalization
        }.GetNewClosure()
        ControllerInitialized = @{}

        NavigateDashboard = $null
        NavigateImages    = $null
        NavigateMedia     = $null
        NavigateDriver    = $null
        NavigateUpdates   = $null
        NavigateSettings  = $null
    }
}

function Set-MainWindowWorkAreaLayout {
    param(
        [Parameter(Mandatory)]$Window
    )

    try {
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
        $Window.Left = [double]$workArea.Left
        $Window.Top = [double]$workArea.Top
        $Window.Width = [double]$workArea.Width
        $Window.Height = [double]$workArea.Height
        $Window.WindowState = [System.Windows.WindowState]::Maximized
        Write-Log -Level INFO -Message ("UI: Main window aligned to work area {0}x{1}." -f [int]$workArea.Width, [int]$workArea.Height)
    } catch {
        try { $Window.WindowState = [System.Windows.WindowState]::Maximized } catch {}
    }
}
