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

function New-MainWindowNavigateScript {
    param(
        [Parameter(Mandatory)]$Frame,
        [Parameter(Mandatory)]$Page,
        [string]$RefreshCommandName = $null,
        [string]$Label = 'Navigation'
    )

    $refreshCmd = $null
    if (-not [string]::IsNullOrWhiteSpace($RefreshCommandName)) {
        $refreshCmd = Get-Command $RefreshCommandName -ErrorAction SilentlyContinue
    }

    return {
        if (-not $Frame) {
            throw "$Label fehlgeschlagen: Frame nicht gefunden."
        }

        if (-not $Page) {
            throw "$Label fehlgeschlagen: Zielseite nicht gefunden."
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
    }.GetNewClosure()
}

function Initialize-MainWindowControllers {
    param(
        [object]$Ctx = $null,

        $DashboardPage = $null,
        $ImagesPage    = $null,
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
            DriverPage        = $null
            UpdatesPage       = $null
            SettingsPage      = $null
            SetStatus         = $null
            OnStateChanged    = $null
            NavigateDashboard = $null
            NavigateImages    = $null
            NavigateDriver    = $null
            NavigateUpdates   = $null
            NavigateSettings  = $null
        }
    }

    if ($null -ne $DashboardPage) { $Ctx.DashboardPage  = $DashboardPage }
    if ($null -ne $ImagesPage)    { $Ctx.ImagesPage     = $ImagesPage }
    if ($null -ne $DriverPage)    { $Ctx.DriverPage     = $DriverPage }
    if ($null -ne $UpdatesPage)   { $Ctx.UpdatesPage    = $UpdatesPage }
    if ($null -ne $SettingsPage)  { $Ctx.SettingsPage   = $SettingsPage }
    if ($null -ne $SetStatus)     { $Ctx.SetStatus      = $SetStatus }
    if ($null -ne $OnStateChanged){ $Ctx.OnStateChanged = $OnStateChanged }

    if (-not ($Ctx.SetStatus -is [scriptblock])) {
        throw "SetStatus wurde für Initialize-MainWindowControllers nicht gefunden oder ist kein ScriptBlock."
    }

    if ($Ctx.DashboardPage) {
        Invoke-ControllerInitializer `
            -CommandName 'Initialize-DashboardController' `
            -PageObject $Ctx.DashboardPage `
            -SetStatus $Ctx.SetStatus `
            -OnStateChanged $Ctx.OnStateChanged
    }

    if ($Ctx.ImagesPage) {
        Invoke-ControllerInitializer `
            -CommandName 'Initialize-ImagesController' `
            -PageObject $Ctx.ImagesPage `
            -SetStatus $Ctx.SetStatus `
            -OnStateChanged $Ctx.OnStateChanged
    }

    if ($Ctx.DriverPage) {
        Invoke-ControllerInitializer `
            -CommandName 'Initialize-DriverController' `
            -PageObject $Ctx.DriverPage `
            -SetStatus $Ctx.SetStatus `
            -OnStateChanged $Ctx.OnStateChanged
    }

    if ($Ctx.UpdatesPage) {
        Invoke-ControllerInitializer `
            -CommandName 'Initialize-UpdatesController' `
            -PageObject $Ctx.UpdatesPage `
            -SetStatus $Ctx.SetStatus `
            -OnStateChanged $Ctx.OnStateChanged
    }

    if ($Ctx.SettingsPage) {
        Invoke-ControllerInitializer `
            -CommandName 'Initialize-SettingsController' `
            -PageObject $Ctx.SettingsPage `
            -SetStatus $Ctx.SetStatus `
            -OnStateChanged $Ctx.OnStateChanged
    }

    $Ctx.NavigateDashboard = New-MainWindowNavigateScript `
        -Frame $Ctx.Frame `
        -Page $Ctx.DashboardPage `
        -RefreshCommandName 'Refresh-DashboardUI' `
        -Label 'NavigateDashboard'

    $Ctx.NavigateImages = New-MainWindowNavigateScript `
        -Frame $Ctx.Frame `
        -Page $Ctx.ImagesPage `
        -RefreshCommandName 'Refresh-ImagesUI' `
        -Label 'NavigateImages'

    $Ctx.NavigateDriver = New-MainWindowNavigateScript `
        -Frame $Ctx.Frame `
        -Page $Ctx.DriverPage `
        -RefreshCommandName 'Refresh-DriverUI' `
        -Label 'NavigateDriver'

    $Ctx.NavigateUpdates = New-MainWindowNavigateScript `
        -Frame $Ctx.Frame `
        -Page $Ctx.UpdatesPage `
        -RefreshCommandName 'Refresh-UpdatesUI' `
        -Label 'NavigateUpdates'

    $Ctx.NavigateSettings = New-MainWindowNavigateScript `
        -Frame $Ctx.Frame `
        -Page $Ctx.SettingsPage `
        -RefreshCommandName 'Refresh-SettingsUI' `
        -Label 'NavigateSettings'

    return $Ctx
}