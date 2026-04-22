function Get-CatalogInstalledBaseline {
    [CmdletBinding()]
    param(
        [string]$CurrentBuildVersion,
        [string[]]$InstalledKBs
    )

    $installedSet = @{}
    foreach ($kb in @($InstalledKBs)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$kb)) {
            $installedSet[[string]$kb.ToUpperInvariant()] = $true
        }
    }

    $baselineVersion = ConvertTo-VersionSafely -Value ([string]$CurrentBuildVersion)
    $baselineBranch  = ''
    try {
        $baselineBranch = Get-CatalogVersionBranch -Value ([string]$CurrentBuildVersion)
    } catch {
        $baselineBranch = ''
    }

    return [pscustomobject]@{
        InstalledKbSet = $installedSet
        CurrentBuildVersionText = [string]$CurrentBuildVersion
        CurrentBuildVersionObj  = $baselineVersion
        CurrentBuildBranch      = $baselineBranch
    }
}

function Test-CatalogItemInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)]$Baseline
    )

    $installedByKb = $false
    $installedByVersion = $false

    $kb = ''
    try { $kb = [string]$Item.KB } catch {}

    if (-not [string]::IsNullOrWhiteSpace($kb)) {
        $installedByKb = $Baseline.InstalledKbSet.ContainsKey($kb.ToUpperInvariant())
    }

    if (-not $installedByKb) {
        $kind = ''
        try { $kind = [string]$Item.Kind } catch {}

        if ($kind -in @('LCU', 'Preview', 'SecurityUpdate')) {
            $candidateVersion = ConvertTo-VersionSafely -Value ([string]$Item.Version)
            if ($null -ne $candidateVersion -and $null -ne $Baseline.CurrentBuildVersionObj) {
                $candidateBranch = ''
                try {
                    $candidateBranch = Get-CatalogVersionBranch -Value ([string]$Item.Version)
                } catch {
                    $candidateBranch = ''
                }

                if (
                    -not [string]::IsNullOrWhiteSpace($candidateBranch) -and
                    -not [string]::IsNullOrWhiteSpace($Baseline.CurrentBuildBranch) -and
                    ($candidateBranch -eq $Baseline.CurrentBuildBranch) -and
                    ($candidateVersion -le $Baseline.CurrentBuildVersionObj)
                ) {
                    $installedByVersion = $true
                }
            }
        }
    }

    return [pscustomobject]@{
        IsInstalledByKb      = $installedByKb
        IsInstalledByVersion = $installedByVersion
        IsInstalled          = ($installedByKb -or $installedByVersion)
    }
}

function Search-WindowsUpdateCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Queries,
        [string[]]$InstalledKBs,
        [string]$ProductFamily,
        [string]$Architecture,
        [string]$BuildBranch,
        [string]$CurrentBuildVersion
    )

    $queryList = @($Queries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($queryList.Count -eq 0) {
        throw "Search-WindowsUpdateCatalog hat keine verwertbaren Queries erhalten."
    }

    $baseline = Get-CatalogInstalledBaseline -CurrentBuildVersion $CurrentBuildVersion -InstalledKBs $InstalledKBs

    try {
        Write-Log -Level INFO -Message ("Catalog: Installed baseline | CurrentBuildVersion={0} | CurrentBuildBranch={1} | InstalledKBs={2}" -f `
            $(if ($baseline.CurrentBuildVersionText) { $baseline.CurrentBuildVersionText } else { '-' }),
            $(if ($baseline.CurrentBuildBranch) { $baseline.CurrentBuildBranch } else { '-' }),
            $baseline.InstalledKbSet.Keys.Count)
    } catch {}

    $results = @()
    $seen = @{}

    foreach ($query in $queryList) {
        $url  = Get-CatalogSearchUrl -Query $query
        $resp = Invoke-CatalogWebRequest -Url $url
        $html = [string]$resp.Content

        try {
            Write-Log -Level INFO -Message ("Catalog: HtmlLength fuer '{0}' = {1}" -f $query, $html.Length)
        } catch {}

        $null = Write-CatalogDebugFile -Prefix ("catalog_html_" + $query) -Content $html

        try {
            $pageTitle = $null
            $mTitle = [regex]::Match(
                $html,
                '<title[^>]*>(?<t>.*?)</title>',
                [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )

            if ($mTitle.Success) {
                $pageTitle = Normalize-CatalogText -Text ([string]$mTitle.Groups['t'].Value)
            }

            Write-Log -Level INFO -Message ("Catalog: PageTitle fuer '{0}' = {1}" -f $query, $(if ($pageTitle) { $pageTitle } else { '-' }))
        } catch {}

        try {
            if ($html -notmatch 'We did not find any results for') {
                Write-Log -Level WARN -Message ("Catalog: Keine sichtbare Updates-Zusammenfassung fuer '{0}' gefunden." -f $query)
            }
        } catch {}

        $rows = @(Get-CatalogRowBlocks -Html $html)

        try {
            Write-Log -Level INFO -Message ("Catalog: HTML-TR-Anzahl fuer '{0}' = {1}" -f $query, $rows.Count)
        } catch {}

        $parsedForQuery = @()
        $rawRelevantCount = 0
        $suppressedInstalledCount = 0

        foreach ($row in $rows) {
            $updateId = Get-UpdateIdFromRow -RowHtml $row
            if ([string]::IsNullOrWhiteSpace($updateId)) { continue }

            $title = Get-TitleFromRow -RowHtml $row
            if ([string]::IsNullOrWhiteSpace($title)) { continue }

            $cells = @(Get-CellTextsFromRow -RowHtml $row)

            $products            = if ($cells.Count -ge 2) { $cells[1] } else { $null }
            $classification      = if ($cells.Count -ge 3) { $cells[2] } else { $null }
            $lastUpdated         = if ($cells.Count -ge 4) { $cells[3] } else { $null }
            $catalogVersionLabel = if ($cells.Count -ge 5) { $cells[4] } else { $null }
            $size                = if ($cells.Count -ge 6) { $cells[5] } else { $null }

            $kb = Get-KBFromTitle -Title $title

            $titleVersion = Get-VersionFromTitle -Title $title
            $version = $titleVersion
            if ([string]::IsNullOrWhiteSpace($version)) {
                $version = $catalogVersionLabel
            }

            $kind = Get-CatalogUpdateKind -Title $title -Classification $classification
            $isPreview = ($kind -eq 'Preview')

            $item = [pscustomobject]@{
                Query               = $query
                UpdateId            = $updateId
                Title               = $title
                KB                  = $kb
                Products            = $products
                Classification      = $classification
                LastUpdated         = $lastUpdated
                Version             = $version
                CatalogVersionLabel = $catalogVersionLabel
                Size                = $size
                Kind                = $kind
                IsPreview           = $isPreview
                IsInstalled         = $false
                IsInstalledByKb     = $false
                IsInstalledByVersion= $false
            }

            $installedState = Test-CatalogItemInstalled -Item $item -Baseline $baseline
            $item.IsInstalled = [bool]$installedState.IsInstalled
            $item.IsInstalledByKb = [bool]$installedState.IsInstalledByKb
            $item.IsInstalledByVersion = [bool]$installedState.IsInstalledByVersion

            $parsedForQuery += $item

            if (-not (Test-CatalogResultRelevant -Item $item -ProductFamily $ProductFamily -Architecture $Architecture -BuildBranch $BuildBranch)) {
                continue
            }

            $rawRelevantCount++

            $dedupeKey = if ($updateId) {
                $updateId.ToLowerInvariant()
            } else {
                ($title + '|' + $kb + '|' + $version).ToLowerInvariant()
            }

            if ($seen.ContainsKey($dedupeKey)) { continue }
            $seen[$dedupeKey] = $true

            if ($item.IsInstalled) {
                $suppressedInstalledCount++
                continue
            }

            $results += $item
        }

        try {
            Write-Log -Level INFO -Message ("Catalog: Query '{0}' -> ParsedBeforeArchFilter={1}" -f $query, $parsedForQuery.Count)
            Write-Log -Level INFO -Message ("Catalog: Query '{0}' -> Roh-Treffer={1}" -f $query, $rawRelevantCount)
            Write-Log -Level INFO -Message ("Catalog: Query '{0}' -> UnterdruecktAlsInstalliert={1}" -f $query, $suppressedInstalledCount)
        } catch {}

        $null = Write-CatalogDebugJson -Prefix ("catalog_parse_{0}_parsed" -f $query) -Object $parsedForQuery
        $null = Write-CatalogDebugJson -Prefix ("catalog_parse_{0}_summary" -f $query) -Object ([pscustomobject]@{
            Query                    = $query
            ParsedCount              = $parsedForQuery.Count
            RelevantCount            = $rawRelevantCount
            SuppressedInstalledCount = $suppressedInstalledCount
        })
        $null = Write-CatalogDebugJson -Prefix ("catalog_parse_{0}_rows" -f $query) -Object $rows
    }

    $ordered = @(
        $results | Sort-Object -Property @(
            @{ Expression = {
                $d = ConvertFrom-CatalogDateSafely -Value ([string]$_.LastUpdated)
                if ($null -ne $d) { $d } else { [datetime]::MinValue }
            }; Descending = $true },
            @{ Expression = {
                $v = ConvertTo-VersionSafely -Value ([string]$_.Version)
                if ($null -ne $v) { $v } else { [version]'0.0.0.0' }
            }; Descending = $true },
            @{ Expression = { [string]$_.Title }; Descending = $false }
        )
    )

    try {
        Write-Log -Level INFO -Message ("Catalog: Finale Treffer gesamt: {0}" -f $ordered.Count)
    } catch {}

    return @($ordered)
}

function Search-WindowsUpdateCatalogBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Queries,
        [string[]]$InstalledKBs,
        [string]$ProductFamily,
        [string]$Architecture,
        [string]$BuildBranch,
        [string]$VersionLabel,
        [string]$CurrentBuildVersion,
        [string]$CurrentLcuVersion,
        [string]$CurrentSsuVersion,
        [string]$CurrentDotNetVersion
    )

    $queryList = @($Queries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($queryList.Count -eq 0) {
        throw "Search-WindowsUpdateCatalogBatch hat keine Queries erhalten."
    }

    if ([string]::IsNullOrWhiteSpace($VersionLabel)) {
        foreach ($q in $queryList) {
            $detected = Get-CatalogVersionLabelFromText -Text ([string]$q)
            if (-not [string]::IsNullOrWhiteSpace($detected)) {
                $VersionLabel = $detected
                break
            }
        }
    }

    $allResults = @(Search-WindowsUpdateCatalog `
        -Queries $queryList `
        -InstalledKBs $InstalledKBs `
        -ProductFamily $ProductFamily `
        -Architecture $Architecture `
        -BuildBranch $BuildBranch `
        -CurrentBuildVersion $CurrentBuildVersion)

    if (-not [string]::IsNullOrWhiteSpace($Architecture) -or
        -not [string]::IsNullOrWhiteSpace($VersionLabel) -or
        -not [string]::IsNullOrWhiteSpace($BuildBranch) -or
        -not [string]::IsNullOrWhiteSpace($ProductFamily)) {

        try {
            Write-Log -Level INFO -Message ("Catalog: TargetFilter Product={0}; Arch={1}; Version={2}; Build={3}" -f `
                $(if ($ProductFamily) { $ProductFamily } else { '-' }),
                $(if ($Architecture) { $Architecture } else { '-' }),
                $(if ($VersionLabel) { $VersionLabel } else { '-' }),
                $(if ($BuildBranch) { $BuildBranch } else { '-' }))
        } catch {}

        $before = $allResults.Count
        $filtered = @(
            $allResults | Where-Object {
                Test-CatalogItemTargetMatch `
                    -Item $_ `
                    -Architecture $Architecture `
                    -VersionLabel $VersionLabel `
                    -BuildBranch $BuildBranch `
                    -ProductFamily $ProductFamily
            }
        )

        if ($filtered.Count -gt 0) {
            $allResults = $filtered
        }

        try {
            Write-Log -Level INFO -Message ("Catalog: TargetFilter before={0}; after={1}" -f $before, $allResults.Count)
        } catch {}
    }

    $workResults = @(Get-RecommendedCatalogSubset `
        -Items $allResults `
        -MaxItems 10 `
        -CurrentLcuVersion $CurrentLcuVersion `
        -CurrentSsuVersion $CurrentSsuVersion `
        -CurrentDotNetVersion $CurrentDotNetVersion)

    $recommendations = Get-CatalogRecommendations `
        -Items $allResults `
        -CurrentLcuVersion $CurrentLcuVersion `
        -CurrentSsuVersion $CurrentSsuVersion `
        -CurrentDotNetVersion $CurrentDotNetVersion

    try {
        Write-Log -Level INFO -Message ("Catalog: AllResults={0}; WorkResults={1}" -f $allResults.Count, $workResults.Count)
    } catch {}

    $resultObject = [pscustomobject]@{
        AllResults        = @($allResults)
        WorkResults       = @($workResults)
        Recommendations   = $recommendations
        VersionLabel      = $VersionLabel
        Architecture      = $Architecture
        BuildBranch       = $BuildBranch
        ProductFamily     = $ProductFamily
        InstalledKBs      = @($InstalledKBs)
        CurrentBuildVersion = $CurrentBuildVersion
    }

    $null = Write-CatalogDebugJson -Prefix "catalog_batch_results" -Object $resultObject

    return $resultObject
}