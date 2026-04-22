function Initialize-DriverController {
    param(
        [Parameter(Mandatory)] $DriverPage,
        [Parameter(Mandatory)] [scriptblock] $SetStatus,
        [Parameter()] [scriptblock] $OnStateChanged = $null
    )

    $script:ctx = @{
        DriverPage     = $DriverPage
        SetStatus      = $SetStatus
        OnStateChanged = $OnStateChanged

        BusyOverlay    = $null
        TxtBusyMessage = $null

        CmbDriverMount         = $null
        BtnDriverRefreshMounts = $null
        BtnDriverLoadDrivers   = $null

        BtnDriverAddDrivers      = $null
        BtnDriverRemoveSelected  = $null

        ChkDriverAll           = $null
        ChkDriverRecurse       = $null
        ChkDriverForceUnsigned = $null

        TxtDriverCount     = $null
        TxtDriverMountUsed = $null
        TxtDriverSelected  = $null

        LstDrivers = $null
    }

    $p = $DriverPage

    $script:ctx["BusyOverlay"]     = Find-Ui -Root $p -Name "BusyOverlay"
    $script:ctx["TxtBusyMessage"]  = Find-Ui -Root $p -Name "TxtBusyMessage"

    $script:ctx["CmbDriverMount"]          = Find-Ui -Root $p -Name "CmbDriverMount"
    $script:ctx["BtnDriverRefreshMounts"]  = Find-Ui -Root $p -Name "BtnDriverRefreshMounts"
    $script:ctx["BtnDriverLoadDrivers"]    = Find-Ui -Root $p -Name "BtnDriverLoadDrivers"

    $script:ctx["BtnDriverAddDrivers"]     = Find-Ui -Root $p -Name "BtnDriverAddDrivers"
    $script:ctx["BtnDriverRemoveSelected"] = Find-Ui -Root $p -Name "BtnDriverRemoveSelected"

    $script:ctx["ChkDriverAll"]            = Find-Ui -Root $p -Name "ChkDriverAll"
    $script:ctx["ChkDriverRecurse"]        = Find-Ui -Root $p -Name "ChkDriverRecurse"
    $script:ctx["ChkDriverForceUnsigned"]  = Find-Ui -Root $p -Name "ChkDriverForceUnsigned"

    $script:ctx["TxtDriverCount"]     = Find-Ui -Root $p -Name "TxtDriverCount"
    $script:ctx["TxtDriverMountUsed"] = Find-Ui -Root $p -Name "TxtDriverMountUsed"
    $script:ctx["TxtDriverSelected"]  = Find-Ui -Root $p -Name "TxtDriverSelected"

    $script:ctx["LstDrivers"] = Find-Ui -Root $p -Name "LstDrivers"

    if ($script:ctx["BtnDriverRefreshMounts"]) {
        $script:ctx["BtnDriverRefreshMounts"].Add_Click({
            Refresh-DriverMountedList
        })
    }

    if ($script:ctx["BtnDriverLoadDrivers"]) {
        $script:ctx["BtnDriverLoadDrivers"].Add_Click({
            Request-DriversReload -Reason "Manual load" -Force
        })
    }

    if ($script:ctx["BtnDriverAddDrivers"]) {
        $script:ctx["BtnDriverAddDrivers"].Add_Click({
            Add-DriversFromFolderAsync
        })
    }

    if ($script:ctx["BtnDriverRemoveSelected"]) {
        $script:ctx["BtnDriverRemoveSelected"].Add_Click({
            Remove-SelectedDriverAsync
        })
    }

    foreach ($k in @("ChkDriverAll","ChkDriverRecurse","ChkDriverForceUnsigned")) {
        $cb = $script:ctx[$k]
        if ($cb) {
            $cb.Add_Checked({
                try {
                    Request-DriversReload -Reason "Option changed"
                } catch {}
            })
            $cb.Add_Unchecked({
                try {
                    Request-DriversReload -Reason "Option changed"
                } catch {}
            })
        }
    }

    if ($script:ctx["CmbDriverMount"]) {
        $script:ctx["CmbDriverMount"].Add_SelectionChanged({
            try {
                $sel = Resolve-DriverMountDir
                try { Set-AppStateValue -Key "DriverMountDir" -Value $sel } catch {}

                if ($script:suppressMountSelectionReload) { return }

                Request-DriversReload -Reason "Mount changed"
            } catch {}
        })
    }

    if ($script:ctx["LstDrivers"]) {
        $script:ctx["LstDrivers"].Add_SelectionChanged({
            try { Refresh-DriverUI } catch {}
        })
    }

    Refresh-DriverUI
    Refresh-DriverMountedList
}
