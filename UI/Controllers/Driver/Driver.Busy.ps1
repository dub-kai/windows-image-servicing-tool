function Get-ImageServicingBusy {
    try {
        return [bool](Get-AppStateValue -Key "IsImageServicingBusy" -Default $false)
    } catch {
        return $false
    }
}

function Set-DriverBusy {
    param(
        [Parameter(Mandatory)][bool]$Busy,
        [string]$Reason = $null,
        $Context = $null
    )

    $script:isBusy = $Busy
    $ctxLocal = if ($null -ne $Context) { $Context } else { $script:ctx }
    if (-not $ctxLocal) { return }

    function Get-Ctx([string]$Key) {
        try { return $ctxLocal[$Key] } catch { return $null }
    }

    $targets = @(
        (Get-Ctx "CmbDriverMount"),
        (Get-Ctx "BtnDriverRefreshMounts"),
        (Get-Ctx "BtnDriverLoadDrivers"),
        (Get-Ctx "BtnDriverAddDrivers"),
        (Get-Ctx "BtnDriverRemoveSelected"),
        (Get-Ctx "ChkDriverAll"),
        (Get-Ctx "ChkDriverRecurse"),
        (Get-Ctx "ChkDriverForceUnsigned"),
        (Get-Ctx "LstDrivers")
    ) | Where-Object { $_ -ne $null }

    foreach ($c in $targets) {
        try {
            if ($c.PSObject.Properties.Match("IsEnabled").Count -gt 0) {
                $c.IsEnabled = (-not $Busy)
            }
        } catch {}
    }

    $overlay = Get-Ctx "BusyOverlay"
    if ($overlay) {
        try {
            $overlay.Visibility = if ($Busy) { "Visible" } else { "Collapsed" }
        } catch {}
    }

    $msg = Get-Ctx "TxtBusyMessage"
    if ($msg) {
        try {
            if ($Busy) {
                $msg.Text = if ($Reason) { $Reason } else { "Bitte warten..." }
            } else {
                $msg.Text = "Bitte warten..."
            }
        } catch {}
    }

    try {
        $page = Get-Ctx "DriverPage"
        if ($page) {
            $win = [System.Windows.Window]::GetWindow($page)
            if ($win) {
                $win.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { $null }
            }
        }
    } catch {}

    $setStatus = Get-Ctx "SetStatus"
    if ($Busy -and $Reason -and $setStatus) {
        try { & $setStatus $Reason } catch {}
    }

    if (-not $Busy) {
        if ($script:reloadPending -and -not (Get-ImageServicingBusy)) {
            $script:reloadPending = $false
            try { Load-DriversAsync } catch {}
        }
    }
}