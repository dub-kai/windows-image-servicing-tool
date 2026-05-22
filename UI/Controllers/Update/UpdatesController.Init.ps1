function Initialize-UpdatesController {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$UpdatesPage,
        [Parameter(Mandatory)][scriptblock]$SetStatus,
        $OnStateChanged = $null
    )

    $script:ctx = [ordered]@{
        Page           = $UpdatesPage
        SetStatus      = $SetStatus
        OnStateChanged = $OnStateChanged
    }

    Clear-UpdatesUi
    Update-MountSelectorUi -Mounts @() -PreferredMountDir $null

    $btnRefresh   = Find-Ui -Root $UpdatesPage -Name 'BtnUpdatesRefresh'
    $btnSearch    = Find-Ui -Root $UpdatesPage -Name 'BtnCatalogSearch'
    $btnAddLocal  = Find-Ui -Root $UpdatesPage -Name 'BtnAddLocalUpdate'
    $btnDownload  = Find-Ui -Root $UpdatesPage -Name 'BtnCatalogDownload'
    $btnIntegrate = Find-Ui -Root $UpdatesPage -Name 'BtnCatalogIntegrate'
    $btnIntegrateAll = Find-Ui -Root $UpdatesPage -Name 'BtnCatalogIntegrateAll'
    $btnPreflight = Find-Ui -Root $UpdatesPage -Name 'BtnCatalogPreflight'
    $btnExportPkg = Find-Ui -Root $UpdatesPage -Name 'BtnUpdatesExportPackages'
    $btnExportCat = Find-Ui -Root $UpdatesPage -Name 'BtnUpdatesExportCatalog'
    $cmbMode      = Find-Ui -Root $UpdatesPage -Name 'CmbUpdatesFilterMode'
    $txtFilter    = Find-Ui -Root $UpdatesPage -Name 'TxtUpdatesFilterText'
    $gridCatalog  = Find-Ui -Root $UpdatesPage -Name 'GridCatalogResults'
    $cmbMounts    = Find-Ui -Root $UpdatesPage -Name 'CmbUpdatesMounts'
    $chkAuto      = Find-Ui -Root $UpdatesPage -Name 'ChkUpdatesAutoCatalog'
    $cmbPkgMode   = Find-Ui -Root $UpdatesPage -Name 'CmbUpdatesPackagesMode'
    $txtPkgFilter = Find-Ui -Root $UpdatesPage -Name 'TxtUpdatesPackagesFilter'

    try {
        Write-Log -Level INFO -Message ('Updates UI wires: BtnRefresh={0} BtnSearch={1} BtnAddLocal={2} BtnDownload={3} BtnIntegrate={4} BtnIntegrateAll={5} BtnPreflight={6} BtnExportPkg={7} BtnExportCat={8} CmbMode={9} TxtFilter={10} GridCatalog={11} CmbMounts={12} ChkAuto={13} CmbPkgMode={14} TxtPkgFilter={15}' -f `
            ($null -ne $btnRefresh),
            ($null -ne $btnSearch),
            ($null -ne $btnAddLocal),
            ($null -ne $btnDownload),
            ($null -ne $btnIntegrate),
            ($null -ne $btnIntegrateAll),
            ($null -ne $btnPreflight),
            ($null -ne $btnExportPkg),
            ($null -ne $btnExportCat),
            ($null -ne $cmbMode),
            ($null -ne $txtFilter),
            ($null -ne $gridCatalog),
            ($null -ne $cmbMounts),
            ($null -ne $chkAuto),
            ($null -ne $cmbPkgMode),
            ($null -ne $txtPkgFilter))
    } catch {}

    if ($chkAuto) {
        try {
            $chkAuto.IsChecked = [bool](Get-ConfigValue -Key 'UpdatesAutoCatalogDefault' -Default $true)
        } catch {}
    }

    if ($btnRefresh) {
        $btnRefresh.Add_Click({
            try {
                if ($script:isBusy) { return }
                Write-Log -Level INFO -Message 'Updates: manueller Refresh'
                Refresh-UpdatesUI
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: manueller Refresh fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($btnSearch) {
        $btnSearch.Add_Click({
            try {
                if ($script:isBusy) { return }
                Invoke-CatalogSearchUi
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Catalog-Suche fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($btnAddLocal) {
        $btnAddLocal.Add_Click({
            try {
                if ($script:isBusy) { return }
                Add-LocalUpdatePackageUi
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Lokales Update konnte nicht hinzugefügt werden: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($btnDownload) {
        $btnDownload.Add_Click({
            try {
                if ($script:isBusy) { return }
                Invoke-CatalogDownloadUi
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Download fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($btnIntegrate) {
        $btnIntegrate.Add_Click({
            try {
                if ($script:isBusy) { return }
                Invoke-CatalogIntegrateUi
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Integration fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($cmbMode) {
        $cmbMode.Add_SelectionChanged({
            try {
                if ($script:isBusy) { return }
                Apply-CatalogView
            } catch {}
        })
    }

    if ($txtFilter) {
        $txtFilter.Add_TextChanged({
            try {
                if ($script:isBusy) { return }
                Apply-CatalogView
            } catch {}
        })
    }

    if ($gridCatalog) {
        $gridCatalog.Add_SelectionChanged({
            try {
                Update-SelectedCatalogDetails
            } catch {}
        })
    }

    if ($cmbMounts) {
        $cmbMounts.Add_SelectionChanged({
            try {
                if ($script:suspendMountSelectionEvent) { return }
                if ($script:isBusy) { return }

                $mountDir = Get-SelectedMountDir
                if ([string]::IsNullOrWhiteSpace([string]$mountDir)) { return }

                $script:selectedMountDir = [string]$mountDir

                $currentMountDir = $null
                try { $currentMountDir = [string]$script:updateContext.MountDir } catch {}
                if (-not [string]::IsNullOrWhiteSpace($currentMountDir) -and ($currentMountDir -ieq $script:selectedMountDir)) {
                    try {
                        Write-Log -Level INFO -Message ('Updates: Mount-Auswahl unveraendert, kein Context-Reload: {0}' -f $script:selectedMountDir)
                    } catch {}
                    return
                }

                Start-SelectedMountContextLoad -MountDir $script:selectedMountDir -TriggerCatalogIfEnabled
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Mount-Auswahlwechsel fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($chkAuto) {
        $chkAuto.Add_Click({
            try {
                if ($script:isBusy) { return }
                Set-ConfigValue -Key 'UpdatesAutoCatalogDefault' -Value ([bool]$chkAuto.IsChecked) -Persist | Out-Null
                Invoke-AutoCatalogSearchIfEnabled
            } catch {}
        })
    }

    if ($cmbPkgMode) {
        $cmbPkgMode.Add_SelectionChanged({
            try {
                if ($script:isBusy) { return }
                Apply-PackagesView
            } catch {}
        })
    }

    if ($txtPkgFilter) {
        $txtPkgFilter.Add_TextChanged({
            try {
                if ($script:isBusy) { return }
                Apply-PackagesView
            } catch {}
        })
    }

    if ($UpdatesPage) {
        $UpdatesPage.Add_IsVisibleChanged({
            param($sender, $args)

            try {
                if (-not $sender.IsVisible) { return }
                Invoke-UpdatesPageActivated -Reason "IsVisibleChanged"
            } catch {}
        })

        $UpdatesPage.Add_Loaded({
            param($sender, $args)

            try {
                if (-not $sender.IsVisible) { return }
                Invoke-UpdatesPageActivated -Reason "Loaded"
            } catch {}
        })
    }

    if ($btnIntegrateAll) {
        $btnIntegrateAll.Add_Click({
            try {
                if ($script:isBusy) { return }
                Invoke-CatalogIntegrateAllUi
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Batch-Integration fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($btnPreflight) {
        $btnPreflight.Add_Click({
            try {
                if ($script:isBusy) { return }
                Invoke-CatalogPreflightUi
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Batch-Prüfung fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($btnExportPkg) {
        $btnExportPkg.Add_Click({
            try {
                if ($script:isBusy) { return }
                Export-UpdatesPackagesCsv
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Paket-Export fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    if ($btnExportCat) {
        $btnExportCat.Add_Click({
            try {
                if ($script:isBusy) { return }
                Export-CatalogResultsCsv
            } catch {
                try {
                    Write-Log -Level WARN -Message ('Updates: Catalog-Export fehlgeschlagen: {0}' -f $_.Exception.Message)
                } catch {}
            }
        })
    }

    Set-UpdatesBusy -Busy $false

    try {
        Write-Log -Level INFO -Message 'Updates: Initial refresh'
        Invoke-UpdatesPageActivated -Reason "Initialize"
    } catch {
        try {
            Write-Log -Level WARN -Message ('Updates: initialer Refresh fehlgeschlagen: {0}' -f $_.Exception.Message)
        } catch {}
    }
}
