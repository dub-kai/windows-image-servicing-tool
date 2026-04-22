Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Variable -Name isBusy -Scope Script -ErrorAction SilentlyContinue)) {
    Set-Variable -Name isBusy -Scope Script -Value $false -Force
}

function Get-ImagesCtxValue {
    param(
        [Parameter(Mandatory)]$Obj,
        [Parameter(Mandatory)][string]$Key
    )

    try {
        if ($Obj -is [System.Collections.IDictionary]) {
            return $Obj[$Key]
        }

        $prop = $Obj.PSObject.Properties[$Key]
        if ($prop) { return $prop.Value }
    } catch {}

    return $null
}

function Set-ImagesCtxValue {
    param(
        [Parameter(Mandatory)]$Obj,
        [Parameter(Mandatory)][string]$Key,
        $Value
    )

    try {
        if ($Obj -is [System.Collections.IDictionary]) {
            $Obj[$Key] = $Value
            return
        }

        $prop = $Obj.PSObject.Properties[$Key]
        if ($prop) { $prop.Value = $Value }
    } catch {}
}

function Ensure-ImagesBusyOverlay {
    param(
        [Parameter(Mandatory)]$Context
    )

    $page = Get-ImagesCtxValue -Obj $Context -Key "ImagesPage"
    if (-not $page) { return }

    $overlay = Get-ImagesCtxValue -Obj $Context -Key "BusyOverlay"
    $txt     = Get-ImagesCtxValue -Obj $Context -Key "TxtBusyMessage"

    if (-not $overlay) {
        try { $overlay = $page.FindName("BusyOverlay") } catch {}
        if ($overlay) { Set-ImagesCtxValue -Obj $Context -Key "BusyOverlay" -Value $overlay }
    }

    if (-not $txt) {
        try { $txt = $page.FindName("TxtBusyMessage") } catch {}
        if ($txt) { Set-ImagesCtxValue -Obj $Context -Key "TxtBusyMessage" -Value $txt }
    }
}

function Apply-ImagesBusyUi {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][bool]$Busy,
        [string]$Reason = $null
    )

    Ensure-ImagesBusyOverlay -Context $Context

    function Get-Ctx {
        param([Parameter(Mandatory)][string]$Key)
        return Get-ImagesCtxValue -Obj $Context -Key $Key
    }

    $targets = @(
        (Get-Ctx "CmbView"),
        (Get-Ctx "BtnLoad"),
        (Get-Ctx "BtnPickStandalone"),
        (Get-Ctx "BtnClearStandalone"),
        (Get-Ctx "BtnMountSelected"),
        (Get-Ctx "BtnSaveSourceWim"),
        (Get-Ctx "BtnExportSelectedIndex"),
        (Get-Ctx "LstWimImages"),
        (Get-Ctx "BtnRefreshMounted"),
        (Get-Ctx "BtnUnmountMountedCommit"),
        (Get-Ctx "BtnUnmountMountedDiscard"),
        (Get-Ctx "LstMountedWims")
    ) | Where-Object { $_ -ne $null }

    foreach ($ctrl in $targets) {
        try {
            if ($ctrl.PSObject.Properties.Match("IsEnabled").Count -gt 0) {
                $ctrl.IsEnabled = (-not $Busy)
            }
        } catch {}
    }

    $overlay = Get-Ctx "BusyOverlay"
    if ($overlay) {
        try {
            $overlay.Visibility = if ($Busy) {
                [System.Windows.Visibility]::Visible
            } else {
                [System.Windows.Visibility]::Collapsed
            }
        } catch {}
    }

    $txt = Get-Ctx "TxtBusyMessage"
    if ($txt) {
        try {
            if ($Busy) {
                $txt.Text = if ($Reason) { $Reason } else { "Bitte warten..." }
            } else {
                $txt.Text = "Bitte warten..."
            }
        } catch {}
    }

    try {
        $page = Get-Ctx "ImagesPage"
        if ($page) {
            $win = [System.Windows.Window]::GetWindow($page)
            if ($win) {
                $win.Cursor = if ($Busy) {
                    [System.Windows.Input.Cursors]::Wait
                } else {
                    $null
                }
            }
        }
    } catch {}

    $setStatus = Get-Ctx "SetStatus"
    if ($Busy -and $Reason -and $setStatus) {
        try { & $setStatus $Reason } catch {}
    }

    if ($Busy) {
        try {
            if ($overlay) { $overlay.UpdateLayout() }
        } catch {}

        try {
            $page = Get-Ctx "ImagesPage"
            if ($page) { $page.UpdateLayout() }
        } catch {}

        try {
            $page = Get-Ctx "ImagesPage"
            if ($page -and $page.Dispatcher) {
                $page.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            }
        } catch {}
    }
}

function Set-ImagesBusy {
    param(
        [Parameter(Mandatory)][bool]$Busy,
        [string]$Reason = $null,
        $Context = $null
    )

    $script:isBusy = $Busy

    $ctx = if ($null -ne $Context) { $Context } else { $script:ctx }
    if (-not $ctx) { return }

    $fnApply = ${function:Apply-ImagesBusyUi}

    try {
        if (Get-Command Invoke-Ui -ErrorAction SilentlyContinue) {
            Invoke-Ui -Action { & $fnApply -Context $ctx -Busy $Busy -Reason $Reason } -Priority ([System.Windows.Threading.DispatcherPriority]::Render)
        } else {
            & $fnApply -Context $ctx -Busy $Busy -Reason $Reason
        }
    } catch {
        try {
            & $fnApply -Context $ctx -Busy $Busy -Reason $Reason
        } catch {}
    }
}