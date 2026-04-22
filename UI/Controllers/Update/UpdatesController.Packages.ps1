function Get-PackagesFilterMode {
    if (-not $script:ctx -or -not $script:ctx.Page) { return 'Important' }

    $cmb = Find-Ui -Root $script:ctx.Page -Name 'CmbUpdatesPackagesMode'
    if (-not $cmb) { return 'Important' }

    switch ([int]$cmb.SelectedIndex) {
        1 { return 'KBOnly' }
        2 { return 'All' }
        default { return 'Important' }
    }
}

function Test-IsImportantPackage {
    param($Package)

    if ($null -eq $Package) { return $false }

    $kb = [string]$Package.KB
    $identity = [string]$Package.PackageIdentity
    $releaseType = [string]$Package.ReleaseType
    $blob = (($kb + ' ' + $identity + ' ' + $releaseType).ToLowerInvariant())

    if (-not [string]::IsNullOrWhiteSpace($kb)) { return $true }

    if ($blob -match 'rollupfix') { return $true }
    if ($blob -match 'servicingstack') { return $true }
    if ($blob -match 'dotnet') { return $true }
    if ($blob -match 'netfx') { return $true }
    if ($blob -match 'cumulative') { return $true }

    return $false
}

function Test-PackageMatchesFilterText {
    param(
        $Package,
        [string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) { return $true }

    $needle = $FilterText.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($needle)) { return $true }

    foreach ($field in @(
        [string]$Package.KB,
        [string]$Package.State,
        [string]$Package.ReleaseType,
        [string]$Package.InstallTime,
        [string]$Package.PackageIdentity
    )) {
        if (-not [string]::IsNullOrWhiteSpace($field)) {
            if ($field.ToLowerInvariant().Contains($needle)) {
                return $true
            }
        }
    }

    return $false
}

function Apply-PackagesView {
    if (-not $script:ctx -or -not $script:ctx.Page) { return }

    $page = $script:ctx.Page
    $mode = Get-PackagesFilterMode
    $txtFilter = Find-Ui -Root $page -Name 'TxtUpdatesPackagesFilter'
    $filterText = if ($txtFilter) { [string]$txtFilter.Text } else { '' }

    $source = switch ($mode) {
        'KBOnly' {
            @($script:allPackages | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.KB) })
        }
        'All' {
            @($script:allPackages)
        }
        default {
            @($script:allPackages | Where-Object { Test-IsImportantPackage -Package $_ })
        }
    }

    $visible = @($source | Where-Object { Test-PackageMatchesFilterText -Package $_ -FilterText $filterText })

    $grid = Find-Ui -Root $page -Name 'GridUpdatesPackages'
    if ($grid) {
        $grid.ItemsSource = $null
        $grid.ItemsSource = $visible
        $grid.Items.Refresh()
    }

    $modeText = switch ($mode) {
        'KBOnly' { 'Nur KB-Pakete' }
        'All'    { 'Alle' }
        default  { 'Wichtige' }
    }

    Set-UiText -Root $page -Name 'TxtUpdatesPackagesCount' -Value ('Pakete: {0} / {1} | Modus: {2}' -f $visible.Count, @($script:allPackages).Count, $modeText)

    try {
        Write-Log -Level INFO -Message ('Packages View: Mode={0}; Visible={1}; Total={2}' -f $modeText, $visible.Count, @($script:allPackages).Count)
    } catch {}
}