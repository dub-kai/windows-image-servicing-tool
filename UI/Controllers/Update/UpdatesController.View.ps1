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
    Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesMountHint' -Value ('Mounts: {0} | Auswahl: {1}' -f $items.Count, $selectedText)
    Update-UpdatesBatchPlanUi

    Set-UiEnabled -Root $script:ctx.Page -Name 'CmbUpdatesMounts'      -Enabled (($items.Count -gt 0) -and (-not $script:isBusy))
    Set-UiEnabled -Root $script:ctx.Page -Name 'ChkUpdatesAutoCatalog' -Enabled (-not $script:isBusy)
}

function Test-UpdatesMountUiItemWritable {
    param($Mount)

    if ($null -eq $Mount) { return $false }

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
        return 'Batch: Kein Mount geladen. Bitte zuerst Images mounten oder aktualisieren.'
    }

    $writable = @($mounts | Where-Object { Test-UpdatesMountUiItemWritable -Mount $_ })
    $selectedUpdate = $null
    try {
        if (Get-Command Get-SelectedCatalogItem -ErrorAction SilentlyContinue) {
            $selectedUpdate = Get-SelectedCatalogItem
        }
    } catch { $selectedUpdate = $null }

    $updateText = 'kein Catalog-Treffer ausgewählt'
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
            $updateText = 'Catalog-Treffer ausgewählt'
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
    $more = if ($writable.Count -gt $preview.Count) { " + {0} weitere" -f ($writable.Count - $preview.Count) } else { "" }

    return ("Batch: {0}/{1} Mounts sind Read/Write. Update: {2}. Ziele: {3}{4}" -f $writable.Count, $mounts.Count, $updateText, $previewText, $more)
}

function Update-UpdatesBatchPlanUi {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    try {
        Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesBatchPlan' -Value (Get-UpdatesBatchPlanText)
    } catch {}
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
            Start-UiBusyProgress -Root $page -Context $script:ctx -Message $Message -Detail 'Updates oder Paketlisten werden verarbeitet. DISM kann bei großen Paketen mehrere Minuten benötigen.' -ShowDismTail
        } else {
            Stop-UiBusyProgress -Root $page -Context $script:ctx
        }
    } catch {}

    Set-UiEnabled -Root $page -Name 'BtnUpdatesRefresh'        -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'BtnCatalogSearch'         -Enabled (-not $Busy -and $null -ne $script:updateContext)
    Set-UiEnabled -Root $page -Name 'BtnAddLocalUpdate'        -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportPackages' -Enabled ((@($script:visiblePackages).Count -gt 0) -and (-not $Busy))
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportCatalog'  -Enabled ((@($script:catalogVisibleResults).Count -gt 0) -and (-not $Busy))
    Set-UiEnabled -Root $page -Name 'CmbUpdatesFilterMode'     -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'TxtUpdatesFilterText'     -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'CmbUpdatesMounts'         -Enabled ((@($script:mountItems).Count -gt 0) -and (-not $Busy))
    Set-UiEnabled -Root $page -Name 'ChkUpdatesAutoCatalog'    -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'CmbUpdatesPackagesMode'   -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'TxtUpdatesPackagesFilter' -Enabled (-not $Busy)

    Update-UpdatesActionButtons
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
    Set-UiText -Root $page -Name 'TxtUpdatesPackagesCount'    -Value 'Pakete: 0'
    Set-UiText -Root $page -Name 'TxtUpdatesFooterHint'       -Value 'Mount-Daten laden. Danach kann die Catalog-Suche ausgefuehrt werden.'
    Set-UiText -Root $page -Name 'TxtUpdatesBatchPlan'        -Value 'Batch: Mounts werden geladen.'
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
    Set-UiEnabled -Root $page -Name 'BtnAddLocalUpdate' -Enabled (-not $script:isBusy)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportPackages' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportCatalog' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnCatalogIntegrateAll' -Enabled $false
    Set-UiEnabled -Root $page -Name 'BtnCatalogPreflight' -Enabled $false
    Update-UpdatesActionButtons
    Update-UpdatesBatchPlanUi
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

    $statusLine = 'Mount bereit | Produkt: {0} | Arch: {1} | Build: {2}' -f `
        $Context.ProductFamily, `
        $Context.Architecture, `
        $buildText

    $catalogSupported = $true
    try {
        if ($Context.PSObject.Properties.Match('CatalogSearchSupported').Count -gt 0) {
            $catalogSupported = [bool]$Context.CatalogSearchSupported
        }
    } catch { $catalogSupported = $true }

    $footerHint = 'Mount-Daten geladen. Catalog-Suche kann gestartet werden.'
    if (-not $catalogSupported) {
        $reason = 'Boot-/WinPE-Image erkannt. Pakete werden angezeigt, aber die automatische Catalog-Suche ist deaktiviert.'
        try {
            if ($Context.PSObject.Properties.Match('CatalogSkipReason').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Context.CatalogSkipReason)) {
                $reason = [string]$Context.CatalogSkipReason
            }
        } catch {}
        $statusLine = $statusLine + ' | Boot/WinPE'
        $footerHint = $reason
    }

    Set-UpdatesStatusText -Message $statusLine
    Set-UiText -Root $page -Name 'TxtUpdatesFooterHint' -Value $footerHint

    Reset-CatalogState
    Apply-CatalogView
    Apply-PackagesView
    Set-UiEnabled -Root $page -Name 'BtnCatalogSearch' -Enabled $catalogSupported
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportPackages' -Enabled (@($script:visiblePackages).Count -gt 0)
    Set-UiEnabled -Root $page -Name 'BtnUpdatesExportCatalog' -Enabled (@($script:catalogVisibleResults).Count -gt 0)
}
