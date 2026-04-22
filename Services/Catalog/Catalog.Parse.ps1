function Normalize-CatalogText {
    param([string]$Text)

    if ($null -eq $Text) { return '' }

    $value = [string]$Text
    $value = $value -replace '&nbsp;', ' '
    $value = [System.Net.WebUtility]::HtmlDecode($value)
    $value = $value -replace '\s+', ' '
    return $value.Trim()
}

function Get-CatalogSearchUrl {
    param(
        [Parameter(Mandatory)][string]$Query
    )

    $encoded = [System.Uri]::EscapeDataString($Query)
    return ("https://www.catalog.update.microsoft.com/Search.aspx?q={0}" -f $encoded)
}

function Invoke-CatalogWebRequest {
    param(
        [Parameter(Mandatory)][string]$Url
    )

    try {
        Write-Log -Level INFO -Message ("Catalog: Request {0}" -f $Url)
    } catch {}

    try {
        return Invoke-WebRequest -UseBasicParsing -Uri $Url -Method Get -TimeoutSec 120
    } catch {
        throw "Catalog-Webrequest fehlgeschlagen: $($_.Exception.Message)"
    }
}

function Get-CatalogRowBlocks {
    param(
        [Parameter(Mandatory)][string]$Html
    )

    $rows = [regex]::Matches(
        $Html,
        '<tr[^>]*>(?<row>.*?)</tr>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $list = @()
    foreach ($m in $rows) {
        $list += [string]$m.Groups['row'].Value
    }

    return @($list)
}

function Get-CellTextsFromRow {
    param(
        [Parameter(Mandatory)][string]$RowHtml
    )

    $cells = [regex]::Matches(
        $RowHtml,
        '<td[^>]*>\s*(.*?)\s*</td>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $values = @()
    foreach ($cell in $cells) {
        $inner = [string]$cell.Groups[1].Value
        $text  = $inner -replace '<[^>]+>', ' '
        $text  = Normalize-CatalogText -Text $text
        $values += $text
    }

    return @($values)
}

function Get-TitleFromRow {
    param(
        [Parameter(Mandatory)][string]$RowHtml
    )

    $patterns = @(
        '<a[^>]*>(?<title>.*?)</a>',
        'title\s*=\s*"(?<title>.*?)"'
    )

    foreach ($pattern in $patterns) {
        $m = [regex]::Match(
            $RowHtml,
            $pattern,
            [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($m.Success) {
            $title = Normalize-CatalogText -Text ([string]$m.Groups['title'].Value)
            if (-not [string]::IsNullOrWhiteSpace($title)) {
                return $title
            }
        }
    }

    return $null
}

function Get-UpdateIdFromRow {
    param(
        [Parameter(Mandatory)][string]$RowHtml
    )

    $patterns = @(
        'ScopedViewInline\.aspx\?updateid=(?<id>[0-9a-fA-F-]{36})',
        'goToDetails\("(?<id>[0-9a-fA-F-]{36})"\)',
        'addToBasket\("(?<id>[0-9a-fA-F-]{36})"\)',
        'id\s*=\s*"(?<id>[0-9a-fA-F-]{36})"'
    )

    foreach ($pattern in $patterns) {
        $m = [regex]::Match(
            $RowHtml,
            $pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if ($m.Success) {
            return [string]$m.Groups['id'].Value
        }
    }

    return $null
}

function Get-KBFromTitle {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }

    $m = [regex]::Match($Title, '(KB\d{6,8})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        return $m.Groups[1].Value.ToUpperInvariant()
    }

    return $null
}

function Get-VersionFromTitle {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }

    $text = [string]$Title

    $patterns = @(
        '\((?<v>\d{4,5}\.\d{1,5})\)',
        '\b(?<v>\d{4,5}\.\d{1,5})\b',
        '\((?<v>\d+\.\d+\.\d+\.\d+)\)',
        '\b(?<v>\d+\.\d+\.\d+\.\d+)\b',
        '\((?<v>\d+\.\d+\.\d+)\)',
        '\((?<v>\d+\.\d+)\)'
    )

    foreach ($pattern in $patterns) {
        $m = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            return [string]$m.Groups['v'].Value
        }
    }

    return $null
}

function ConvertTo-VersionSafely {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    try {
        return [version]$Value
    } catch {
        return $null
    }
}

function ConvertFrom-CatalogDateSafely {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $text = [string]$Value.Trim()
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces

    $cultures = @(
        [System.Globalization.CultureInfo]::GetCultureInfo('en-US'),
        [System.Globalization.CultureInfo]::GetCultureInfo('de-DE'),
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.CultureInfo]::CurrentCulture
    )

    foreach ($culture in $cultures) {
        try {
            $parsed = $null
            if ([datetime]::TryParse($text, $culture, $styles, [ref]$parsed)) {
                return $parsed
            }
        } catch {}
    }

    return $null
}