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

function New-MainWindowNavigateScript {
    param(
        [Parameter(Mandatory)]$Ctx,
        [Parameter(Mandatory)]$Frame,
        [Parameter(Mandatory)]$Page,
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

    return {
        if (-not $Frame) {
            throw "$Label fehlgeschlagen: Frame nicht gefunden."
        }

        if (-not $Page) {
            throw "$Label fehlgeschlagen: Zielseite nicht gefunden."
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

        if ($null -ne $refreshCmd) {
            & $refreshCmd
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
        -ControllerKey 'Dashboard' `
        -InitializeCommandName 'Initialize-DashboardController' `
        -RefreshCommandName 'Refresh-DashboardUI' `
        -Label 'NavigateDashboard'

    $Ctx.NavigateImages = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.ImagesPage `
        -ControllerKey 'Images' `
        -InitializeCommandName 'Initialize-ImagesController' `
        -RefreshCommandName 'Refresh-ImagesUI' `
        -Label 'NavigateImages'

    $Ctx.NavigateMedia = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.MediaPage `
        -ControllerKey 'Media' `
        -InitializeCommandName 'Initialize-MediaBuilderController' `
        -RefreshCommandName 'Refresh-MediaBuilderUI' `
        -Label 'NavigateMedia'

    $Ctx.NavigateDriver = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.DriverPage `
        -ControllerKey 'Driver' `
        -InitializeCommandName 'Initialize-DriverController' `
        -RefreshCommandName 'Refresh-DriverUI' `
        -Label 'NavigateDriver'

    $Ctx.NavigateUpdates = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.UpdatesPage `
        -ControllerKey 'Updates' `
        -InitializeCommandName 'Initialize-UpdatesController' `
        -RefreshCommandName 'Refresh-UpdatesUI' `
        -Label 'NavigateUpdates'

    $Ctx.NavigateSettings = New-MainWindowNavigateScript `
        -Ctx $Ctx `
        -Frame $Ctx.Frame `
        -Page $Ctx.SettingsPage `
        -ControllerKey 'Settings' `
        -InitializeCommandName 'Initialize-SettingsController' `
        -RefreshCommandName 'Refresh-SettingsUI' `
        -Label 'NavigateSettings'

    return $Ctx
}
