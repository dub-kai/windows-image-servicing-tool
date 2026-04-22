function Get-WindowsReleaseLabelFromBuild {
    param(
        [string]$ProductFamily,
        [string]$BuildBranch
    )

    $pf = [string]$ProductFamily
    $build = [string]$BuildBranch

    if ($pf -match 'Windows 11') {
        switch ($build) {
            '22000' { return '21H2' }
            '22621' { return '22H2' }
            '22631' { return '23H2' }
            '26100' { return '24H2' }
            '26200' { return '25H2' }
        }
    }

    if ($pf -match 'Windows 10') {
        switch ($build) {
            '19041' { return '2004' }
            '19042' { return '20H2' }
            '19043' { return '21H1' }
            '19044' { return '21H2' }
            '19045' { return '22H2' }
        }
    }

    return ''
}

function Get-ArchitectureCatalogLabel {
    param([string]$Architecture)

    switch -Regex ([string]$Architecture) {
        '^x64$'   { return 'x64-based Systems' }
        '^arm64$' { return 'arm64-based Systems' }
        '^x86$'   { return 'x86-based Systems' }
        default   { return $Architecture }
    }
}

function Add-CatalogQueryIfMissing {
    param(
        [Parameter(Mandatory)]$List,
        [string]$Query
    )

    if ([string]::IsNullOrWhiteSpace($Query)) { return }

    $value = [string]$Query.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return }

    if (-not ($List.Contains($value))) {
        $List.Add($value) | Out-Null
    }
}

function Get-SafeObjectPropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }

    return $prop.Value
}

function ConvertTo-ComparableBuildVersion {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $text = [string]$Value.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $match = [regex]::Match($text, '(?<v>\d+(?:\.\d+){1,3})')
    if (-not $match.Success) { return $null }

    $raw = [string]$match.Groups['v'].Value
    $parts = @($raw.Split('.') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($parts.Count -le 0) { return $null }
    if ($parts.Count -gt 4) { $parts = @($parts[0..3]) }

    try {
        return [version]($parts -join '.')
    }
    catch {
        return $null
    }
}

function Get-BuildBranchFromVersionText {
    param([string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) { return '' }

    $m = [regex]::Match([string]$VersionText, '^(?:10\.0\.)?(?<build>\d{4,5})(?:\.|$)')
    if ($m.Success) {
        return [string]$m.Groups['build'].Value
    }

    return ''
}

function Get-PackageVersionString {
    param(
        $Package
    )

    if ($null -eq $Package) { return $null }

    $candidates = @(
        (Get-SafeObjectPropertyValue -Object $Package -Name 'PackageIdentity'),
        (Get-SafeObjectPropertyValue -Object $Package -Name 'Identity'),
        (Get-SafeObjectPropertyValue -Object $Package -Name 'Version'),
        (Get-SafeObjectPropertyValue -Object $Package -Name 'Name')
    ) | ForEach-Object {
        if ($null -ne $_) { [string]$_ } else { $null }
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        $mRollup = [regex]::Match(
            $candidate,
            'Package_for_(?:RollupFix|KB\d+|ServicingStack_[0-9]+)~[^~]+~[^~]+~[^~]*~~(?<build>\d{4,5})\.(?<rev>\d{1,5})\.\d+\.\d+',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($mRollup.Success) {
            return ('{0}.{1}' -f $mRollup.Groups['build'].Value, $mRollup.Groups['rev'].Value)
        }

        $mOsPackage = [regex]::Match(
            $candidate,
            '~~10\.0\.(?<build>\d{4,5})\.(?<rev>\d{1,5})\b',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($mOsPackage.Success) {
            return ('{0}.{1}' -f $mOsPackage.Groups['build'].Value, $mOsPackage.Groups['rev'].Value)
        }

        $mGenericBuild = [regex]::Match(
            $candidate,
            '~~(?<build>\d{4,5})\.(?<rev>\d{1,5})\.\d+\.\d+',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($mGenericBuild.Success) {
            return ('{0}.{1}' -f $mGenericBuild.Groups['build'].Value, $mGenericBuild.Groups['rev'].Value)
        }

        $m4 = [regex]::Match($candidate, '\b(?<v>\d+\.\d+\.\d+\.\d+)\b')
        if ($m4.Success) {
            $parts = ([string]$m4.Groups['v'].Value).Split('.')
            if ($parts.Count -ge 2) {
                return ('{0}.{1}' -f $parts[0], $parts[1])
            }
            return [string]$m4.Groups['v'].Value
        }

        $m3 = [regex]::Match($candidate, '\b(?<v>\d+\.\d+\.\d+)\b')
        if ($m3.Success) {
            $parts = ([string]$m3.Groups['v'].Value).Split('.')
            if ($parts.Count -ge 2) {
                return ('{0}.{1}' -f $parts[0], $parts[1])
            }
            return [string]$m3.Groups['v'].Value
        }
    }

    return $null
}

function Get-CurrentImageBuildVersion {
    param(
        [AllowEmptyCollection()][object[]]$Packages = @(),
        $BestLCU,
        $BestSSU
    )

    $lcuVersion = Get-PackageVersionString -Package $BestLCU
    if (-not [string]::IsNullOrWhiteSpace($lcuVersion)) {
        return $lcuVersion
    }

    $ssuVersion = Get-PackageVersionString -Package $BestSSU
    if (-not [string]::IsNullOrWhiteSpace($ssuVersion)) {
        return $ssuVersion
    }

    $ranked = foreach ($pkg in @($Packages)) {
        $state = [string](Get-SafeObjectPropertyValue -Object $pkg -Name 'State')
        if ($state -notmatch 'Installed' -and $state -notmatch 'Superseded') { continue }

        $versionText = Get-PackageVersionString -Package $pkg
        $versionObj  = ConvertTo-ComparableBuildVersion -Value $versionText
        if ($null -eq $versionObj) { continue }

        [pscustomobject]@{
            VersionText = $versionText
            VersionObj  = $versionObj
        }
    }

    $ordered = @($ranked | Sort-Object VersionObj -Descending)
    if ($ordered.Count -gt 0) {
        return [string]$ordered[0].VersionText
    }

    return ''
}

function Normalize-ReleaseLabel {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

    $m = [regex]::Match($Value.ToUpperInvariant(), '^\d{2}H[12]$')
    if ($m.Success) {
        return $m.Value
    }

    return ''
}

function Get-PrimaryReleaseLabelsForContext {
    param(
        [string]$ProductFamily,
        [string]$BuildBranch,
        [string]$DisplayVersion
    )

    $labels = New-Object System.Collections.Generic.List[string]

    $display = Normalize-ReleaseLabel -Value $DisplayVersion
    if (-not [string]::IsNullOrWhiteSpace($display)) {
        Add-CatalogQueryIfMissing -List ([object]$labels) -Query $display
    }

    $primary = Get-WindowsReleaseLabelFromBuild -ProductFamily $ProductFamily -BuildBranch $BuildBranch
    if (-not [string]::IsNullOrWhiteSpace($primary)) {
        Add-CatalogQueryIfMissing -List ([object]$labels) -Query $primary
    }

    if ([string]$ProductFamily -match 'Windows 11') {
        if ([string]$BuildBranch -in @('26100', '26200')) {
            Add-CatalogQueryIfMissing -List ([object]$labels) -Query '24H2'
            Add-CatalogQueryIfMissing -List ([object]$labels) -Query '25H2'
        }
    }

    return @($labels)
}

function Get-MicrosoftCatalogProductPhrase {
    param(
        [string]$ProductFamily,
        [string]$ReleaseLabel
    )

    if ([string]::IsNullOrWhiteSpace($ProductFamily) -or [string]::IsNullOrWhiteSpace($ReleaseLabel)) {
        return $null
    }

    switch -Regex ([string]$ProductFamily) {
        'Windows 11' { return ("Microsoft Windows 11, version {0}" -f $ReleaseLabel) }
        'Windows 10' { return ("Microsoft Windows 10, version {0}" -f $ReleaseLabel) }
        default      { return $null }
    }
}

function Add-CatalogQueriesForReleaseLabel {
    param(
        [Parameter(Mandatory)]$List,
        [string]$ProductFamily,
        [string]$ReleaseLabel,
        [string]$ArchitectureCatalogLabel,
        [string]$BuildBranch
    )

    if ([string]::IsNullOrWhiteSpace($ReleaseLabel)) { return }

    $msPhrase = Get-MicrosoftCatalogProductPhrase -ProductFamily $ProductFamily -ReleaseLabel $ReleaseLabel

    Add-CatalogQueryIfMissing -List ([object]$List) -Query ("Cumulative Update for {0} Version {1} for {2}" -f $ProductFamily, $ReleaseLabel, $ArchitectureCatalogLabel)
    Add-CatalogQueryIfMissing -List ([object]$List) -Query ("Cumulative Update Preview for {0} Version {1} for {2}" -f $ProductFamily, $ReleaseLabel, $ArchitectureCatalogLabel)
    Add-CatalogQueryIfMissing -List ([object]$List) -Query ("Servicing Stack Update for {0} Version {1} for {2}" -f $ProductFamily, $ReleaseLabel, $ArchitectureCatalogLabel)

    Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} Version {1} for {2}" -f $ProductFamily, $ReleaseLabel, $ArchitectureCatalogLabel)
    Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} Version {1}" -f $ProductFamily, $ReleaseLabel)

    Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} cumulative update {1}" -f $ReleaseLabel, $ArchitectureCatalogLabel)
    Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} cumulative update preview {1}" -f $ReleaseLabel, $ArchitectureCatalogLabel)

    if (-not [string]::IsNullOrWhiteSpace($msPhrase)) {
        Add-CatalogQueryIfMissing -List ([object]$List) -Query ("Cumulative Update for {0}" -f $msPhrase)
        Add-CatalogQueryIfMissing -List ([object]$List) -Query ("Cumulative Update Preview for {0}" -f $msPhrase)
        Add-CatalogQueryIfMissing -List ([object]$List) -Query ("Servicing Stack Update for {0}" -f $msPhrase)
    }

    if (-not [string]::IsNullOrWhiteSpace($BuildBranch)) {
        Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} {1}" -f $ReleaseLabel, $BuildBranch)
    }

    $now = Get-Date
    foreach ($offset in @(0, -1, -2)) {
        $ym = $now.AddMonths($offset).ToString('yyyy-MM')

        Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} Cumulative Update for {1} Version {2} for {3}" -f $ym, $ProductFamily, $ReleaseLabel, $ArchitectureCatalogLabel)
        Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} Cumulative Update Preview for {1} Version {2} for {3}" -f $ym, $ProductFamily, $ReleaseLabel, $ArchitectureCatalogLabel)

        if (-not [string]::IsNullOrWhiteSpace($msPhrase)) {
            Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} Cumulative Update for {1}" -f $ym, $msPhrase)
            Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} Cumulative Update Preview for {1}" -f $ym, $msPhrase)
        }

        Add-CatalogQueryIfMissing -List ([object]$List) -Query ("{0} {1} {2}" -f $ym, $ReleaseLabel, $BuildBranch)
    }
}

function Get-CatalogQueriesForContext {
    param(
        [string]$ProductFamily,
        [string]$Architecture,
        [string]$BuildBranch,
        [string]$DisplayVersion
    )

    $queries = New-Object System.Collections.Generic.List[string]

    $pf = if ([string]::IsNullOrWhiteSpace($ProductFamily)) { 'Windows' } else { $ProductFamily }
    $arch = if ([string]::IsNullOrWhiteSpace($Architecture)) { 'x64' } else { $Architecture }
    $archCatalog = Get-ArchitectureCatalogLabel -Architecture $arch
    $build = [string]$BuildBranch

    $releaseLabels = @(Get-PrimaryReleaseLabelsForContext -ProductFamily $pf -BuildBranch $build -DisplayVersion $DisplayVersion)

    foreach ($label in $releaseLabels) {
        Add-CatalogQueriesForReleaseLabel `
            -List ([object]$queries) `
            -ProductFamily $pf `
            -ReleaseLabel $label `
            -ArchitectureCatalogLabel $archCatalog `
            -BuildBranch $build
    }

    if (-not [string]::IsNullOrWhiteSpace($build)) {
        Add-CatalogQueryIfMissing -List ([object]$queries) -Query ("{0} cumulative update" -f $build)
        Add-CatalogQueryIfMissing -List ([object]$queries) -Query ("{0} cumulative update preview" -f $build)
        Add-CatalogQueryIfMissing -List ([object]$queries) -Query ("Windows 11 {0}" -f $build)
    }

    Add-CatalogQueryIfMissing -List ([object]$queries) -Query ("Cumulative Update for {0}" -f $pf)
    Add-CatalogQueryIfMissing -List ([object]$queries) -Query ("Cumulative Update Preview for {0}" -f $pf)
    Add-CatalogQueryIfMissing -List ([object]$queries) -Query $pf

    return @($queries)
}

function Get-MountedImageUpdateContext {
    param(
        [Parameter(Mandatory)][string]$MountDir
    )

    $meta = Get-MountedWimMeta -MountDir $MountDir
    $packages = @(Get-MountedImagePackagesInternal -MountDir $MountDir)

    if (-not $packages -or $packages.Count -eq 0) {
        Write-UpdateLog -Level WARN -Message "Updates: Paketliste ist leer. Es wird trotzdem ein Kontextobjekt erzeugt."
    }

    $edition = Get-CurrentEditionSafe -MountDir $MountDir
    $offlineInfo = Get-OfflineWindowsCurrentVersionInfo -MountDir $MountDir
    $installedKbs = @(Get-InstalledKBs -Packages $packages)

    $bestLCU = Get-BestInstalledPackageByKind -Packages $packages -Kind 'LCU'
    $bestSSU = Get-BestInstalledPackageByKind -Packages $packages -Kind 'SSU'
    $bestDotNet = Get-BestInstalledPackageByKind -Packages $packages -Kind 'DotNet'

    $currentLcuVersion = Get-PackageVersionString -Package $bestLCU
    $currentSsuVersion = Get-PackageVersionString -Package $bestSSU
    $currentDotNetVersion = Get-PackageVersionString -Package $bestDotNet

    $servicingBuildVersion = Get-CurrentImageBuildVersion -Packages $packages -BestLCU $bestLCU -BestSSU $bestSSU
    $servicingBuildBranch  = Get-BuildBranchFromVersionText -VersionText $servicingBuildVersion
    if ([string]::IsNullOrWhiteSpace($servicingBuildBranch)) {
        $servicingBuildBranch = Get-BuildBranchFromPackages -Packages $packages
    }

    $osBuildVersion = Get-OfflineWindowsFullBuildVersion -Info $offlineInfo
    $osBuildBranch  = Get-OfflineWindowsBuildBranch -Info $offlineInfo
    $displayVersion = Get-OfflineWindowsDisplayVersion -Info $offlineInfo

    $productFamily = Get-ProductFamilyFromOfflineInfoOrPath -OfflineInfo $offlineInfo -ImageFile $meta.ImageFile
    $arch = Get-ArchitectureFromPackagesAndPath -Packages $packages -ImageFile $meta.ImageFile

    $effectiveBuildBranch = if (-not [string]::IsNullOrWhiteSpace($osBuildBranch)) { $osBuildBranch } else { $servicingBuildBranch }
    $effectiveBuildVersion = if (-not [string]::IsNullOrWhiteSpace($osBuildVersion)) { $osBuildVersion } else { $servicingBuildVersion }

    $releaseLabels = @(Get-PrimaryReleaseLabelsForContext -ProductFamily $productFamily -BuildBranch $effectiveBuildBranch -DisplayVersion $displayVersion)
    $queries = Get-CatalogQueriesForContext -ProductFamily $productFamily -Architecture $arch -BuildBranch $effectiveBuildBranch -DisplayVersion $displayVersion

    return [pscustomobject]@{
        MountDir              = $meta.MountDir
        ReadWrite             = $meta.ReadWrite
        ImageFile             = $meta.ImageFile
        ImageIndex            = $meta.ImageIndex
        Edition               = $edition

        Packages              = @($packages)
        InstalledKBs          = @($installedKbs)
        InstalledKBCount      = @($installedKbs).Count

        CurrentLCUVersion     = if (-not [string]::IsNullOrWhiteSpace($currentLcuVersion)) { $currentLcuVersion } elseif ($bestLCU) { [string](Get-SafeObjectPropertyValue -Object $bestLCU -Name 'PackageIdentity') } else { '-' }
        CurrentSSUVersion     = if (-not [string]::IsNullOrWhiteSpace($currentSsuVersion)) { $currentSsuVersion } elseif ($bestSSU) { [string](Get-SafeObjectPropertyValue -Object $bestSSU -Name 'PackageIdentity') } else { '-' }
        CurrentDotNetVersion  = if (-not [string]::IsNullOrWhiteSpace($currentDotNetVersion)) { $currentDotNetVersion } elseif ($bestDotNet) { [string](Get-SafeObjectPropertyValue -Object $bestDotNet -Name 'PackageIdentity') } else { '-' }
        CurrentBuildVersion   = if (-not [string]::IsNullOrWhiteSpace($effectiveBuildVersion)) { $effectiveBuildVersion } else { '-' }

        OsBuildVersion        = if (-not [string]::IsNullOrWhiteSpace($osBuildVersion)) { $osBuildVersion } else { '-' }
        OsBuildBranch         = if (-not [string]::IsNullOrWhiteSpace($osBuildBranch)) { $osBuildBranch } else { '-' }
        ServicingBuildVersion = if (-not [string]::IsNullOrWhiteSpace($servicingBuildVersion)) { $servicingBuildVersion } else { '-' }
        ServicingBuildBranch  = if (-not [string]::IsNullOrWhiteSpace($servicingBuildBranch)) { $servicingBuildBranch } else { '-' }

        ProductName           = if ($offlineInfo) { [string]$offlineInfo.ProductName } else { '' }
        DisplayVersion        = if (-not [string]::IsNullOrWhiteSpace($displayVersion)) { $displayVersion } else { '' }

        ProductFamily         = $productFamily
        Architecture          = $arch
        BuildBranch           = $effectiveBuildBranch
        ReleaseLabels         = @($releaseLabels)
        CatalogQueries        = @($queries)
    }
}