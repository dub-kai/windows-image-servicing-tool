function New-MountDisplayText {
    param($Mount)

    if ($null -eq $Mount) { return '-' }

    $mountDir = [string]$Mount.MountDir
    $imageFile = [string]$Mount.ImageFile
    $imageIndex = [string]$Mount.ImageIndex

    $name = $mountDir
    if (-not [string]::IsNullOrWhiteSpace($imageFile)) {
        try {
            $fileName = [System.IO.Path]::GetFileName($imageFile)
            if (-not [string]::IsNullOrWhiteSpace($fileName)) {
                $name = $fileName
            }
        }
        catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($imageIndex)) {
        $name = '{0} (Index {1})' -f $name, $imageIndex
    }

    if (-not [string]::IsNullOrWhiteSpace($mountDir) -and $name -ne $mountDir) {
        return '{0} | {1}' -f $name, $mountDir
    }

    return $name
}

function Get-UpdatesUiString {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Default,
        [object[]]$Args = @()
    )

    try {
        if (Get-Command Get-UiString -ErrorAction SilentlyContinue) {
            return (Get-UiString -Key $Key -Args $Args)
        }
    } catch {}

    if (@($Args).Count -gt 0) {
        try { return ($Default -f $Args) } catch {}
    }

    return $Default
}

function Update-MountSelectorUi {
    param(
        [object[]]$Mounts,
        [string]$PreferredMountDir
    )

    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $combo = Find-Ui -Root $script:ctx.Page -Name 'CmbUpdatesMounts'
    $items = @()

    foreach ($mount in @($Mounts)) {
        if ($null -eq $mount) { continue }

        $mountDir = [string]$mount.MountDir
        if ([string]::IsNullOrWhiteSpace($mountDir)) { continue }

        $items += [pscustomobject]@{
            MountDir    = $mountDir
            ImageFile   = [string]$mount.ImageFile
            ImageIndex  = [string]$mount.ImageIndex
            Status      = [string]$mount.Status
            ReadWrite   = [string]$mount.ReadWrite
            MountKind   = if ($mount.PSObject.Properties.Match('MountKind').Count -gt 0) { [string]$mount.MountKind } else { '' }
            MountCapability = if ($mount.PSObject.Properties.Match('MountCapability').Count -gt 0) { [string]$mount.MountCapability } else { '' }
            MountGuidance = if ($mount.PSObject.Properties.Match('MountGuidance').Count -gt 0) { [string]$mount.MountGuidance } else { '' }
            CanIntegrateUpdates = if ($mount.PSObject.Properties.Match('CanIntegrateUpdates').Count -gt 0) { [bool]$mount.CanIntegrateUpdates } else { $false }
            DisplayText = New-MountDisplayText -Mount $mount
        }
    }

    $script:mountItems = @($items)

    $selectedItem = $null
    $script:suspendMountSelectionEvent = $true
    try {
        if ($combo) {
            $combo.DisplayMemberPath = 'DisplayText'
            $combo.SelectedValuePath = 'MountDir'
            $combo.ItemsSource = $null
            $combo.ItemsSource = @($items)

            if (-not [string]::IsNullOrWhiteSpace($PreferredMountDir)) {
                $selectedItem = @(
                    $items |
                    Where-Object { ([string]$_.MountDir) -ieq $PreferredMountDir } |
                    Select-Object -First 1
                )
            }

            if (-not $selectedItem -and $items.Count -gt 0) {
                $selectedItem = $items[0]
            }

            $combo.SelectedItem = $selectedItem
        }
    }
    finally {
        $script:suspendMountSelectionEvent = $false
    }

    $script:selectedMountDir = if ($selectedItem) { [string]$selectedItem.MountDir } else { $null }

    $selectedText = if ($selectedItem) { [string]$selectedItem.DisplayText } else { '-' }
    Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesMountHint' -Value (Get-UpdatesUiString -Key 'UpdatesMountSelectionFormat' -Default 'Mounts: {0} | Auswahl: {1}' -Args @($items.Count, $selectedText))
    Update-UpdatesBatchPlanUi

    Set-UiEnabled -Root $script:ctx.Page -Name 'CmbUpdatesMounts'      -Enabled (($items.Count -gt 0) -and (-not $script:isBusy))
    Set-UiEnabled -Root $script:ctx.Page -Name 'ChkUpdatesAutoCatalog' -Enabled (-not $script:isBusy)
}

function Test-UpdatesMountUiItemWritable {
    param($Mount)

    if ($null -eq $Mount) { return $false }

    try {
        if ($Mount.PSObject.Properties.Match('CanIntegrateUpdates').Count -gt 0) {
            return [bool]$Mount.CanIntegrateUpdates
        }
    } catch {}

    $rw = ''
    $status = ''
    try { $rw = [string]$Mount.ReadWrite } catch {}
    try { $status = [string]$Mount.Status } catch {}

    if (-not [string]::IsNullOrWhiteSpace($status)) {
        $s = $status.ToLowerInvariant()
        if ($s -notmatch '^(ok|mounted)$') { return $false }
    }

    if ([string]::IsNullOrWhiteSpace($rw)) { return $false }
    $x = $rw.ToLowerInvariant()
    if ($x -match 'readonly' -or $x -match 'read\s*only' -or $x -match '^no$' -or $x -match '^false$') { return $false }
    if ($x -match 'read/write' -or $x -match 'readwrite' -or $x -match '^yes$' -or $x -match '^true$' -or $x -match '\brw\b') { return $true }

    return $false
}

function Get-UpdatesBatchPlanText {
    $mounts = @($script:mountItems | Where-Object { $null -ne $_ })
    if ($mounts.Count -lt 1) {
        return (Get-UpdatesUiString -Key 'UpdatesBatchNoMount' -Default 'Batch: Kein Mount geladen. Bitte zuerst Images mounten oder aktualisieren.')
    }

    $writable = @($mounts | Where-Object { Test-UpdatesMountUiItemWritable -Mount $_ })
    $selectedUpdate = $null
    try {
        if (Get-Command Get-SelectedCatalogItem -ErrorAction SilentlyContinue) {
            $selectedUpdate = Get-SelectedCatalogItem
        }
    } catch { $selectedUpdate = $null }

    $updateText = Get-UpdatesUiString -Key 'UpdatesBatchNoCatalog' -Default 'kein Catalog-Treffer ausgewählt'
    if ($selectedUpdate) {
        $kb = ''
        $title = ''
        try { $kb = [string]$selectedUpdate.KB } catch {}
        try { $title = [string]$selectedUpdate.Title } catch {}
        if (-not [string]::IsNullOrWhiteSpace($kb)) {
            $updateText = $kb
        } elseif (-not [string]::IsNullOrWhiteSpace($title)) {
            $updateText = $title
        } else {
            $updateText = Get-UpdatesUiString -Key 'UpdatesBatchCatalogSelected' -Default 'Catalog-Treffer ausgewählt'
        }
    }

    $preview = @(
        $writable |
        Select-Object -First 4 |
        ForEach-Object {
            $display = ''
            try { $display = [string]$_.DisplayText } catch {}
            if ([string]::IsNullOrWhiteSpace($display)) { $display = [string]$_.MountDir }
            $display
        }
    )

    $previewText = if ($preview.Count -gt 0) { $preview -join '; ' } else { '-' }
    $more = if ($writable.Count -gt $preview.Count) { Get-UpdatesUiString -Key 'UpdatesBatchMoreTargets' -Default ' + {0} weitere' -Args @(($writable.Count - $preview.Count)) } else { "" }

    return (Get-UpdatesUiString -Key 'UpdatesBatchPlanFormat' -Default 'Batch: {0}/{1} Mounts sind Read/Write. Update: {2}. Ziele: {3}{4}' -Args @($writable.Count, $mounts.Count, $updateText, $previewText, $more))
}

function Update-UpdatesBatchPlanUi {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    try {
        Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesBatchPlan' -Value (Get-UpdatesBatchPlanText)
    } catch {}

    try { Update-UpdatesWorkflowUi } catch {}
}

function Get-UpdatesWorkflowSelectedUpdateText {
    $selectedUpdate = $null
    try {
        if (Get-Command Get-SelectedCatalogItem -ErrorAction SilentlyContinue) {
            $selectedUpdate = Get-SelectedCatalogItem
        }
    } catch { $selectedUpdate = $null }

    if (-not $selectedUpdate) { return '' }

    $kb = ''
    $title = ''
    try { $kb = [string]$selectedUpdate.KB } catch {}
    try { $title = [string]$selectedUpdate.Title } catch {}

    if (-not [string]::IsNullOrWhiteSpace($kb)) { return $kb }
    if (-not [string]::IsNullOrWhiteSpace($title)) { return $title }
    return (Get-UpdatesUiString -Key 'UpdatesCatalogResultFallback' -Default 'Catalog-Treffer')
}

function Update-UpdatesWorkflowUi {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $mounts = @($script:mountItems | Where-Object { $null -ne $_ })
    $writable = @($mounts | Where-Object { Test-UpdatesMountUiItemWritable -Mount $_ })

    $selectedMount = $null
    $selectedMountDir = $null
    try { $selectedMountDir = Get-SelectedMountDir } catch { $selectedMountDir = $script:selectedMountDir }
    if (-not [string]::IsNullOrWhiteSpace([string]$selectedMountDir)) {
        $selectedMount = $mounts | Where-Object { ([string]$_.MountDir) -ieq [string]$selectedMountDir } | Select-Object -First 1
    }

    $mountState = Get-UpdatesUiString -Key 'UpdatesNoMountsLoaded' -Default 'Keine Mounts geladen'
    $mountDetail = Get-UpdatesUiString -Key 'UpdatesNoMountsDetail' -Default 'Öffne Images, mounte ein Image oder klicke hier auf Refresh.'
    if ($mounts.Count -gt 0) {
        $display = if ($selectedMount) { [string]$selectedMount.DisplayText } else { Get-UpdatesUiString -Key 'UpdatesNoSelection' -Default 'keine Auswahl' }
        $mountState = Get-UpdatesUiString -Key 'UpdatesMountStateFormat' -Default '{0} Mount(s), {1} Read/Write' -Args @($mounts.Count, $writable.Count)
        $mountDetail = Get-UpdatesUiString -Key 'UpdatesSelectionFormat' -Default 'Auswahl: {0}' -Args @($display)
        if ($selectedMount -and -not (Test-UpdatesMountUiItemWritable -Mount $selectedMount)) {
            $hint = ''
            try { $hint = [string]$selectedMount.MountGuidance } catch {}
            if ([string]::IsNullOrWhiteSpace($hint)) { $hint = Get-UpdatesUiString -Key 'UpdatesMountNotSuitable' -Default 'Dieser Mount ist nicht für Update-Integration geeignet.' }
            $mountDetail = $hint
        }
    }

    if ($script:updateContext) {
        $edition = ''
        $rw = ''
        try { $edition = [string]$script:updateContext.Edition } catch {}
        try { $rw = [string]$script:updateContext.ReadWrite } catch {}
        if (-not [string]::IsNullOrWhiteSpace($edition)) {
            $mountDetail = ('{0} | {1}' -f $edition, $(if ([string]::IsNullOrWhiteSpace($rw)) { Get-UpdatesUiString -Key 'UpdatesStatusLoaded' -Default 'Status geladen' } else { $rw }))
        }
    }

    $catalogTotal = @($script:catalogAllResults).Count
    $catalogVisible = @($script:catalogVisibleResults).Count
    $catalogRecommended = @($script:catalogWorkResults).Count
    $selectedUpdateText = Get-UpdatesWorkflowSelectedUpdateText

    $catalogState = Get-UpdatesUiString -Key 'UpdatesCatalogOpen' -Default 'Catalog noch offen'
    $catalogDetail = Get-UpdatesUiString -Key 'StaticStartCatalogHint' -Default 'Starte die Catalog-Suche oder füge eine lokale MSU/CAB hinzu.'
    if ($catalogTotal -gt 0) {
        $catalogState = Get-UpdatesUiString -Key 'UpdatesCatalogVisibleFormat' -Default '{0} Treffer sichtbar' -Args @($catalogVisible)
        $catalogDetail = Get-UpdatesUiString -Key 'UpdatesCatalogSummaryFormat' -Default 'Gesamt: {0} | empfohlen: {1}' -Args @($catalogTotal, $catalogRecommended)
        if (-not [string]::IsNullOrWhiteSpace($selectedUpdateText)) {
            $catalogDetail = Get-UpdatesUiString -Key 'UpdatesCatalogSelectedFormat' -Default 'Ausgewählt: {0}' -Args @($selectedUpdateText)
        }
    }

    $actionState = Get-UpdatesUiString -Key 'UpdatesActionSelectUpdate' -Default 'Update auswählen'
    $actionDetail = Get-UpdatesUiString -Key 'StaticIntegrateSelectionHint' -Default 'Wähle einen Treffer und integriere ihn in einen passenden Read/Write-Mount.'
    if ($script:isBusy) {
        $actionState = Get-UpdatesUiString -Key 'UpdatesActionBusy' -Default 'Aktion läuft'
        $actionDetail = Get-UpdatesUiString -Key 'UpdatesActionBusyDetail' -Default 'Bitte warten. Der Fortschritt steht im Busy-Bereich und im Log.'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($selectedUpdateText)) {
        if ($writable.Count -gt 0) {
            $actionState = Get-UpdatesUiString -Key 'UpdatesActionReady' -Default 'Bereit zum Anwenden'
            $actionDetail = Get-UpdatesUiString -Key 'UpdatesActionReadyDetail' -Default '{0} kann in {1} passende(n) Mount(s) integriert werden.' -Args @($selectedUpdateText, $writable.Count)
        }
        else {
            $actionState = Get-UpdatesUiString -Key 'UpdatesActionNoTarget' -Default 'Kein Read/Write-Ziel'
            $actionDetail = Get-UpdatesUiString -Key 'UpdatesActionNoTargetDetail' -Default 'Zum Integrieren brauchst du mindestens einen passenden Read/Write-Mount.'
        }
    }
    elseif ($catalogTotal -gt 0) {
        $actionState = Get-UpdatesUiString -Key 'UpdatesActionSelectResult' -Default 'Treffer auswählen'
        $actionDetail = Get-UpdatesUiString -Key 'UpdatesActionSelectResultDetail' -Default 'Wähle einen Catalog-Treffer für Download, Preflight oder Integration.'
    }

    Set-UiText -Root $page -Name 'TxtUpdatesWorkflowMountState'    -Value $mountState
    Set-UiText -Root $page -Name 'TxtUpdatesWorkflowMountDetail'   -Value $mountDetail
    Set-UiText -Root $page -Name 'TxtUpdatesWorkflowCatalogState'  -Value $catalogState
    Set-UiText -Root $page -Name 'TxtUpdatesWorkflowCatalogDetail' -Value $catalogDetail
    Set-UiText -Root $page -Name 'TxtUpdatesWorkflowActionState'   -Value $actionState
    Set-UiText -Root $page -Name 'TxtUpdatesWorkflowActionDetail'  -Value $actionDetail
}

function Set-UpdatesBusy {
    param(
        [Parameter(Mandatory)][bool]$Busy,
        [string]$Message = 'Bitte warten...'
    )

    $script:isBusy = $Busy

    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $overlay = Find-Ui -Root $page -Name 'BusyOverlay'
    if ($overlay) {
        $overlay.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
    }

    Set-UiText -Root $page -Name 'TxtBusyMessage' -Value $Message

    try {
        if ($Busy) {
            Start-UiBusyProgress -Root $page -Context $script:ctx -Message $Message -Detail (Get-UpdatesUiString -Key 'UpdatesBusyDetail' -Default 'Updates oder Paketlisten werden verarbeitet. DISM kann bei großen Paketen mehrere Minuten benötigen.') -ShowDismTail
        } else {
            Stop-UiBusyProgress -Root $page -Context $script:ctx
        }
    } catch {}

    Set-UiEnabled -Root $page -Name 'BtnUpdatesRefresh'        -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'BtnCatalogSearch'         -Enabled (-not $Busy -and $null -ne $script:updateContext)
    Set-UiEnabled -Root $page -Name 'BtnAddLocalUpdate'        -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowRefresh' -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowCatalogSearch' -Enabled (-not $Busy -and $null -ne $script:updateContext)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowAddLocal' -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportPackages' -Enabled ((@($script:visiblePackages).Count -gt 0) -and (-not $Busy))
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportCatalog'  -Enabled ((@($script:catalogVisibleResults).Count -gt 0) -and (-not $Busy))
    Set-UiEnabled -Root $page -Name 'CmbUpdatesFilterMode'     -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'TxtUpdatesFilterText'     -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'CmbUpdatesMounts'         -Enabled ((@($script:mountItems).Count -gt 0) -and (-not $Busy))
    Set-UiEnabled -Root $page -Name 'ChkUpdatesAutoCatalog'    -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'CmbUpdatesPackagesMode'   -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'TxtUpdatesPackagesFilter' -Enabled (-not $Busy)

    Update-UpdatesActionButtons
    try { Update-UpdatesWorkflowUi } catch {}
}

function Clear-UpdatesUi {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $script:updateContext = $null
    $script:allPackages = @()
    $script:visiblePackages = @()

    Set-UiText -Root $page -Name 'TxtUpdatesImageFile'        -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesEdition'          -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesReadWrite'        -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentLCU'       -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentSSU'       -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentDotNet'    -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesInstalledKbCount' -Value '0'
    Set-UiText -Root $page -Name 'TxtUpdatesPackagesCount'    -Value (Get-UpdatesUiString -Key 'StaticPackagesZero' -Default 'Pakete: 0')
    Set-UiText -Root $page -Name 'TxtUpdatesFooterHint'       -Value (Get-UpdatesUiString -Key 'UpdatesFooterLoadMountData' -Default 'Mount-Daten laden. Danach kann die Catalog-Suche ausgefuehrt werden.')
    Set-UiText -Root $page -Name 'TxtUpdatesServiceHint'       -Value (Get-UpdatesUiString -Key 'UpdatesServiceNoMountContext' -Default 'Eignung: Kein Mount-Kontext geladen.')
    Set-UiText -Root $page -Name 'TxtUpdatesBatchPlan'        -Value (Get-UpdatesUiString -Key 'StaticBatchMountsLoading' -Default 'Batch: Mounts werden geladen.')
    Set-UpdatesStatusText -Message '-'

    $pkgGrid = Find-Ui -Root $page -Name 'GridUpdatesPackages'
    if ($pkgGrid) {
        $pkgGrid.ItemsSource = @()
        $pkgGrid.Items.Refresh()
    }

    Reset-CatalogState
    Apply-CatalogView
    Apply-PackagesView

    Set-UiEnabled -Root $page -Name 'BtnCatalogSearch' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowCatalogSearch' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnAddLocalUpdate' -Enabled (-not $script:isBusy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowRefresh' -Enabled (-not $script:isBusy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowAddLocal' -Enabled (-not $script:isBusy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportPackages' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportCatalog' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnCatalogIntegrateAll' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnCatalogPreflight' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowIntegrate' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowIntegrateAll' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnUpdatesWorkflowPreflight' -Enabled $false
    Update-UpdatesActionButtons
    Update-UpdatesBatchPlanUi
    try { Update-UpdatesWorkflowUi } catch {}
}

function Get-UpdatesDisplayBuildText {
    param($Context)

    if ($null -eq $Context) { return '-' }

    $osBuild = ''
    $servicingBuild = ''
    $fallback = ''

    try { $osBuild = [string]$Context.OsBuildVersion } catch {}
    try { $servicingBuild = [string]$Context.ServicingBuildVersion } catch {}
    try { $fallback = [string]$Context.CurrentBuildVersion } catch {}

    if ([string]::IsNullOrWhiteSpace($osBuild) -or $osBuild -eq '-') {
        $osBuild = $fallback
    }

    if (-not [string]::IsNullOrWhiteSpace($osBuild) -and $osBuild -ne '-') {
        if (-not [string]::IsNullOrWhiteSpace($servicingBuild) -and $servicingBuild -ne '-' -and $servicingBuild -ne $osBuild) {
            return ('{0} | Servicing: {1}' -f $osBuild, $servicingBuild)
        }

        return $osBuild
    }

    try {
        $branch = [string]$Context.BuildBranch
        if (-not [string]::IsNullOrWhiteSpace($branch)) {
            return $branch
        }
    }
    catch {}

    return '-'
}

function Show-UpdateContext {
    param($Context)

    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $script:updateContext = $Context
    $script:allPackages = @($Context.Packages)

    $imageLine = [string]$Context.ImageFile
    if ($Context.ImageIndex) {
        $imageLine = '{0} (Index {1})' -f $imageLine, $Context.ImageIndex
    }

    Set-UiText -Root $page -Name 'TxtUpdatesImageFile'        -Value $imageLine
    Set-UiText -Root $page -Name 'TxtUpdatesEdition'          -Value $Context.Edition
    Set-UiText -Root $page -Name 'TxtUpdatesReadWrite'        -Value $Context.ReadWrite
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentLCU'       -Value $Context.CurrentLCUVersion
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentSSU'       -Value $Context.CurrentSSUVersion
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentDotNet'    -Value $Context.CurrentDotNetVersion
    Set-UiText -Root $page -Name 'TxtUpdatesInstalledKbCount' -Value $Context.InstalledKBCount

    $buildText = Get-UpdatesDisplayBuildText -Context $Context

    $statusLine = Get-UpdatesUiString -Key 'UpdatesMountReadyStatusFormat' -Default 'Mount bereit | Produkt: {0} | Arch: {1} | Build: {2}' -Args @($Context.ProductFamily, $Context.Architecture, $buildText)

    $catalogSupported = $true
    try {
        if ($Context.PSObject.Properties.Match('CatalogSearchSupported').Count -gt 0) {
            $catalogSupported = [bool]$Context.CatalogSearchSupported
        }
    } catch { $catalogSupported = $true }

    $canIntegrateUpdates = $true
    try {
        if ($Context.PSObject.Properties.Match('CanIntegrateUpdates').Count -gt 0) {
            $canIntegrateUpdates = [bool]$Context.CanIntegrateUpdates
        }
    } catch { $canIntegrateUpdates = $true }

    $serviceStatus = Get-UpdatesUiString -Key 'UpdatesServiceStatusDefault' -Default 'Eignung'
    $serviceHint = Get-UpdatesUiString -Key 'UpdatesMountDataLoaded' -Default 'Mount-Daten geladen.'
    try {
        if ($Context.PSObject.Properties.Match('UpdateServiceStatus').Count -gt 0) { $serviceStatus = [string]$Context.UpdateServiceStatus }
        if ($Context.PSObject.Properties.Match('UpdateServiceHint').Count -gt 0) { $serviceHint = [string]$Context.UpdateServiceHint }
    } catch {}

    $footerHint = Get-UpdatesUiString -Key 'UpdatesFooterCatalogReady' -Default 'Mount-Daten geladen. Catalog-Suche kann gestartet werden.'
    if (-not $catalogSupported) {
        $reason = Get-UpdatesUiString -Key 'UpdatesBootWinPeReason' -Default 'Boot-/WinPE-Image erkannt. Pakete werden angezeigt, aber die automatische Catalog-Suche ist deaktiviert.'
        try {
            if ($Context.PSObject.Properties.Match('CatalogSkipReason').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Context.CatalogSkipReason)) {
                $reason = [string]$Context.CatalogSkipReason
            }
        } catch {}
        $statusLine = $statusLine + ' | Boot/WinPE'
        $footerHint = $reason
    }
    elseif (-not $canIntegrateUpdates) {
        $statusLine = $statusLine + (' | {0}' -f $serviceStatus)
        $footerHint = $serviceHint
    }

    Set-UpdatesStatusText -Message $statusLine
    Set-UiText -Root $page -Name 'TxtUpdatesFooterHint' -Value $footerHint
    Set-UiText -Root $page -Name 'TxtUpdatesServiceHint' -Value (Get-UpdatesUiString -Key 'UpdatesServiceHintFormat' -Default 'Eignung: {0} | {1}' -Args @($serviceStatus, $serviceHint))

    Reset-CatalogState
    Apply-CatalogView
    Apply-PackagesView
    Set-UiEnabled -Root $page -Name 'BtnCatalogSearch' -Enabled $catalogSupported
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportPackages' -Enabled (@($script:visiblePackages).Count -gt 0)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportCatalog' -Enabled (@($script:catalogVisibleResults).Count -gt 0)
    try { Update-UpdatesWorkflowUi } catch {}
}
