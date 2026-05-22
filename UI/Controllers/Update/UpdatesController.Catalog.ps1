function Reset-CatalogState {
    $script:catalogAllResults = @()
    $script:catalogWorkResults = @()
    $script:catalogVisibleResults = @()
    $script:catalogRecommendations = $null
    $script:lastCatalogSelectionKey = $null
}

function Get-SelectedCatalogItem {
    if (-not $script:ctx -or -not $script:ctx.Page) { return $null }

    $grid = Find-Ui -Root $script:ctx.Page -Name 'GridCatalogResults'
    if (-not $grid) { return $null }

    return $grid.SelectedItem
}

function Test-CatalogItemIsLocalPackage {
    param($Item)

    if ($null -eq $Item) { return $false }

    try {
        if ($Item.PSObject.Properties.Match('IsLocalPackage').Count -gt 0 -and [bool]$Item.IsLocalPackage) {
            return $true
        }
    } catch {}

    try {
        if ($Item.PSObject.Properties.Match('LocalPackagePath').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Item.LocalPackagePath)) {
            return $true
        }
    } catch {}

    return $false
}

function Get-CatalogItemLocalPackagePath {
    param($Item)

    if ($null -eq $Item) { return '' }

    try {
        if ($Item.PSObject.Properties.Match('LocalPackagePath').Count -gt 0) {
            return [string]$Item.LocalPackagePath
        }
    } catch {}

    return ''
}

function Get-CatalogSelectionKey {
    param($Item)

    if ($null -eq $Item) { return $null }

    $localPath = Get-CatalogItemLocalPackagePath -Item $Item
    if (-not [string]::IsNullOrWhiteSpace($localPath)) {
        return ('LOCAL|' + $localPath)
    }

    $updateId = [string]$Item.UpdateId
    if (-not [string]::IsNullOrWhiteSpace($updateId)) { return $updateId }

    return (([string]$Item.Title) + '|' + ([string]$Item.KB) + '|' + ([string]$Item.Version))
}

function Format-CatalogItemLine {
    param($Item)

    if ($null -eq $Item) { return '-' }

    $kb = [string]$Item.KB
    $kind = [string]$Item.Kind
    $date = [string]$Item.LastUpdated
    $title = [string]$Item.Title

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($kb))   { $parts.Add($kb) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($kind)) { $parts.Add($kind) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($date)) { $parts.Add($date) | Out-Null }

    if ($parts.Count -gt 0) {
        return (($parts -join ' | ') + ' | ' + $title)
    }

    return $title
}

function Update-SelectedCatalogDetails {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $item = Get-SelectedCatalogItem

    if ($item) {
        $script:lastCatalogSelectionKey = Get-CatalogSelectionKey -Item $item
        Set-UiText -Root $page -Name 'TxtSelectedCatalogKB'      -Value $item.KB
        Set-UiText -Root $page -Name 'TxtSelectedCatalogType'    -Value $item.Kind
        Set-UiText -Root $page -Name 'TxtSelectedCatalogDate'    -Value $item.LastUpdated
        Set-UiText -Root $page -Name 'TxtSelectedCatalogVersion' -Value $item.Version
        Set-UiText -Root $page -Name 'TxtSelectedCatalogTitle'   -Value $item.Title
    }
    else {
        Set-UiText -Root $page -Name 'TxtSelectedCatalogKB'      -Value '-'
        Set-UiText -Root $page -Name 'TxtSelectedCatalogType'    -Value '-'
        Set-UiText -Root $page -Name 'TxtSelectedCatalogDate'    -Value '-'
        Set-UiText -Root $page -Name 'TxtSelectedCatalogVersion' -Value '-'
        Set-UiText -Root $page -Name 'TxtSelectedCatalogTitle'   -Value 'Noch kein Catalog-Treffer ausgewaehlt.'
    }

    Update-UpdatesActionButtons
    try { Update-UpdatesBatchPlanUi } catch {}
}

function Update-UpdatesActionButtons {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $selected = Get-SelectedCatalogItem
    $canSelect = ($null -ne $selected) -and (-not $script:isBusy)
    $isLocal = Test-CatalogItemIsLocalPackage -Item $selected
    $hasUpdateId = $false
    try { $hasUpdateId = -not [string]::IsNullOrWhiteSpace([string]$selected.UpdateId) } catch {}

    Set-UiEnabled -Root $script:ctx.Page -Name 'BtnCatalogDownload'  -Enabled ($canSelect -and (-not $isLocal) -and $hasUpdateId)
    Set-UiEnabled -Root $script:ctx.Page -Name 'BtnCatalogIntegrate' -Enabled $canSelect
    Set-UiEnabled -Root $script:ctx.Page -Name 'BtnCatalogIntegrateAll' -Enabled ($canSelect -and (@($script:mountItems).Count -gt 0))
    Set-UiEnabled -Root $script:ctx.Page -Name 'BtnCatalogPreflight' -Enabled ($canSelect -and (@($script:mountItems).Count -gt 0))
}

function New-LocalCatalogItem {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $name = [string]$item.Name
    $encodedPath = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$item.FullName))
    $encodedPath = $encodedPath.TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $kb = ''
    $mKb = [regex]::Match($name, '(KB\d{6,8})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($mKb.Success) { $kb = $mKb.Groups[1].Value.ToUpperInvariant() }

    $version = ''
    $mVer = [regex]::Match($name, '(?<!\d)(?<v>\d{4,5}\.\d{1,5})(?!\d)')
    if ($mVer.Success) { $version = [string]$mVer.Groups['v'].Value }

    $kind = if ($name -match 'Preview') { 'Preview' } else { 'Manual' }

    return [pscustomobject]@{
        Query               = 'LocalPackage'
        UpdateId            = ('LOCAL:' + $encodedPath)
        Title               = $name
        KB                  = $kb
        Products            = 'Lokale Datei'
        Classification      = 'Manuell hinzugefügt'
        LastUpdated         = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        Version             = $version
        CatalogVersionLabel = $version
        Size                = ('{0:N1} MB' -f ($item.Length / 1MB))
        Kind                = $kind
        IsPreview           = ($kind -eq 'Preview')
        IsInstalled         = $false
        IsInstalledByKb     = $false
        IsInstalledByVersion= $false
        IsLocalPackage      = $true
        LocalPackagePath    = [string]$item.FullName
    }
}

function Add-LocalUpdatePackageUi {
    if ($script:isBusy) { return }

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Lokales Update auswählen'
    $dlg.Filter = 'Windows Update Pakete (*.msu;*.cab)|*.msu;*.cab|Alle Dateien (*.*)|*.*'
    $dlg.Multiselect = $true

    $ok = $dlg.ShowDialog()
    if ($ok -ne $true) { return }

    $added = New-Object System.Collections.Generic.List[object]
    foreach ($path in @($dlg.FileNames)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        try {
            $ext = [System.IO.Path]::GetExtension([string]$path).ToLowerInvariant()
            if ($ext -notin @('.msu', '.cab')) { continue }
            $added.Add((New-LocalCatalogItem -Path ([string]$path))) | Out-Null
        } catch {
            try { Write-Log -Level WARN -Message ('Lokales Update konnte nicht übernommen werden: {0}' -f $_.Exception.Message) } catch {}
        }
    }

    $newItems = @($added.ToArray())
    if ($newItems.Count -lt 1) {
        Show-UiInfo -Message 'Es wurde keine gültige .msu- oder .cab-Datei ausgewählt.' -Title 'Lokales Update'
        return
    }

    $existing = @($script:catalogAllResults | Where-Object { $null -ne $_ })
    $script:catalogAllResults = @($newItems + $existing)
    $script:catalogWorkResults = @($newItems + @($script:catalogWorkResults | Where-Object { $null -ne $_ }))
    $script:catalogRecommendations = $null
    $script:lastCatalogSelectionKey = Get-CatalogSelectionKey -Item $newItems[0]

    Apply-CatalogView
    Set-UpdatesStatusText -Message ('Lokales Update hinzugefügt: {0}' -f [string]$newItems[0].Title)
    if ($script:ctx -and $script:ctx.Page) {
        Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesFooterHint' -Value ('Lokale Update-Datei bereit. Du kannst sie jetzt in den ausgewählten Mount oder in alle Mounts integrieren.')
    }
}

function Get-CurrentFilterMode {
    if (-not $script:ctx -or -not $script:ctx.Page) { return 'Recommended' }

    $cmb = Find-Ui -Root $script:ctx.Page -Name 'CmbUpdatesFilterMode'
    if (-not $cmb) { return 'Recommended' }

    switch ([int]$cmb.SelectedIndex) {
        1 { return 'All' }
        2 { return 'Packages' }
        default { return 'Recommended' }
    }
}

function Test-CatalogItemMatchesFilter {
    param(
        $Item,
        [string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) { return $true }

    $needle = $FilterText.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($needle)) { return $true }

    foreach ($field in @(
        [string]$Item.Title,
        [string]$Item.KB,
        [string]$Item.Kind,
        [string]$Item.Version,
        [string]$Item.Classification,
        [string]$Item.Products,
        [string]$Item.Query
    )) {
        if (-not [string]::IsNullOrWhiteSpace($field)) {
            if ($field.ToLowerInvariant().Contains($needle)) {
                return $true
            }
        }
    }

    return $false
}

function Update-RecommendationUi {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $rec = $script:catalogRecommendations

    if ($null -eq $rec) {
        Set-UiText -Root $page -Name 'TxtRecommendedLCU'        -Value '-'
        Set-UiText -Root $page -Name 'TxtRecommendedSSU'        -Value '-'
        Set-UiText -Root $page -Name 'TxtRecommendedDotNet'     -Value '-'
        Set-UiText -Root $page -Name 'TxtRecommendationSummary' -Value 'Noch keine Catalog-Suche ausgefuehrt.'
        return
    }

    Set-UiText -Root $page -Name 'TxtRecommendedLCU'    -Value (Format-CatalogItemLine -Item $rec.RecommendedLCU)
    Set-UiText -Root $page -Name 'TxtRecommendedSSU'    -Value (Format-CatalogItemLine -Item $rec.RecommendedSSU)
    Set-UiText -Root $page -Name 'TxtRecommendedDotNet' -Value (Format-CatalogItemLine -Item $rec.RecommendedDotNet)

    $summary = 'Gesamt: {0} | LCU: {1} | SSU: {2} | .NET: {3} | Preview: {4}' -f `
        $rec.TotalCount,
        $rec.LCUCount,
        $rec.SSUCount,
        $rec.DotNetCount,
        $rec.PreviewCount

    Set-UiText -Root $page -Name 'TxtRecommendationSummary' -Value $summary
}

function Apply-CatalogView {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $mode = Get-CurrentFilterMode
    $txtFilter = Find-Ui -Root $page -Name 'TxtUpdatesFilterText'
    $filterText = if ($txtFilter) { [string]$txtFilter.Text } else { '' }

    $source = switch ($mode) {
        'All' {
            @($script:catalogAllResults)
        }
        'Packages' {
            @(
                $script:catalogAllResults | Where-Object {
                    $kind = [string]$_.Kind
                    $class = [string]$_.Classification
                    ($kind -in @('LCU','SSU','DotNet','Preview')) -or ($class -match 'Update')
                }
            )
        }
        default {
            @($script:catalogWorkResults)
        }
    }

    $visible = @(
        $source | Where-Object {
            Test-CatalogItemMatchesFilter -Item $_ -FilterText $filterText
        }
    )
    $script:catalogVisibleResults = $visible

    $grid = Find-Ui -Root $page -Name 'GridCatalogResults'
    if ($grid) {
        $selectedKey = $script:lastCatalogSelectionKey

        $grid.ItemsSource = $null
        $grid.ItemsSource = $visible

        $selectedItem = $null
        if (-not [string]::IsNullOrWhiteSpace($selectedKey)) {
            $selectedItem = $visible | Where-Object {
                (Get-CatalogSelectionKey -Item $_) -eq $selectedKey
            } | Select-Object -First 1
        }

        if (-not $selectedItem -and $visible.Count -gt 0) {
            $selectedItem = $visible[0]
        }

        $grid.SelectedItem = $selectedItem
        $grid.Items.Refresh()
    }

    $localKbCount = if ($null -ne $script:updateContext) { @($script:updateContext.InstalledKBs).Count } else { 0 }
    $countText = 'Treffer: {0} | Lokal: {1}' -f $visible.Count, $localKbCount
    Set-UiText -Root $page -Name 'TxtCatalogResultsCount' -Value $countText

    $packageCount = if ($null -ne $script:updateContext) { @($script:updateContext.Packages).Count } else { 0 }
    $hintText = 'Ansicht: {0} | Pakete: {1} | Treffer: {2}' -f $mode, $packageCount, $visible.Count
    Set-UiText -Root $page -Name 'TxtUpdatesFilterHint' -Value $hintText

    try {
        Write-Log -Level INFO -Message ('Catalog View: Mode={0}; All={1}; Work={2}; Visible={3}' -f `
            $mode,
            @($script:catalogAllResults).Count,
            @($script:catalogWorkResults).Count,
            $visible.Count)
    } catch {}

    Update-RecommendationUi
    Update-SelectedCatalogDetails
}

function Export-CatalogResultsCsv {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }
    if ($script:isBusy) { return }

    $items = @($script:catalogVisibleResults)
    if ($items.Count -le 0) {
        Show-UiInfo -Message 'Aktuell sind keine sichtbaren Catalog-Treffer zum Exportieren vorhanden.' -Title 'Catalog Export'
        return
    }

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'CSV (*.csv)|*.csv|Alle Dateien (*.*)|*.*'
    $dlg.FileName = ('catalog_results_{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    $dlg.OverwritePrompt = $true

    $ok = $dlg.ShowDialog()
    if ($ok -ne $true) { return }

    $dest = [string]$dlg.FileName
    if ([string]::IsNullOrWhiteSpace($dest)) { return }

    $mountDir = $null
    try { $mountDir = [string]$script:updateContext.MountDir } catch {}

    $rows = @(
        foreach ($item in $items) {
            [pscustomobject]@{
                MountDir       = $mountDir
                KB             = [string]$item.KB
                Kind           = [string]$item.Kind
                LastUpdated    = [string]$item.LastUpdated
                Version        = [string]$item.Version
                Classification = [string]$item.Classification
                Products       = [string]$item.Products
                Query          = [string]$item.Query
                Title          = [string]$item.Title
                UpdateId       = [string]$item.UpdateId
            }
        }
    )

    try {
        $dir = Split-Path -LiteralPath $dest -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }

        $rows | Export-Csv -LiteralPath $dest -Delimiter ';' -NoTypeInformation -Encoding UTF8
        Set-UpdatesStatusText -Message ('Catalog CSV exportiert: {0}' -f $dest)
    } catch {
        Show-UiError -Message $_.Exception.Message -Title 'Catalog Export'
    }
}
