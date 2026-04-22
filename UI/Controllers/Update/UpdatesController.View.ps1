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

    Set-UiEnabled -Root $script:ctx.Page -Name 'CmbUpdatesMounts'      -Enabled (($items.Count -gt 0) -and (-not $script:isBusy))
    Set-UiEnabled -Root $script:ctx.Page -Name 'ChkUpdatesAutoCatalog' -Enabled (-not $script:isBusy)
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

    Set-UiEnabled -Root $page -Name 'BtnUpdatesRefresh'        -Enabled (-not $Busy)
    Set-UiEnabled -Root $page -Name 'BtnCatalogSearch'         -Enabled (-not $Busy -and $null -ne $script:updateContext)
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

    Set-UiText -Root $page -Name 'TxtUpdatesImageFile'        -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesEdition'          -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesReadWrite'        -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentLCU'       -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentSSU'       -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesCurrentDotNet'    -Value '-'
    Set-UiText -Root $page -Name 'TxtUpdatesInstalledKbCount' -Value '0'
    Set-UiText -Root $page -Name 'TxtUpdatesPackagesCount'    -Value 'Pakete: 0'
    Set-UiText -Root $page -Name 'TxtUpdatesFooterHint'       -Value 'Mount-Daten laden. Danach kann die Catalog-Suche ausgefuehrt werden.'
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
    Update-UpdatesActionButtons
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

    Set-UpdatesStatusText -Message $statusLine
    Set-UiText -Root $page -Name 'TxtUpdatesFooterHint' -Value 'Mount-Daten geladen. Catalog-Suche kann gestartet werden.'

    Reset-CatalogState
    Apply-CatalogView
    Apply-PackagesView
    Set-UiEnabled -Root $page -Name 'BtnCatalogSearch' -Enabled $true
}