function New-DriverContext {
    param(
        [Parameter(Mandatory)] $DriverPage,
        [Parameter(Mandatory)] [scriptblock] $SetStatus,
        [Parameter()] [scriptblock] $OnStateChanged = $null
    )

    $ctx = @{
        DriverPage     = $DriverPage
        SetStatus      = $SetStatus
        OnStateChanged = $OnStateChanged

        BusyOverlay    = $null
        TxtBusyMessage = $null

        CmbDriverMount         = $null
        BtnDriverRefreshMounts = $null

        BtnDriverAddDrivers     = $null
        BtnDriverRemoveSelected = $null
        BtnDriverExportCsv      = $null

        ChkDriverAll           = $null
        ChkDriverRecurse       = $null
        ChkDriverForceUnsigned = $null

        TxtDriverCount     = $null
        TxtDriverMountUsed = $null
        TxtDriverSelected  = $null

        LstDrivers = $null
    }

    $p = $DriverPage

    $ctx["BusyOverlay"]    = Find-Ui -Root $p -Name "BusyOverlay"
    $ctx["TxtBusyMessage"] = Find-Ui -Root $p -Name "TxtBusyMessage"

    $ctx["CmbDriverMount"]         = Find-Ui -Root $p -Name "CmbDriverMount"
    $ctx["BtnDriverRefreshMounts"] = Find-Ui -Root $p -Name "BtnDriverRefreshMounts"

    $ctx["BtnDriverAddDrivers"]     = Find-Ui -Root $p -Name "BtnDriverAddDrivers"
    $ctx["BtnDriverRemoveSelected"] = Find-Ui -Root $p -Name "BtnDriverRemoveSelected"
    $ctx["BtnDriverExportCsv"]      = Find-Ui -Root $p -Name "BtnDriverExportCsv"

    $ctx["ChkDriverAll"]           = Find-Ui -Root $p -Name "ChkDriverAll"
    $ctx["ChkDriverRecurse"]       = Find-Ui -Root $p -Name "ChkDriverRecurse"
    $ctx["ChkDriverForceUnsigned"] = Find-Ui -Root $p -Name "ChkDriverForceUnsigned"

    if ($ctx["ChkDriverAll"]) {
        try {
            $ctx["ChkDriverAll"].IsChecked = [bool](Get-ConfigValue -Key "DriverLoadAllDefault" -Default $false)
        } catch {}
    }

    $ctx["TxtDriverCount"]     = Find-Ui -Root $p -Name "TxtDriverCount"
    $ctx["TxtDriverMountUsed"] = Find-Ui -Root $p -Name "TxtDriverMountUsed"
    $ctx["TxtDriverSelected"]  = Find-Ui -Root $p -Name "TxtDriverSelected"

    $ctx["LstDrivers"] = Find-Ui -Root $p -Name "LstDrivers"

    return $ctx
}

function Assert-DriverContext {
    param(
        [Parameter(Mandatory)] $Context
    )

    if (-not $Context["CmbDriverMount"])         { throw "CmbDriverMount nicht gefunden." }
    if (-not $Context["BtnDriverRefreshMounts"]) { throw "BtnDriverRefreshMounts nicht gefunden." }
    if (-not $Context["BtnDriverAddDrivers"])    { throw "BtnDriverAddDrivers nicht gefunden." }
    if (-not $Context["BtnDriverRemoveSelected"]) { throw "BtnDriverRemoveSelected nicht gefunden." }
    if (-not $Context["BtnDriverExportCsv"])     { throw "BtnDriverExportCsv nicht gefunden." }
    if (-not $Context["LstDrivers"])             { throw "LstDrivers nicht gefunden." }
}

function Write-DriverUiWiresLog {
    param(
        [Parameter(Mandatory)] $Context
    )

    try {
        Write-Log -Level INFO -Message (
            "Driver UI wires: CmbDriverMount={0} BtnRefreshMounts={1} BtnAddDrivers={2} BtnRemoveSelected={3} BtnExportCsv={4} LstDrivers={5}" -f
            [bool]($Context["CmbDriverMount"]),
            [bool]($Context["BtnDriverRefreshMounts"]),
            [bool]($Context["BtnDriverAddDrivers"]),
            [bool]($Context["BtnDriverRemoveSelected"]),
            [bool]($Context["BtnDriverExportCsv"]),
            [bool]($Context["LstDrivers"])
        )
    } catch {}
}
