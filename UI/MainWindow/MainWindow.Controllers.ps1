Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ControllerInitializer {
    param(
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)]$PageObject,
        [Parameter(Mandatory)][scriptblock]$SetStatus,
        $OnStateChanged = $null
    )

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $cmd) { return }

    $args = @{}

    $pageParam = @(
        'Page',
        'DriverPage',
        'DashboardPage',
        'ImagesPage',
        'MediaBuilderPage',
        'UpdatesPage',
        'SettingsPage'
    ) | Where-Object { $cmd.Parameters.ContainsKey($_) } | Select-Object -First 1

    if (-not $pageParam) {
        throw "Kein passender Page-Parameter für $CommandName gefunden."
    }

    $args[$pageParam] = $PageObject

    if ($cmd.Parameters.ContainsKey('SetStatus')) {
        $args['SetStatus'] = $SetStatus
    }

    if ($cmd.Parameters.ContainsKey('OnStateChanged')) {
        if ($OnStateChanged -is [scriptblock]) {
            $args['OnStateChanged'] = $OnStateChanged
        }
        else {
            $paramMeta = $cmd.Parameters['OnStateChanged']
            $isMandatory = $false

            try {
                foreach ($attr in $paramMeta.Attributes) {
                    if ($attr -is [System.Management.Automation.ParameterAttribute] -and $attr.Mandatory) {
                        $isMandatory = $true
                        break
                    }
                }
            }
            catch {}

            if ($isMandatory) {
                $args['OnStateChanged'] = {}
            }
        }
    }

    & $cmd @args
}

function Ensure-MainWindowControllerInitialized {
    param(
        [Parameter(Mandatory)][object]$Ctx,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)]$PageObject
    )

    if ($null -eq $Ctx.ControllerInitialized) {
        $Ctx.ControllerInitialized = @{}
    }

    if ($Ctx.ControllerInitialized.ContainsKey($Key) -and $Ctx.ControllerInitialized[$Key]) {
        return
    }

    Write-Log -Level INFO -Message ("UI: Initialisiere Controller bei Bedarf: {0}" -f $Key)
    Invoke-ControllerInitializer `
        -CommandName $CommandName `
        -PageObject $PageObject `
        -SetStatus $Ctx.SetStatus `
        -OnStateChanged $Ctx.OnStateChanged

    $Ctx.ControllerInitialized[$Key] = $true
}

function Get-MainWindowPageSpecs {
    return @(
        [pscustomobject]@{ Key = 'Dashboard'; PropertyName = 'DashboardPage'; RelativePath = 'UI\Pages\Dashboard.xaml' },
        [pscustomobject]@{ Key = 'Images'; PropertyName = 'ImagesPage'; RelativePath = 'UI\Pages\Images.xaml' },
        [pscustomobject]@{ Key = 'Media'; PropertyName = 'MediaPage'; RelativePath = 'UI\Pages\MediaBuilder.xaml' },
        [pscustomobject]@{ Key = 'Driver'; PropertyName = 'DriverPage'; RelativePath = 'UI\Pages\Driver.xaml' },
        [pscustomobject]@{ Key = 'Updates'; PropertyName = 'UpdatesPage'; RelativePath = 'UI\Pages\Updates.xaml' },
        [pscustomobject]@{ Key = 'Settings'; PropertyName = 'SettingsPage'; RelativePath = 'UI\Pages\Settings.xaml' }
    )
}

function Ensure-MainWindowPageLoaded {
    param(
        [Parameter(Mandatory)][object]$Ctx,
        [Parameter(Mandatory)][string]$PagePropertyName,
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$ApplyViewState
    )

    $page = $null
    try {
        if ($Ctx.PSObject.Properties.Match($PagePropertyName).Count -gt 0) {
            $page = $Ctx.$PagePropertyName
        }
    } catch {}

    if (-not $page) {
        Write-Log -Level INFO -Message ("UI: Lade Seite bei Bedarf: {0}" -f $RelativePath)
        $page = Import-XamlFile -RelativePath $RelativePath

        try {
            if ($Ctx.PSObject.Properties.Match($PagePropertyName).Count -gt 0) {
                $Ctx.$PagePropertyName = $page
            }
        } catch {}
    }

    if ($ApplyViewState -and $page) {
        try {
            $viewStateAction = $null
            if ($Ctx.PSObject.Properties.Match('ApplyViewState').Count -gt 0) {
                $viewStateAction = $Ctx.ApplyViewState
            }
            if ($viewStateAction -is [scriptblock]) {
                & $viewStateAction -Root $page
            }
        } catch {}
    }

    return $page
}

function Start-MainWindowPageWarmup {
    param(
        [Parameter(Mandatory)][object]$Ctx,
        [int]$InitialDelayMs = 2200,
        [int]$IntervalMs = 900
    )

    try {
        if (-not $Ctx.Window) { return }

        $getPageSpecs = ${function:Get-MainWindowPageSpecs}
        $ensurePage = ${function:Ensure-MainWindowPageLoaded}

        $pending = New-Object System.Collections.Queue
        foreach ($spec in @(& $getPageSpecs)) {
            $page = $null
            try {
                if ($Ctx.PSObject.Properties.Match([string]$spec.PropertyName).Count -gt 0) {
                    $page = $Ctx.($spec.PropertyName)
                }
            } catch {}

            if (-not $page) {
                [void]$pending.Enqueue($spec)
            }
        }

        if ($pending.Count -lt 1) { return }

        $dispatcher = $Ctx.Window.Dispatcher
        $timer = New-Object System.Windows.Threading.DispatcherTimer(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            $dispatcher
        )
        $timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(100, $InitialDelayMs))

        $tick = {
            try {
                if ($pending.Count -lt 1) {
                    $timer.Stop()
                    return
                }

                $timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(100, $IntervalMs))
                $spec = $pending.Dequeue()
                $null = & $ensurePage `
                    -Ctx $Ctx `
                    -PagePropertyName ([string]$spec.PropertyName) `
                    -RelativePath ([string]$spec.RelativePath) `
                    -ApplyViewState

                try { Write-Log -Level INFO -Message ("UI: Seite vorgewärmt: {0}" -f [string]$spec.Key) } catch {}
            } catch {
                try { Write-Log -Level WARN -Message ("UI: Seiten-Warmup fehlgeschlagen: {0}" -f $_.Exception.Message) } catch {}
            }
        }.GetNewClosure()

        $timer.Add_Tick($tick)
        $timer.Start()

        try {
            if ($Ctx.PSObject.Properties.Match('PageWarmupTimer').Count -gt 0) {
                $Ctx.PageWarmupTimer = $timer
            }
        } catch {}

        Write-Log -Level INFO -Message ("UI: Seiten-Warmup geplant: {0} Seite(n)." -f $pending.Count)
    } catch {
        try { Write-Log -Level WARN -Message ("UI: Seiten-Warmup konnte nicht geplant werden: {0}" -f $_.Exception.Message) } catch {}
    }
}

function New-MainWindowNavigateScript {
    param(
        [Parameter(Mandatory)]$Ctx,
        [Parameter(Mandatory)]$Frame,
        [AllowNull()]$Page = $null,
        [string]$PagePropertyName = $null,
        [string]$RelativePath = $null,
        [string]$NavKey = $null,
        [string]$ControllerKey = $null,
        [string]$InitializeCommandName = $null,
        [string]$RefreshCommandName = $null,
        [string]$Label = 'Navigation'
    )

    $refreshCmd = $null
    if (-not [string]::IsNullOrWhiteSpace($RefreshCommandName)) {
        $refreshCmd = Get-Command $RefreshCommandName -ErrorAction SilentlyContinue
    }

    $ensureController = ${function:Ensure-MainWindowControllerInitialized}
    $ensurePage = ${function:Ensure-MainWindowPageLoaded}

    return {
        if (-not $Frame) {
            throw "$Label fehlgeschlagen: Frame nicht gefunden."
        }

        if (-not [string]::IsNullOrWhiteSpace($PagePropertyName) -and -not [string]::IsNullOrWhiteSpace($RelativePath)) {
            $Page = & $ensurePage -Ctx $Ctx -PagePropertyName $PagePropertyName -RelativePath $RelativePath
        }

        if (-not $Page) {
            throw "$Label fehlgeschlagen: Zielseite nicht gefunden."
        }

        $controllerWasInitialized = $false
        try {
            $controllerWasInitialized = (
                -not [string]::IsNullOrWhiteSpace($ControllerKey) -and
                $Ctx.ControllerInitialized -and
                $Ctx.ControllerInitialized.ContainsKey($ControllerKey) -and
                $Ctx.ControllerInitialized[$ControllerKey]
            )
        } catch {
            $controllerWasInitialized = $false
        }

        if (-not [string]::IsNullOrWhiteSpace($ControllerKey) -and -not [string]::IsNullOrWhiteSpace($InitializeCommandName)) {
            & $ensureController `
                -Ctx $Ctx `
                -Key $ControllerKey `
                -CommandName $InitializeCommandName `
                -PageObject $Page
        }

        try {
            [void]$Frame.Navigate($Page)
        }
        catch {
            try {
                $Frame.Content = $Page
            }
            catch {
                throw
            }
        }

        if ($null -ne $refreshCmd -and $controllerWasInitialized) {
            $shouldRefresh = $true
            try {
                if ($null -eq $Ctx.NavigationRefreshAt) {
                    $Ctx.NavigationRefreshAt = @{}
                }

                $refreshKey = if ([string]::IsNullOrWhiteSpace($ControllerKey)) { [string]$Label } else { [string]$ControllerKey }
                $now = Get-Date
                if ($Ctx.NavigationRefreshAt.ContainsKey($refreshKey)) {
                    $last = [datetime]$Ctx.NavigationRefreshAt[$refreshKey]
                    if (($now - $last).TotalMilliseconds -lt 2000) {
                        $shouldRefresh = $false
                    }
                }

                if ($shouldRefresh) {
                    $Ctx.NavigationRefreshAt[$refreshKey] = $now
                }
            } catch {
                $shouldRefresh = $true
            }

            if ($shouldRefresh) {
                & $refreshCmd
            }
        }

        try {
            $viewStateAction = $null
            if ($Ctx.PSObject.Properties.Match('ApplyViewState').Count -gt 0) {
                $viewStateAction = $Ctx.ApplyViewState
            }
            if ($viewStateAction -is [scriptblock]) {
                & $viewStateAction -Root $Page
            }
            else {
                $themeAction = $null
                if ($Ctx.PSObject.Properties.Match('ApplyTheme').Count -gt 0) {
                    $themeAction = $Ctx.ApplyTheme
                }
                if ($themeAction -is [scriptblock]) {
                    & $themeAction -Root $Page
                }
            }
        } catch {}

        if (-not [string]::IsNullOrWhiteSpace($NavKey)) {
            try { Set-MainWindowActiveNav -Ctx $Ctx -Key $NavKey } catch {}
        }
    }.GetNewClosure()
}

function Initialize-MainWindowControllers {
    param(
        [object]$Ctx = $null,

        $DashboardPage = $null,
        $ImagesPage    = $null,
        $MediaPage     = $null,
        $DriverPage    = $null,
        $UpdatesPage   = $null,
        $SettingsPage  = $null,

        [scriptblock]$SetStatus = $null,
        $OnStateChanged = $null
    )

    if ($null -eq $Ctx) {
        $Ctx = [pscustomobject]@{
            Window            = $null
            Frame             = $null
            DashboardPage     = $null
            ImagesPage        = $null
            MediaPage         = $null
            DriverPage        = $null
            UpdatesPage       = $null
            SettingsPage      = $null
            SetStatus         = $null
            ApplyViewState    = $null
            ApplyTheme        = $null
            OnStateChanged    = $null
            NavigateDashboard = $null
            NavigateImages    = $null
            NavigateMedia     = $null
            NavigateDriver    = $null
            NavigateUpdates   = $null
            NavigateSettings  = $null
            ControllerInitialized = @{}
            NavigationRefreshAt = @{}
            PageWarmupTimer = $null
        }
    }

    if ($null -ne $DashboardPage) { $Ctx.DashboardPage  = $DashboardPage }
    if ($null -ne $ImagesPage)    { $Ctx.ImagesPage     = $ImagesPage }
    if ($null -ne $MediaPage)     { $Ctx.MediaPage      = $MediaPage }
    if ($null -ne $DriverPage)    { $Ctx.DriverPage     = $DriverPage }
    if ($null -ne $UpdatesPage)   { $Ctx.UpdatesPage    = $UpdatesPage }
    if ($null -ne $SettingsPage)  { $Ctx.SettingsPage   = $SettingsPage }
    if ($null -ne $SetStatus)     { $Ctx.SetStatus      = $SetStatus }
    if ($null -ne $OnStateChanged){ $Ctx.OnStateChanged = $OnStateChanged }

    if (-not ($Ctx.SetStatus -is [scriptblock])) {
        throw "SetStatus wurde für Initialize-MainWindowControllers nicht gefunden oder ist kein ScriptBlock."
    }

    if ($null -eq $Ctx.ControllerInitialized) {
        $Ctx.ControllerInitialized = @{}
    }

    $Ctx.NavigateDashboard = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.DashboardPage `
        -PagePropertyName 'DashboardPage' `
        -RelativePath 'UI\Pages\Dashboard.xaml' `
        -NavKey 'Dashboard' `
        -ControllerKey 'Dashboard' `
        -InitializeCommandName 'Initialize-DashboardController' `
        -RefreshCommandName 'Refresh-DashboardUI' `
        -Label 'NavigateDashboard'

    $Ctx.NavigateImages = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.ImagesPage `
        -PagePropertyName 'ImagesPage' `
        -RelativePath 'UI\Pages\Images.xaml' `
        -NavKey 'Images' `
        -ControllerKey 'Images' `
        -InitializeCommandName 'Initialize-ImagesController' `
        -RefreshCommandName 'Refresh-ImagesUI' `
        -Label 'NavigateImages'

    $Ctx.NavigateMedia = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.MediaPage `
        -PagePropertyName 'MediaPage' `
        -RelativePath 'UI\Pages\MediaBuilder.xaml' `
        -NavKey 'Media' `
        -ControllerKey 'Media' `
        -InitializeCommandName 'Initialize-MediaBuilderController' `
        -RefreshCommandName 'Refresh-MediaBuilderUI' `
        -Label 'NavigateMedia'

    $Ctx.NavigateDriver = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.DriverPage `
        -PagePropertyName 'DriverPage' `
        -RelativePath 'UI\Pages\Driver.xaml' `
        -NavKey 'Driver' `
        -ControllerKey 'Driver' `
        -InitializeCommandName 'Initialize-DriverController' `
        -RefreshCommandName 'Refresh-DriverUI' `
        -Label 'NavigateDriver'

    $Ctx.NavigateUpdates = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.UpdatesPage `
        -PagePropertyName 'UpdatesPage' `
        -RelativePath 'UI\Pages\Updates.xaml' `
        -NavKey 'Updates' `
        -ControllerKey 'Updates' `
        -InitializeCommandName 'Initialize-UpdatesController' `
        -RefreshCommandName 'Refresh-UpdatesUI' `
        -Label 'NavigateUpdates'

    $Ctx.NavigateSettings = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.SettingsPage `
        -PagePropertyName 'SettingsPage' `
        -RelativePath 'UI\Pages\Settings.xaml' `
        -NavKey 'Settings' `
        -ControllerKey 'Settings' `
        -InitializeCommandName 'Initialize-SettingsController' `
        -RefreshCommandName 'Refresh-SettingsUI' `
        -Label 'NavigateSettings'

    return $Ctx
}
