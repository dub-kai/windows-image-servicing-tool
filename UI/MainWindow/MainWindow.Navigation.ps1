Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-MainWindowNavigation {
    param(
        [Parameter(Mandatory)][object]$Ctx
    )

    $window = $Ctx.Window
    if (-not $window) { return $Ctx }

    $btnDashboard = $null
    $btnImages    = $null
    $btnMedia     = $null
    $btnDriver    = $null
    $btnUpdates   = $null
    $btnSettings  = $null

    try { $btnDashboard = $window.FindName('BtnNavDashboard') } catch {}
    if (-not $btnDashboard) { try { $btnDashboard = $window.FindName('BtnDashboard') } catch {} }

    try { $btnImages = $window.FindName('BtnNavImages') } catch {}
    if (-not $btnImages) { try { $btnImages = $window.FindName('BtnImages') } catch {} }

    try { $btnMedia = $window.FindName('BtnNavMedia') } catch {}
    if (-not $btnMedia) { try { $btnMedia = $window.FindName('BtnMedia') } catch {} }

    try { $btnDriver = $window.FindName('BtnNavDriver') } catch {}
    if (-not $btnDriver) { try { $btnDriver = $window.FindName('BtnDriver') } catch {} }

    try { $btnUpdates = $window.FindName('BtnNavUpdates') } catch {}
    if (-not $btnUpdates) { try { $btnUpdates = $window.FindName('BtnUpdates') } catch {} }

    try { $btnSettings = $window.FindName('BtnNavSettings') } catch {}
    if (-not $btnSettings) { try { $btnSettings = $window.FindName('BtnSettings') } catch {} }

    $navigateDashboard = $Ctx.NavigateDashboard
    $navigateImages    = $Ctx.NavigateImages
    $navigateMedia     = $Ctx.NavigateMedia
    $navigateDriver    = $Ctx.NavigateDriver
    $navigateUpdates   = $Ctx.NavigateUpdates
    $navigateSettings  = $Ctx.NavigateSettings

    if ($btnDashboard) {
        $btnDashboard.Add_Click({
            try {
                if (-not ($navigateDashboard -is [scriptblock])) {
                    throw "NavigateDashboard ist nicht verfuegbar."
                }
                & $navigateDashboard
            }
            catch {
                try {
                    Write-Log -Level ERROR -Message ("NavigateDashboard FAILED: {0}" -f $_.Exception.Message)
                    if ($_.ScriptStackTrace) {
                        Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $_.ScriptStackTrace)
                    }
                }
                catch {}
                Show-UiError -Message $_.Exception.Message
            }
        }.GetNewClosure())
    }

    if ($btnMedia) {
        $btnMedia.Add_Click({
            try {
                if (-not ($navigateMedia -is [scriptblock])) {
                    throw "NavigateMedia ist nicht verfuegbar."
                }
                & $navigateMedia
            }
            catch {
                try {
                    Write-Log -Level ERROR -Message ("NavigateMedia FAILED: {0}" -f $_.Exception.Message)
                    if ($_.ScriptStackTrace) {
                        Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $_.ScriptStackTrace)
                    }
                }
                catch {}
                Show-UiError -Message $_.Exception.Message
            }
        }.GetNewClosure())
    }

    if ($btnImages) {
        $btnImages.Add_Click({
            try {
                if (-not ($navigateImages -is [scriptblock])) {
                    throw "NavigateImages ist nicht verfuegbar."
                }
                & $navigateImages
            }
            catch {
                try {
                    Write-Log -Level ERROR -Message ("NavigateImages FAILED: {0}" -f $_.Exception.Message)
                    if ($_.ScriptStackTrace) {
                        Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $_.ScriptStackTrace)
                    }
                }
                catch {}
                Show-UiError -Message $_.Exception.Message
            }
        }.GetNewClosure())
    }

    if ($btnDriver) {
        $btnDriver.Add_Click({
            try {
                if (-not ($navigateDriver -is [scriptblock])) {
                    throw "NavigateDriver ist nicht verfuegbar."
                }
                & $navigateDriver
            }
            catch {
                try {
                    Write-Log -Level ERROR -Message ("NavigateDriver FAILED: {0}" -f $_.Exception.Message)
                    if ($_.ScriptStackTrace) {
                        Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $_.ScriptStackTrace)
                    }
                }
                catch {}
                Show-UiError -Message $_.Exception.Message
            }
        }.GetNewClosure())
    }

    if ($btnUpdates) {
        $btnUpdates.Add_Click({
            try {
                if (-not ($navigateUpdates -is [scriptblock])) {
                    throw "NavigateUpdates ist nicht verfuegbar."
                }
                & $navigateUpdates
            }
            catch {
                try {
                    Write-Log -Level ERROR -Message ("NavigateUpdates FAILED: {0}" -f $_.Exception.Message)
                    if ($_.ScriptStackTrace) {
                        Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $_.ScriptStackTrace)
                    }
                }
                catch {}
                Show-UiError -Message $_.Exception.Message
            }
        }.GetNewClosure())
    }

    if ($btnSettings) {
        $btnSettings.Add_Click({
            try {
                if (-not ($navigateSettings -is [scriptblock])) {
                    throw "NavigateSettings ist nicht verfuegbar."
                }
                & $navigateSettings
            }
            catch {
                try {
                    Write-Log -Level ERROR -Message ("NavigateSettings FAILED: {0}" -f $_.Exception.Message)
                    if ($_.ScriptStackTrace) {
                        Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $_.ScriptStackTrace)
                    }
                }
                catch {}
                Show-UiError -Message $_.Exception.Message
            }
        }.GetNewClosure())
    }

    return $Ctx
}

function Invoke-MainWindowInitialNavigation {
    param(
        [Parameter(Mandatory)][object]$Ctx
    )

    $startPage = $null
    try { $startPage = [string]$Ctx.StartPage } catch {}

    if ([string]::IsNullOrWhiteSpace($startPage)) {
        $startPage = 'Dashboard'
    }

    $action = switch ($startPage) {
        'Images'   { $Ctx.NavigateImages }
        'Media'    { $Ctx.NavigateMedia }
        'Driver'   { $Ctx.NavigateDriver }
        'Updates'  { $Ctx.NavigateUpdates }
        'Settings' { $Ctx.NavigateSettings }
        default    { $Ctx.NavigateDashboard }
    }

    try {
        if (-not ($action -is [scriptblock])) {
            throw "Initiale Navigation fuer '$startPage' ist nicht verfuegbar."
        }
        & $action
    }
    catch {
        try {
            Write-Log -Level ERROR -Message ("InitialNavigation FAILED: {0}" -f $_.Exception.Message)
            if ($_.ScriptStackTrace) {
                Write-Log -Level ERROR -Message ("STACK:`n{0}" -f $_.ScriptStackTrace)
            }
        }
        catch {}
        Show-UiError -Message $_.Exception.Message
    }
}
