function Invoke-StateChangedSafe {
    try {
        if ($script:ctx -and $script:ctx.OnStateChanged) { & $script:ctx.OnStateChanged }
    } catch {
        try {
            Write-Log -Level ERROR -Message ("OnStateChanged FAILED: {0}`nSTACK:`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) -ToConsole
        } catch {}
        Show-UiError -Message $_.Exception.Message
    }
}

function Invoke-SetStatusSafe {
    param([string]$Text)
    try {
        if ($script:ctx -and $script:ctx.SetStatus) { & $script:ctx.SetStatus $Text }
    } catch {}
}

function Invoke-DashboardMainNavigation {
    param(
        [Parameter(Mandatory)][string]$ButtonName
    )

    if (-not $script:ctx -or -not $script:ctx.DashboardPage) {
        throw "Dashboard-Kontext ist nicht verfügbar."
    }

    $window = $null
    try { $window = [System.Windows.Window]::GetWindow($script:ctx.DashboardPage) } catch {}
    if (-not $window) {
        throw "Hauptfenster wurde nicht gefunden."
    }

    $button = $null
    try { $button = $window.FindName($ButtonName) } catch {}
    if (-not $button) {
        throw ("Navigationsbutton nicht gefunden: {0}" -f $ButtonName)
    }

    $args = New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
    $button.RaiseEvent($args)
}
