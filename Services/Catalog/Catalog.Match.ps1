function Get-CatalogUpdateKind {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Classification
    )

    $text = (($Title + ' ' + $Classification).Trim())

    if ($text -match '\bPreview\b') { return 'Preview' }
    if ($text -match 'Servicing Stack') { return 'SSU' }
    if ($text -match '\.NET' -or $text -match 'Framework') { return 'DotNet' }
    if ($text -match 'Cumulative Update') { return 'LCU' }
    if ($text -match 'Security Update') { return 'SecurityUpdate' }

    return 'Other'
}

function Test-IsServerCatalogItem {
    param($Item)

    if ($null -eq $Item) { return $false }

    $title = [string]$Item.Title
    $products = [string]$Item.Products
    $classification = [string]$Item.Classification
    $hay = ($title + ' ' + $products + ' ' + $classification).ToLowerInvariant()

    if ($hay -match 'windows server') { return $true }
    if ($hay -match 'server operating system') { return $true }
    if ($hay -match 'microsoft server operating system') { return $true }
    if ($hay -match 'server version 24h2') { return $true }
    if ($hay -match 'azure stack hci') { return $true }
    if ($hay -match '\bserver\b') { return $true }

    return $false
}

function Test-IsClientCatalogItemForProduct {
    param(
        [Parameter(Mandatory)]$Item,
        [string]$ProductFamily
    )

    if ($null -eq $Item) { return $false }

    $title = [string]$Item.Title
    $products = [string]$Item.Products
    $classification = [string]$Item.Classification
    $hay = ($title + ' ' + $products + ' ' + $classification)

    if (Test-IsServerCatalogItem -Item $Item) {
        return $false
    }

    switch ($ProductFamily) {
        'Windows 11' {
            if ($hay -match 'Windows\s+11') { return $true }
            if ($hay -match 'Version\s+25H2') { return $true }
            if ($hay -match 'Version\s+24H2') { return $true }
            if ($hay -match 'Version\s+23H2') { return $true }
            if ($hay -match '\b25H2\b') { return $true }
            if ($hay -match '\b24H2\b') { return $true }
            if ($hay -match '\b23H2\b') { return $true }
            return $false
        }
        'Windows 10' {
            if ($hay -match 'Windows\s+10') { return $true }
            if ($hay -match '\b22H2\b') { return $true }
            if ($hay -match '\b21H2\b') { return $true }
            return $false
        }
        default {
            return $true
        }
    }
}

function Test-CatalogResultRelevant {
    param(
        [Parameter(Mandatory)]$Item,
        [string]$ProductFamily,
        [string]$Architecture,
        [string]$BuildBranch
    )

    if (-not [string]::IsNullOrWhiteSpace($ProductFamily)) {
        if (-not (Test-IsClientCatalogItemForProduct -Item $Item -ProductFamily $ProductFamily)) {
            return $false
        }
    }

    $title    = [string]$Item.Title
    $products = [string]$Item.Products
    $class    = [string]$Item.Classification
    $hay      = ($title + ' ' + $products + ' ' + $class)

    if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
        switch ($Architecture.ToLowerInvariant()) {
            'x64' {
                if ($hay -notmatch '\bx64\b' -and $hay -notmatch 'x64-based') { return $false }
            }
            'arm64' {
                if ($hay -notmatch '\barm64\b' -and $hay -notmatch 'arm64-based') { return $false }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($BuildBranch)) {
        if ($title -notmatch [regex]::Escape($BuildBranch) -and
            [string]$Item.Version -notmatch ('^' + [regex]::Escape($BuildBranch) + '(\.|$)')) {
            return $false
        }
    }

    return $true
}

function Get-CatalogVersionLabelFromText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $m = [regex]::Match($Text, '\b(2[0-9]H[12])\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        return $m.Groups[1].Value.ToUpperInvariant()
    }

    return $null
}

function Test-CatalogItemTargetMatch {
    param(
        [Parameter(Mandatory)]$Item,
        [string]$Architecture,
        [string]$VersionLabel,
        [string]$BuildBranch,
        [string]$ProductFamily
    )

    if (-not [string]::IsNullOrWhiteSpace($ProductFamily)) {
        if (-not (Test-IsClientCatalogItemForProduct -Item $Item -ProductFamily $ProductFamily)) {
            return $false
        }
    }

    $title = [string]$Item.Title
    $prod  = [string]$Item.Products
    $hay   = ($title + ' ' + $prod)

    if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
        switch ($Architecture.ToLowerInvariant()) {
            'x64' {
                if ($hay -notmatch '\bx64\b' -and $hay -notmatch 'x64-based') { return $false }
            }
            'arm64' {
                if ($hay -notmatch '\barm64\b' -and $hay -notmatch 'arm64-based') { return $false }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($VersionLabel)) {
        if ($hay -notmatch [regex]::Escape($VersionLabel)) {
            return $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($BuildBranch)) {
        $matchesBuild = $false

        if ($title -match [regex]::Escape($BuildBranch)) {
            $matchesBuild = $true
        }

        if (-not $matchesBuild -and -not [string]::IsNullOrWhiteSpace([string]$Item.Version)) {
            if ([string]$Item.Version -match ('^' + [regex]::Escape($BuildBranch) + '(\.|$)')) {
                $matchesBuild = $true
            }
        }

        if (-not $matchesBuild) {
            return $false
        }
    }

    return $true
}

function Get-CatalogVersionBranch {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

    $text = [string]$Value.Trim()

    $m = [regex]::Match($text, '^(?:10\.0\.)?(?<build>\d{4,5})(?:\.|$)')
    if ($m.Success) {
        return [string]$m.Groups['build'].Value
    }

    return ''
}

function Get-CatalogDominantBuildBranch {
    param(
        [AllowEmptyCollection()][object[]]$Items = @()
    )

    $counts = @{}

    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }

        $branch = Get-CatalogVersionBranch -Value ([string]$item.Version)
        if ([string]::IsNullOrWhiteSpace($branch)) { continue }

        if (-not $counts.ContainsKey($branch)) {
            $counts[$branch] = 0
        }

        $counts[$branch]++
    }

    if ($counts.Keys.Count -le 0) {
        return ''
    }

    $winner = $counts.GetEnumerator() |
        Sort-Object -Property @(
            @{ Expression = { [int]$_.Value }; Descending = $true },
            @{ Expression = { [int]$_.Key }; Descending = $true }
        ) |
        Select-Object -First 1

    if ($winner) {
        return [string]$winner.Key
    }

    return ''
}

function Resolve-CatalogComparisonBaseline {
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [string]$CurrentVersion
    )

    $currentVersionText = [string]$CurrentVersion
    $currentVersionObj  = ConvertTo-VersionSafely -Value $currentVersionText
    $currentBuildBranch = Get-CatalogVersionBranch -Value $currentVersionText
    $dominantBuildBranch = Get-CatalogDominantBuildBranch -Items $Items

    $useComparableCurrent = $true
    $branchMismatch = $false

    if (
        $null -ne $currentVersionObj -and
        -not [string]::IsNullOrWhiteSpace($currentBuildBranch) -and
        -not [string]::IsNullOrWhiteSpace($dominantBuildBranch) -and
        ($currentBuildBranch -ne $dominantBuildBranch)
    ) {
        $useComparableCurrent = $false
        $branchMismatch = $true
    }

    return [pscustomobject]@{
        CurrentVersionText   = $currentVersionText
        CurrentVersionObj    = $currentVersionObj
        CurrentBuildBranch   = $currentBuildBranch
        DominantBuildBranch  = $dominantBuildBranch
        UseComparableCurrent = $useComparableCurrent
        BranchMismatch       = $branchMismatch
    }
}

function Test-CatalogCandidateIsNewerForBaseline {
    param(
        $Item,
        $Baseline
    )

    if ($null -eq $Item) { return $false }

    $candidateVersion = ConvertTo-VersionSafely -Value ([string]$Item.Version)
    if ($null -eq $candidateVersion) { return $false }

    if ($null -eq $Baseline) {
        return $true
    }

    if (-not $Baseline.UseComparableCurrent) {
        return $true
    }

    if ($null -eq $Baseline.CurrentVersionObj) {
        return $true
    }

    $candidateBranch = Get-CatalogVersionBranch -Value ([string]$Item.Version)
    $currentBranch   = [string]$Baseline.CurrentBuildBranch

    if (
        -not [string]::IsNullOrWhiteSpace($candidateBranch) -and
        -not [string]::IsNullOrWhiteSpace($currentBranch) -and
        ($candidateBranch -ne $currentBranch)
    ) {
        return $false
    }

    return ($candidateVersion -gt $Baseline.CurrentVersionObj)
}

function Select-BestCatalogCandidate {
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [string]$Kind,
        [string]$CurrentVersion,
        [switch]$ExcludePreview
    )

    $all = @($Items)
    if ($all.Count -eq 0) { return $null }

    $filtered = @(
        $all | Where-Object {
            $ok = $true

            if (-not [string]::IsNullOrWhiteSpace($Kind)) {
                $ok = $ok -and ([string]$_.Kind -eq $Kind)
            }

            if ($ExcludePreview) {
                $ok = $ok -and (-not [bool]$_.IsPreview)
            }

            $ok
        }
    )

    if ($filtered.Count -eq 0) { return $null }

    $baseline = Resolve-CatalogComparisonBaseline -Items $filtered -CurrentVersion $CurrentVersion

    try {
        if ($baseline.BranchMismatch) {
            Write-Log -Level INFO -Message ("Catalog: Branch mismatch erkannt fuer Kind={0}. Current={1}; CandidateBranch={2}" -f `
                $(if ($Kind) { $Kind } else { '-' }),
                $(if ($baseline.CurrentBuildBranch) { $baseline.CurrentBuildBranch } else { '-' }),
                $(if ($baseline.DominantBuildBranch) { $baseline.DominantBuildBranch } else { '-' }))
        }
    } catch {}

    $scored = foreach ($item in $filtered) {
        $candidateVer    = ConvertTo-VersionSafely -Value ([string]$item.Version)
        $candidateDate   = ConvertFrom-CatalogDateSafely -Value ([string]$item.LastUpdated)
        $candidateBranch = Get-CatalogVersionBranch -Value ([string]$item.Version)
        $isNewer         = Test-CatalogCandidateIsNewerForBaseline -Item $item -Baseline $baseline

        [pscustomobject]@{
            Item            = $item
            CandidateVer    = $candidateVer
            CandidateDate   = $candidateDate
            CandidateBranch = $candidateBranch
            IsNewer         = $isNewer
        }
    }

    $preferNewer = @($scored | Where-Object { $_.IsNewer })
    if ($preferNewer.Count -gt 0) {
        $scored = $preferNewer
    }

    $ordered = @(
        $scored | Sort-Object -Property @(
            @{ Expression = { if ($null -ne $_.CandidateVer) { $_.CandidateVer } else { [version]'0.0.0.0' } }; Descending = $true },
            @{ Expression = { if ($null -ne $_.CandidateDate) { $_.CandidateDate } else { [datetime]::MinValue } }; Descending = $true },
            @{ Expression = { [string]$_.Item.Title }; Descending = $false }
        )
    )

    if ($ordered.Count -eq 0) { return $null }
    return $ordered[0].Item
}

function Get-CatalogRecommendations {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [string]$CurrentLcuVersion,
        [string]$CurrentSsuVersion,
        [string]$CurrentDotNetVersion
    )

    $all = @($Items)

    if ($all.Count -eq 0) {
        return [pscustomobject]@{
            RecommendedLCU     = $null
            RecommendedSSU     = $null
            RecommendedDotNet  = $null
            RecommendedPreview = $null
            PreviewCount       = 0
            LCUCount           = 0
            SSUCount           = 0
            DotNetCount        = 0
            TotalCount         = 0
        }
    }

    $lcu     = Select-BestCatalogCandidate -Items $all -Kind 'LCU'    -CurrentVersion $CurrentLcuVersion -ExcludePreview
    $ssu     = Select-BestCatalogCandidate -Items $all -Kind 'SSU'    -CurrentVersion $CurrentSsuVersion -ExcludePreview
    $dotnet  = Select-BestCatalogCandidate -Items $all -Kind 'DotNet' -CurrentVersion $CurrentDotNetVersion -ExcludePreview
    $preview = Select-BestCatalogCandidate -Items $all -Kind 'Preview'

    return [pscustomobject]@{
        RecommendedLCU     = $lcu
        RecommendedSSU     = $ssu
        RecommendedDotNet  = $dotnet
        RecommendedPreview = $preview

        PreviewCount       = @($all | Where-Object { [bool]$_.IsPreview }).Count
        LCUCount           = @($all | Where-Object { [string]$_.Kind -eq 'LCU' }).Count
        SSUCount           = @($all | Where-Object { [string]$_.Kind -eq 'SSU' }).Count
        DotNetCount        = @($all | Where-Object { [string]$_.Kind -eq 'DotNet' }).Count
        TotalCount         = $all.Count
    }
}

function Get-RecommendedCatalogSubset {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [int]$MaxItems = 10,
        [string]$CurrentLcuVersion,
        [string]$CurrentSsuVersion,
        [string]$CurrentDotNetVersion
    )

    $all = @($Items)
    if ($all.Count -eq 0) { return @() }

    $recommendations = Get-CatalogRecommendations `
        -Items $all `
        -CurrentLcuVersion $CurrentLcuVersion `
        -CurrentSsuVersion $CurrentSsuVersion `
        -CurrentDotNetVersion $CurrentDotNetVersion

    $result = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($candidate in @(
        $recommendations.RecommendedLCU,
        $recommendations.RecommendedSSU,
        $recommendations.RecommendedDotNet,
        $recommendations.RecommendedPreview
    )) {
        if (-not $candidate) { continue }

        $key = [string]$candidate.UpdateId
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = ([string]$candidate.Title + '|' + [string]$candidate.KB)
        }

        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $result.Add($candidate) | Out-Null
        }
    }

    $lcuBaseline    = Resolve-CatalogComparisonBaseline -Items @($all | Where-Object { [string]$_.Kind -eq 'LCU' -and -not [bool]$_.IsPreview }) -CurrentVersion $CurrentLcuVersion
    $ssuBaseline    = Resolve-CatalogComparisonBaseline -Items @($all | Where-Object { [string]$_.Kind -eq 'SSU' -and -not [bool]$_.IsPreview }) -CurrentVersion $CurrentSsuVersion
    $dotNetBaseline = Resolve-CatalogComparisonBaseline -Items @($all | Where-Object { [string]$_.Kind -eq 'DotNet' -and -not [bool]$_.IsPreview }) -CurrentVersion $CurrentDotNetVersion

    $remaining = @(
        $all |
        Where-Object {
            $key = [string]$_.UpdateId
            if ([string]::IsNullOrWhiteSpace($key)) {
                $key = ([string]$_.Title + '|' + [string]$_.KB)
            }

            -not $seen.ContainsKey($key)
        } |
        ForEach-Object {
            $item = $_
            $kind = [string]$item.Kind
            $bucket = 3

            switch ($kind) {
                'LCU' {
                    if (Test-CatalogCandidateIsNewerForBaseline -Item $item -Baseline $lcuBaseline) {
                        $bucket = 0
                    } else {
                        $bucket = 2
                    }
                }
                'SSU' {
                    if (Test-CatalogCandidateIsNewerForBaseline -Item $item -Baseline $ssuBaseline) {
                        $bucket = 0
                    } else {
                        $bucket = 2
                    }
                }
                'DotNet' {
                    if (Test-CatalogCandidateIsNewerForBaseline -Item $item -Baseline $dotNetBaseline) {
                        $bucket = 0
                    } else {
                        $bucket = 2
                    }
                }
                'Preview' {
                    $bucket = 1
                }
                default {
                    $bucket = 3
                }
            }

            [pscustomobject]@{
                Item   = $item
                Bucket = $bucket
                Date   = ConvertFrom-CatalogDateSafely -Value ([string]$item.LastUpdated)
                Ver    = ConvertTo-VersionSafely -Value ([string]$item.Version)
            }
        } |
        Sort-Object -Property @(
            @{ Expression = { [int]$_.Bucket }; Descending = $false },
            @{ Expression = { if ($null -ne $_.Ver) { $_.Ver } else { [version]'0.0.0.0' } }; Descending = $true },
            @{ Expression = { if ($null -ne $_.Date) { $_.Date } else { [datetime]::MinValue } }; Descending = $true },
            @{ Expression = { [string]$_.Item.Title }; Descending = $false }
        ) |
        ForEach-Object { $_.Item }
    )

    foreach ($item in $remaining) {
        if ($result.Count -ge $MaxItems) { break }

        $key = [string]$item.UpdateId
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = ([string]$item.Title + '|' + [string]$item.KB)
        }

        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $result.Add($item) | Out-Null
        }
    }

    try {
        Write-Log -Level INFO -Message ("Catalog: Recommended subset={0}" -f $result.Count)
    } catch {}

    return @($result.ToArray())
}