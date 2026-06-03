function New-WorkerScript {
    param([Parameter(Mandatory)][string]$Code)
    return [scriptblock]::Create($Code)
}

function Get-DisplayValue {
    param([object]$Value)
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return "-" }
    return $s
}

function ConvertTo-InboxBool {
    param([string]$InboxText)

    $x = ([string]$InboxText).Trim().ToLowerInvariant()
    if ($x -in @('yes','true','ja','1'))  { return $true }
    if ($x -in @('no','false','nein','0')) { return $false }
    return $null
}

function Get-ImageServicingBusy {
    try {
        return [bool](Get-AppStateValue -Key "IsImageServicingBusy" -Default $false)
    } catch {
        return $false
    }
}

function Test-DriverMountUsable {
    param([string]$MountDir)

    if ([string]::IsNullOrWhiteSpace($MountDir)) { return $false }

    try {
        return (Test-Path -LiteralPath $MountDir -PathType Container)
    } catch {
        return $false
    }
}

function Assert-DriverMountUsable {
    param([Parameter(Mandatory)][string]$MountDir)

    if (-not (Test-DriverMountUsable -MountDir $MountDir)) {
        throw ("MountDir nicht gefunden oder ungültig: {0}" -f $MountDir)
    }

    $windowsDir = Join-Path -Path $MountDir -ChildPath 'Windows'
    if (-not (Test-Path -LiteralPath $windowsDir -PathType Container)) {
        throw ("Ungültiges MountDir, 'Windows' fehlt: {0}" -f $MountDir)
    }
}

function Test-DriverTransientDismError {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    $m = [string]$Message

    if ($m -match '(?i)An error occurred closing a servicing component in the image') { return $true }
    if ($m -match '(?i)Wait a few minutes and try running the command again') { return $true }
    if ($m -match '(?i)The system cannot find the path specified') { return $true }
    if ($m -match '(?i)cannot find the file specified') { return $true }
    if ($m -match '(?i)No driver packages were found on the specified path') { return $true }
    if ($m -match '(?i)problem opening the INF file') { return $true }
    if ($m -match '(?i)Unable to access the image') { return $true }

    return $false
}

function Write-DriverMountLog {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [string]$MountDir
    )

    try {
        Write-Log -Level INFO -Message ("Driver:{0} using MountDir={1}" -f $Operation, $MountDir)
    } catch {}
}

function Resolve-DriverMountDir {
    param(
        $Context = $null
    )

    $ctxLocal = if ($null -ne $Context) { $Context } else { $script:ctx }
    if (-not $ctxLocal) { return $null }

    $cmb = $ctxLocal["CmbDriverMount"]
    if (-not $cmb) { return $null }

    $selected = $null
    try { $selected = [string]$cmb.SelectedItem } catch { $selected = $null }

    if (-not [string]::IsNullOrWhiteSpace($selected)) {
        return $selected
    }

    $wanted = $null
    try { $wanted = Get-AppStateValue -Key "DriverMountDir" -Default $null } catch { $wanted = $null }

    if (-not [string]::IsNullOrWhiteSpace($wanted)) {
        try {
            $items = @($cmb.ItemsSource)
            if ($items -contains $wanted) {
                return $wanted
            }
        } catch {}
    }

    try {
        $items = @($cmb.ItemsSource)
        if ($items.Count -gt 0) {
            return [string]$items[0]
        }
    } catch {}

    return $null
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
                $msg.Text = if ($Reason) { $Reason } else { Get-UiString -Key 'DriverBusyDefault' }
            } else {
                $msg.Text = Get-UiString -Key 'DriverBusyDefault'
            }
        } catch {}
    }

    try {
        $page = Get-Ctx "DriverPage"
        if ($Busy) {
            Start-UiBusyProgress -Root $page -Context $ctxLocal -Message $(if ($Reason) { $Reason } else { Get-UiString -Key 'DriverBusyDefault' }) -Detail (Get-UiString -Key 'DriverBusyDetail') -ShowDismTail
        } else {
            Stop-UiBusyProgress -Root $page -Context $ctxLocal
        }
    } catch {}

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
            try {
                $fnReload = (Get-Item function:Request-DriversReload -ErrorAction Stop).ScriptBlock
                & $fnReload -Reason "Pending reload after busy"
            } catch {}
        }
    }
}
