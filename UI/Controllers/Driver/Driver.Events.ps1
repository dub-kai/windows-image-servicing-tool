function Invoke-DriverPageActivated {
    param(
        [Parameter(Mandatory)] $Context,
        [string] $Reason = $null
    )

    try {
        $page = $Context["DriverPage"]
        if (-not $page) { return }

        if (-not [bool]$page.IsVisible) {
            try {
                Write-Log -Level INFO -Message ("Driver: Activation skipped (nicht sichtbar){0}" -f $(if ($Reason) { " | Reason=$Reason" } else { "" }))
            } catch {}
            return
        }

        if (Get-ImageServicingBusy) {
            $script:reloadPending = $true
            try {
                Write-Log -Level INFO -Message ("Driver: Activation deferred (Image servicing busy){0}" -f $(if ($Reason) { " | Reason=$Reason" } else { "" }))
            } catch {}
            return
        }

        try {
            Write-Log -Level INFO -Message ("Driver: Activation refresh{0}" -f $(if ($Reason) { " | Reason=$Reason" } else { "" }))
        } catch {}

        Refresh-DriverMountedList
    }
    catch {}
}

function Register-DriverEventHandlers {
    param(
        [Parameter(Mandatory)] $Context
    )

    $copyDriverField = {
        param([string]$FieldName)

        try {
            $item = $script:ctx["LstDrivers"].SelectedItem
            if (-not $item) { return }

            $value = $null
            if ($item.PSObject.Properties.Match($FieldName).Count -gt 0) {
                $value = [string]$item.$FieldName
            }

            if ([string]::IsNullOrWhiteSpace($value)) { return }

            [System.Windows.Clipboard]::SetText($value)

            $setStatus = $script:ctx["SetStatus"]
            if ($setStatus) {
                try { & $setStatus ("Driver: {0} kopiert: {1}" -f $FieldName, $value) } catch {}
            }
        } catch {}
    }

    if ($Context["BtnDriverRefreshMounts"]) {
        $Context["BtnDriverRefreshMounts"].Add_Click({
            Refresh-DriverMountedList
        })
    }

    if ($Context["BtnDriverAddDrivers"]) {
        $Context["BtnDriverAddDrivers"].Add_Click({
            Add-DriversFromFolderAsync
        })
    }

    if ($Context["BtnDriverRemoveSelected"]) {
        $Context["BtnDriverRemoveSelected"].Add_Click({
            Remove-SelectedDriverAsync
        })
    }

    if ($Context["BtnDriverExportCsv"]) {
        $Context["BtnDriverExportCsv"].Add_Click({
            Export-DriversCsv
        })
    }

    foreach ($k in @("ChkDriverAll", "ChkDriverRecurse", "ChkDriverForceUnsigned")) {
        $cb = $Context[$k]
        if ($cb) {
            $cb.Add_Checked({
                try {
                    if ($script:ctx -and $script:ctx["ChkDriverAll"]) {
                        Set-ConfigValue -Key "DriverLoadAllDefault" -Value ([bool]$script:ctx["ChkDriverAll"].IsChecked) -Persist | Out-Null
                    }
                    if (-not (Get-ImageServicingBusy)) {
                        Load-DriversAsync
                    } else {
                        $script:reloadPending = $true
                    }
                } catch {}
            })

            $cb.Add_Unchecked({
                try {
                    if ($script:ctx -and $script:ctx["ChkDriverAll"]) {
                        Set-ConfigValue -Key "DriverLoadAllDefault" -Value ([bool]$script:ctx["ChkDriverAll"].IsChecked) -Persist | Out-Null
                    }
                    if (-not (Get-ImageServicingBusy)) {
                        Load-DriversAsync
                    } else {
                        $script:reloadPending = $true
                    }
                } catch {}
            })
        }
    }

    if ($Context["CmbDriverMount"]) {
        $Context["CmbDriverMount"].Add_SelectionChanged({
            try {
                $sel = Resolve-DriverMountDir
                try { Set-AppStateValue -Key "DriverMountDir" -Value $sel } catch {}

                if ($script:suppressMountSelectionReload) { return }

                if (Get-ImageServicingBusy) {
                    $script:reloadPending = $true
                    return
                }

                if (Test-DriverMountUsable -MountDir $sel) {
                    Load-DriversAsync
                } else {
                    Clear-DriversList -Context $script:ctx -StatusText (Get-UiString -Key 'DriverCountZero')
                }
            } catch {}
        })
    }

    if ($Context["LstDrivers"]) {
        $Context["LstDrivers"].Add_SelectionChanged({
            try {
                Refresh-DriverUI
            } catch {}
        })
    }

    if ($Context["MiDriverRefreshMounts"]) {
        $Context["MiDriverRefreshMounts"].Add_Click({
            Refresh-DriverMountedList
        })
    }

    if ($Context["MiDriverAddDrivers"]) {
        $Context["MiDriverAddDrivers"].Add_Click({
            Add-DriversFromFolderAsync
        })
    }

    if ($Context["MiDriverRemoveSelected"]) {
        $Context["MiDriverRemoveSelected"].Add_Click({
            Remove-SelectedDriverAsync
        })
    }

    if ($Context["MiDriverReloadDrivers"]) {
        $Context["MiDriverReloadDrivers"].Add_Click({
            Request-DriversReload -Reason "ContextMenu"
        })
    }

    if ($Context["MiDriverExportCsv"]) {
        $Context["MiDriverExportCsv"].Add_Click({
            Export-DriversCsv
        })
    }

    if ($Context["MiDriverCopyPublishedName"]) {
        $Context["MiDriverCopyPublishedName"].Add_Click({
            & $copyDriverField "PublishedName"
        })
    }

    if ($Context["MiDriverCopyOriginalFileName"]) {
        $Context["MiDriverCopyOriginalFileName"].Add_Click({
            & $copyDriverField "OriginalFileName"
        })
    }

    if ($Context["DriverPage"]) {
        $Context["DriverPage"].Add_Loaded({
            param($sender, $args)
            try {
                Invoke-DriverPageActivated -Context $script:ctx -Reason "Loaded"
            } catch {}
        })

        $Context["DriverPage"].Add_IsVisibleChanged({
            param($sender, $args)

            try {
                if (-not $sender.IsVisible) { return }
                Invoke-DriverPageActivated -Context $script:ctx -Reason "IsVisibleChanged"
            } catch {}
        })
    }
}

function Initialize-DriverController {
    param(
        [Parameter(Mandatory)] $DriverPage,
        [Parameter(Mandatory)] [scriptblock] $SetStatus,
        [Parameter()] [scriptblock] $OnStateChanged = $null
    )

    $script:ctx = New-DriverContext -DriverPage $DriverPage -SetStatus $SetStatus -OnStateChanged $OnStateChanged

    Assert-DriverContext -Context $script:ctx
    Write-DriverUiWiresLog -Context $script:ctx
    Register-DriverEventHandlers -Context $script:ctx

    Refresh-DriverUI
    Refresh-DriverMountedList

    try {
        Invoke-DriverPageActivated -Context $script:ctx -Reason "Initialize"
    } catch {}
}
