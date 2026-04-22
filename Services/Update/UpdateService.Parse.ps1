function Convert-DismTextToBlocks {
    param(
        [AllowEmptyString()][string]$Text
    )

    $blocks = New-Object System.Collections.Generic.List[object]
    $current = [ordered]@{}

    $lines = @()
    if (-not [string]::IsNullOrEmpty($Text)) {
        $lines = $Text -split "`r?`n"
    }

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                $blocks.Add([pscustomobject]$current)
                $current = [ordered]@{}
            }
            continue
        }

        if ($line -match '^\s*([^:]+?)\s*:\s*(.*)$') {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()

            if ($current.Contains($key)) {
                $current[$key] = ([string]$current[$key] + "`n" + $val).Trim()
            } else {
                $current[$key] = $val
            }
        }
    }

    if ($current.Count -gt 0) {
        $blocks.Add([pscustomobject]$current)
    }

    return @($blocks.ToArray())
}

function Get-PackageKb {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $m = [regex]::Match($Text, 'KB\d{6,8}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        return $m.Value.ToUpperInvariant()
    }

    return ''
}

function Get-PackageKind {
    param(
        [string]$Identity,
        [string]$ReleaseType
    )

    $blob = (([string]$Identity) + ' ' + ([string]$ReleaseType)).ToLowerInvariant()

    if ($blob -match 'servicingstack' -or $blob -match 'servicing stack' -or $blob -match '\bssu\b') {
        return 'SSU'
    }

    if ($blob -match '\.net' -or $blob -match 'netfx' -or $blob -match 'net framework') {
        return 'DotNet'
    }

    if ($blob -match 'rollupfix' -or $blob -match 'cumulative') {
        return 'LCU'
    }

    return 'Other'
}

function ConvertTo-PackageObjectsFromDism {
    param(
        [AllowEmptyString()][string]$Text
    )

    $items = New-Object System.Collections.Generic.List[object]

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $normalized = $Text -replace "`r", ""

    $parts = [regex]::Split(
        $normalized,
        '(?m)^\s*Package Identity\s*:\s*'
    )

    if ($parts.Count -le 1) {
        Write-UpdateLog -Level WARN -Message "Updates: Parser hat keine 'Package Identity'-Bloecke gefunden."
        return @()
    }

    for ($i = 1; $i -lt $parts.Count; $i++) {
        $part = [string]$parts[$i]
        if ([string]::IsNullOrWhiteSpace($part)) { continue }

        $lines = $part -split "`n"
        if ($lines.Count -eq 0) { continue }

        $identity = ''
        $state = ''
        $releaseType = ''
        $installTime = ''

        $identity = [string]$lines[0].Trim()
        if ([string]::IsNullOrWhiteSpace($identity)) { continue }

        foreach ($line in $lines) {
            if ($line -match '^\s*State\s*:\s*(.+?)\s*$') {
                $state = $matches[1].Trim()
                continue
            }
            if ($line -match '^\s*Release Type\s*:\s*(.+?)\s*$') {
                $releaseType = $matches[1].Trim()
                continue
            }
            if ($line -match '^\s*Install Time\s*:\s*(.+?)\s*$') {
                $installTime = $matches[1].Trim()
                continue
            }
        }

        $kb = Get-PackageKb -Text ($identity + ' ' + $releaseType)
        $kind = Get-PackageKind -Identity $identity -ReleaseType $releaseType

        $items.Add([pscustomobject]@{
            PackageIdentity = $identity
            State           = $state
            ReleaseType     = $releaseType
            InstallTime     = $installTime
            KB              = $kb
            Kind            = $kind
        })
    }

    Write-UpdateLog -Level INFO -Message ("Updates: entpackte Paket-Items={0}" -f $items.Count)
    return @($items.ToArray())
}