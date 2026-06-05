function Start-MainWindow {
    [CmdletBinding()]
    param(
        [object]$SplashWindow
    )

    Write-Log -Level INFO -Message "UI: Start-MainWindow()" -ToConsole

    $ctx = New-MainWindowContext
    $ctx = Initialize-MainWindowControllers -Ctx $ctx
    $ctx = Initialize-MainWindowNavigation  -Ctx $ctx

    Invoke-MainWindowInitialNavigation -Ctx $ctx

    try {
        if ($SplashWindow -and $SplashWindow.IsVisible) {
            $SplashWindow.Close()
        }
    } catch {}

    try { Start-MainWindowPageWarmup -Ctx $ctx } catch {}

    Write-Log -Level INFO -Message "UI: Window.ShowDialog()" -ToConsole
    $null = $ctx.Window.ShowDialog()
    Write-Log -Level INFO -Message "UI: Window closed" -ToConsole
}
