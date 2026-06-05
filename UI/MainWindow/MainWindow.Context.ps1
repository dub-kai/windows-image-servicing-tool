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
    $shellBusyOverlay = Find-Ui -Root $window -Name "ShellBusyOverlay"
    $txtShellBusyMessage = Find-Ui -Root $window -Name "TxtShellBusyMessage"

    if ($txtBuild -and $txtBuild.PSObject.Properties.Match("Text").Count -gt 0) {
        $txtBuild.Text = "v1.9 (Media Builder)"
    }

    $applyLocalization = ${function:Apply-LocalizationToRoot}
    $applyTheme = ${function:Apply-UiTheme}
    $getUiString = ${function:Get-UiString}
    $getLocalizedText = ${function:Get-LocalizedText}
    $viewStateCache = @{}
    $showShellBusy = {
        param([string]$MessageKey = 'ShellBusyApplying')

        try {
            if ($txtShellBusyMessage) {
                $txtShellBusyMessage.Text = (& $getUiString -Key $MessageKey)
            }
            if ($shellBusyOverlay) {
                $shellBusyOverlay.Visibility = [System.Windows.Visibility]::Visible
            }
            if ($window) {
                $window.Cursor = [System.Windows.Input.Cursors]::Wait
                $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            }
        } catch {}
    }.GetNewClosure()
    $hideShellBusy = {
        try {
            if ($shellBusyOverlay) {
                $shellBusyOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            }
            if ($window) {
                $window.Cursor = $null
                $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
            }
        } catch {}
    }.GetNewClosure()
    $applyViewState = {
        param([AllowNull()]$Root)

        if (-not $Root) { return }
        $rootKey = $null
        try { $rootKey = [string][System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Root) } catch {}

        $stateKey = 'unknown'
        try { $stateKey = ('{0}|{1}' -f (Get-UiLanguage), (Get-UiThemeName)) } catch {}

        if ($rootKey -and $viewStateCache.ContainsKey($rootKey) -and $viewStateCache[$rootKey] -eq $stateKey) {
            return
        }

        & $applyLocalization -Root $Root
        & $applyTheme -Root $Root

        if ($rootKey) {
            $viewStateCache[$rootKey] = $stateKey
        }
    }.GetNewClosure()
    $refreshLocalization = {
        param([bool]$ShowBusy = $false)

        if ($ShowBusy) { & $showShellBusy -MessageKey 'ShellBusyApplying' }
        try {
            & $applyViewState -Root $window

            $currentContent = $null
            try { if ($frame) { $currentContent = $frame.Content } } catch {}
            if ($currentContent) {
                & $applyViewState -Root $currentContent
            }
        } finally {
            if ($ShowBusy) { & $hideShellBusy }
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
        DashboardPage = $null
        ImagesPage    = $null
        MediaPage     = $null
        DriverPage    = $null
        UpdatesPage   = $null
        SettingsPage  = $null
        SetStatus     = $setStatus
        ApplyViewState = $applyViewState
        ApplyTheme    = {
            param([AllowNull()]$Root)

            if ($Root) {
                & $applyTheme -Root $Root
                return
            }

            & $applyTheme -Root $window
            $currentContent = $null
            try { if ($frame) { $currentContent = $frame.Content } } catch {}
            if ($currentContent) { & $applyTheme -Root $currentContent }
        }.GetNewClosure()

        OnStateChanged = {
            & $refreshLocalization -ShowBusy $true
        }.GetNewClosure()
        ControllerInitialized = @{}
        NavigationRefreshAt = @{}
        PageWarmupTimer = $null

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
