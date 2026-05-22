function Get-CatalogDownloadsRoot {
    try {
        $root = Resolve-ProjectPath "Work\Updates\Downloads"
        $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction SilentlyContinue
        return $root
    } catch {
        throw "Catalog-Downloadordner konnte nicht erstellt werden: $($_.Exception.Message)"
    }
}

function Get-CatalogDownloadDialogUrl {
    param(
        [Parameter(Mandatory)][string]$UpdateId
    )

    $payload = '[{"size":0,"languages":"","uidInfo":"' + $UpdateId + '","updateID":"' + $UpdateId + '"}]'
    return ('https://www.catalog.update.microsoft.com/DownloadDialog.aspx?updateIDs={0}' -f [System.Uri]::EscapeDataString($payload))
}

function Invoke-CatalogDownloadDialogRequest {
    param(
        [Parameter(Mandatory)][string]$UpdateId
    )

    $dialogUrl = Get-CatalogDownloadDialogUrl -UpdateId $UpdateId
    $referer = 'https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?updateid=' + $UpdateId

    try {
        Write-Log -Level INFO -Message ("Catalog: DownloadDialog Request fuer {0}" -f $UpdateId)
    } catch {}

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $headers = @{
        'Referer'         = $referer
        'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36'
        'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language' = 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7'
    }

    try {
        $null = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $referer `
            -Method Get `
            -Headers $headers `
            -WebSession $session `
            -TimeoutSec 120 `
            -ErrorAction Stop
    } catch {
        try {
            Write-Log -Level WARN -Message ("Catalog: ScopedViewInline Vorabruf fehlgeschlagen: {0}" -f $_.Exception.Message)
        } catch {}
    }

    try {
        return Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $dialogUrl `
            -Method Get `
            -Headers $headers `
            -WebSession $session `
            -TimeoutSec 120 `
            -ErrorAction Stop
    } catch {
        throw "Catalog-DownloadDialog konnte nicht geladen werden: $($_.Exception.Message)"
    }
}

function ConvertFrom-CatalogJsEscapes {
    param(
        [AllowEmptyString()][string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $value = [string]$Text
    $value = [System.Net.WebUtility]::HtmlDecode($value)
    $value = $value -replace '\\u003a', ':'
    $value = $value -replace '\\u002f', '/'
    $value = $value -replace '\\x3a', ':'
    $value = $value -replace '\\x2f', '/'
    $value = $value -replace '\\/', '/'

    return $value
}

function Test-CatalogDownloadHostAllowed {
    param(
        [Parameter(Mandatory)][string]$Url
    )

    try {
        $uri = [System.Uri]$Url
        $host = $uri.Host.ToLowerInvariant()

        if ($host -like '*.windowsupdate.com') { return $true }
        if ($host -eq 'windowsupdate.com') { return $true }
        if ($host -like '*.delivery.mp.microsoft.com') { return $true }
        if ($host -eq 'delivery.mp.microsoft.com') { return $true }

        return $false
    } catch {
        return $false
    }
}

function Add-CatalogUrlIfValid {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)]$List,
        [Parameter(Mandatory)][hashtable]$Seen
    )

    $candidate = ConvertFrom-CatalogJsEscapes -Text $Url
    $candidate = $candidate.Trim()

    if ([string]::IsNullOrWhiteSpace($candidate)) { return }
    if ($candidate -notmatch '^https?://') { return }
    if (-not (Test-CatalogDownloadHostAllowed -Url $candidate)) { return }

    $key = $candidate.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) { return }

    $Seen[$key] = $true
    $List.Add($candidate) | Out-Null
}

function Get-CatalogDownloadUrlsFromHtml {
    param(
        [Parameter(Mandatory)][string]$Html
    )

    $variants = New-Object System.Collections.Generic.List[string]
    $variants.Add([string]$Html) | Out-Null
    $variants.Add([System.Net.WebUtility]::HtmlDecode([string]$Html)) | Out-Null
    $variants.Add((ConvertFrom-CatalogJsEscapes -Text ([string]$Html))) | Out-Null
    $variants.Add((ConvertFrom-CatalogJsEscapes -Text ([System.Net.WebUtility]::HtmlDecode([string]$Html)))) | Out-Null

    $urls = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($variant in $variants) {
        if ([string]::IsNullOrWhiteSpace($variant)) { continue }

        $rawMatches = [regex]::Matches(
            $variant,
            'https?://[^\s''"<>]+',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($m in $rawMatches) {
            Add-CatalogUrlIfValid -Url ([string]$m.Value) -List ([object]$urls) -Seen $seen
        }

        $assignMatches = [regex]::Matches(
            $variant,
            '(?:^|[\s\{\[\(,;])(?:url|downloadurl|fileurl|enurl|frurl|deurl)?\s*[:=]\s*["''](?<u>https?://[^"'']+)["'']',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        foreach ($m in $assignMatches) {
            Add-CatalogUrlIfValid -Url ([string]$m.Groups['u'].Value) -List ([object]$urls) -Seen $seen
        }

        $quotedMatches = [regex]::Matches(
            $variant,
            '["''](?<u>https?://[^"'']+)["'']',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        foreach ($m in $quotedMatches) {
            Add-CatalogUrlIfValid -Url ([string]$m.Groups['u'].Value) -List ([object]$urls) -Seen $seen
        }
    }

    try {
        Write-Log -Level INFO -Message ("Catalog: Extracted download URLs = {0}" -f $urls.Count)
        if ($urls.Count -gt 0) {
            Write-Log -Level INFO -Message ("Catalog: First download URL = {0}" -f [string]$urls[0])
        }
    } catch {}

    return @($urls.ToArray())
}

function Get-CatalogFileNameFromUrl {
    param(
        [Parameter(Mandatory)][string]$Url
    )

    try {
        $uri = [System.Uri]$Url
        $name = [System.IO.Path]::GetFileName($uri.AbsolutePath)
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name
        }
    } catch {}

    return ('catalog_' + [guid]::NewGuid().ToString('N') + '.bin')
}

function Get-CatalogDownloadPriority {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$KB
    )

    $score = 0
    $name = [string]$FileName
    $nameLower = $name.ToLowerInvariant()
    $ext = [System.IO.Path]::GetExtension($nameLower)

    if (-not [string]::IsNullOrWhiteSpace($KB)) {
        $kbLower = $KB.ToLowerInvariant()
        if ($nameLower -match [regex]::Escape($kbLower)) {
            $score += 1000
        }
    }

    switch ($ext) {
        '.msu' { $score += 200 }
        '.cab' { $score += 100 }
        '.psf' { $score += 10  }
        default { $score += 0 }
    }

    if ($nameLower -match '^windows') {
        $score += 20
    }

    return $score
}

function Select-PrimaryCatalogDownloadUrls {
    param(
        [Parameter(Mandatory)][string[]]$Urls,
        [string]$KB
    )

    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($url in @($Urls)) {
        if ([string]::IsNullOrWhiteSpace($url)) { continue }

        $fileName = Get-CatalogFileNameFromUrl -Url $url
        $priority = Get-CatalogDownloadPriority -FileName $fileName -KB $KB

        $candidates.Add([pscustomobject]@{
            Url      = $url
            FileName = $fileName
            Priority = $priority
            HasKbHit = if (-not [string]::IsNullOrWhiteSpace($KB)) {
                $fileName.ToLowerInvariant() -match [regex]::Escape($KB.ToLowerInvariant())
            } else {
                $false
            }
        }) | Out-Null
    }

    $candidateArray = @($candidates.ToArray())
    if ($candidateArray.Count -eq 0) {
        return [pscustomobject]@{
            SelectedUrls   = @()
            SkippedUrls    = @()
            CandidateCount = 0
            Strategy       = 'None'
        }
    }

    $strategy = 'BestPriority'
    $workingSet = $candidateArray

    if (-not [string]::IsNullOrWhiteSpace($KB)) {
        $kbMatches = @($candidateArray | Where-Object { $_.HasKbHit })
        if ($kbMatches.Count -gt 0) {
            $workingSet = $kbMatches
            $strategy = 'KBMatch'
        }
    }

    $ordered = @(
        $workingSet | Sort-Object -Property @(
            @{ Expression = { [int]$_.Priority }; Descending = $true },
            @{ Expression = { [string]$_.FileName }; Descending = $false }
        )
    )

    $selected = @()
    if ($ordered.Count -gt 0) {
        $selected = @($ordered[0].Url)
    }

    $selectedSet = @{}
    foreach ($u in $selected) {
        $selectedSet[$u.ToLowerInvariant()] = $true
    }

    $skipped = @(
        $candidateArray |
        Where-Object { -not $selectedSet.ContainsKey(([string]$_.Url).ToLowerInvariant()) } |
        Select-Object -ExpandProperty Url
    )

    try {
        Write-Log -Level INFO -Message ("Catalog: URL-Auswahl Strategie={0}; Kandidaten={1}; Ausgewaehlt={2}; Uebersprungen={3}" -f `
            $strategy,
            $candidateArray.Count,
            @($selected).Count,
            @($skipped).Count)

        if (@($selected).Count -gt 0) {
            Write-Log -Level INFO -Message ("Catalog: Primaerdatei = {0}" -f (Get-CatalogFileNameFromUrl -Url $selected[0]))
        }
    } catch {}

    return [pscustomobject]@{
        SelectedUrls   = @($selected)
        SkippedUrls    = @($skipped)
        CandidateCount = $candidateArray.Count
        Strategy       = $strategy
    }
}

function Get-SafeCatalogDownloadFolderName {
    param(
        [string]$Title,
        [string]$KB,
        [string]$UpdateId
    )

    $base = ''
    if (-not [string]::IsNullOrWhiteSpace($KB)) {
        $base = $KB
    } elseif (-not [string]::IsNullOrWhiteSpace($Title)) {
        $base = $Title
    } else {
        $base = 'Update'
    }

    $safe = ($base -replace '[^a-zA-Z0-9]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'Update'
    }

    if ($safe.Length -gt 60) {
        $safe = $safe.Substring(0, 60).TrimEnd('_')
    }

    $suffix = ''
    if (-not [string]::IsNullOrWhiteSpace($UpdateId)) {
        $suffix = $UpdateId.Replace('-', '').ToLowerInvariant()
        if ($suffix.Length -gt 8) {
            $suffix = $suffix.Substring(0, 8)
        }
    } else {
        $suffix = (Get-Date -Format 'yyyyMMddHHmmss')
    }

    return ('{0}_{1}' -f $safe, $suffix)
}

function Save-CatalogFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        try {
            $existing = Get-Item -LiteralPath $DestinationPath -ErrorAction Stop
            if ($existing.Length -gt 0) {
                return [pscustomobject]@{
                    Status    = 'SkippedExists'
                    LocalPath = $DestinationPath
                    Url       = $Url
                }
            }
        } catch {}
    }

    $parent = Split-Path -Path $DestinationPath -Parent
    $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue

    $bits = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    if ($bits) {
        try {
            Start-BitsTransfer -Source $Url -Destination $DestinationPath -DisplayName 'WinImageAdmin Catalog Download' -Description $Url -ErrorAction Stop
            return [pscustomobject]@{
                Status    = 'Downloaded'
                LocalPath = $DestinationPath
                Url       = $Url
            }
        } catch {
            try {
                Write-Log -Level WARN -Message ("Catalog: BITS fehlgeschlagen, Fallback auf Invoke-WebRequest: {0}" -f $_.Exception.Message)
            } catch {}
        }
    }

    $oldProgress = $global:ProgressPreference
    try {
        $global:ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $DestinationPath -TimeoutSec 1800
    } catch {
        throw "Dateidownload fehlgeschlagen ($Url): $($_.Exception.Message)"
    } finally {
        $global:ProgressPreference = $oldProgress
    }

    return [pscustomobject]@{
        Status    = 'Downloaded'
        LocalPath = $DestinationPath
        Url       = $Url
    }
}

function ConvertFrom-CatalogLocalUpdateId {
    param([string]$UpdateId)

    if ([string]::IsNullOrWhiteSpace($UpdateId)) { return '' }
    if ($UpdateId -notmatch '^LOCAL:(?<p>.+)$') { return '' }

    $encoded = [string]$matches['p']
    $encoded = $encoded.Replace('-', '+').Replace('_', '/')
    while (($encoded.Length % 4) -ne 0) {
        $encoded += '='
    }

    try {
        return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
    } catch {
        return ''
    }
}

function New-LocalCatalogDownloadResult {
    param(
        [Parameter(Mandatory)][string]$PackagePath,
        [string]$Title = '',
        [string]$KB = ''
    )

    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "Lokale Paketdatei nicht gefunden: $PackagePath"
    }

    $ext = [System.IO.Path]::GetExtension($PackagePath).ToLowerInvariant()
    if ($ext -notin @('.msu', '.cab')) {
        throw "Lokale Updates müssen .msu- oder .cab-Dateien sein: $PackagePath"
    }

    $item = Get-Item -LiteralPath $PackagePath -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = [string]$item.Name
    }

    return [pscustomobject]@{
        UpdateId           = 'LOCAL'
        Title              = $Title
        KB                 = $KB
        DownloadDirectory  = ''
        FileCount          = 1
        DownloadedCount    = 0
        SkippedCount       = 1
        CandidateCount     = 1
        NonSelectedCount   = 0
        SelectionStrategy  = 'LocalFile'
        Files              = @(
            [pscustomobject]@{
                Url       = ''
                FileName  = [string]$item.Name
                LocalPath = [string]$item.FullName
                Status    = 'LocalFile'
            }
        )
        SkippedUrls        = @()
    }
}

function Download-CatalogUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UpdateId,
        [string]$Title,
        [string]$KB
    )

    if ([string]::IsNullOrWhiteSpace($UpdateId)) {
        throw "Download-CatalogUpdate benoetigt eine UpdateId."
    }

    $localPath = ConvertFrom-CatalogLocalUpdateId -UpdateId $UpdateId
    if (-not [string]::IsNullOrWhiteSpace($localPath)) {
        try {
            Write-Log -Level INFO -Message ("Catalog: Lokale Update-Datei verwendet: {0}" -f $localPath)
        } catch {}
        return (New-LocalCatalogDownloadResult -PackagePath $localPath -Title $Title -KB $KB)
    }

    $dialog = Invoke-CatalogDownloadDialogRequest -UpdateId $UpdateId
    $html = [string]$dialog.Content

    $debugPath = Write-CatalogDebugFile -Prefix ("catalog_download_dialog_" + $UpdateId) -Content $html

    $allUrls = @(Get-CatalogDownloadUrlsFromHtml -Html $html)
    if ($allUrls.Count -eq 0) {
        $extra = if (-not [string]::IsNullOrWhiteSpace($debugPath)) {
            "`nDebug-Datei: $debugPath"
        } else {
            ''
        }

        throw ("Es konnten keine Download-URLs aus dem Catalog-Dialog extrahiert werden.{0}" -f $extra)
    }

    $selection = Select-PrimaryCatalogDownloadUrls -Urls $allUrls -KB $KB
    $selectedUrls = @($selection.SelectedUrls)
    $skippedUrls = @($selection.SkippedUrls)

    if ($selectedUrls.Count -eq 0) {
        throw "Es konnte keine Primaerdatei fuer den Download bestimmt werden."
    }

    $root = Get-CatalogDownloadsRoot
    $folderName = Get-SafeCatalogDownloadFolderName -Title $Title -KB $KB -UpdateId $UpdateId
    $targetDir = Join-Path $root $folderName
    $null = New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue

    $files = New-Object System.Collections.Generic.List[object]
    $downloadedCount = 0
    $skippedCount = 0

    foreach ($url in $selectedUrls) {
        $fileName = Get-CatalogFileNameFromUrl -Url $url
        $destination = Join-Path $targetDir $fileName

        try {
            $fileResult = Save-CatalogFile -Url $url -DestinationPath $destination

            if ([string]$fileResult.Status -eq 'Downloaded') {
                $downloadedCount++
            } else {
                $skippedCount++
            }

            $files.Add([pscustomobject]@{
                Url       = $url
                FileName  = $fileName
                LocalPath = [string]$fileResult.LocalPath
                Status    = [string]$fileResult.Status
            }) | Out-Null
        } catch {
            throw "Download fuer '$fileName' fehlgeschlagen: $($_.Exception.Message)"
        }
    }

    try {
        Write-Log -Level INFO -Message ("Catalog: Download abgeschlossen fuer {0} | Kandidaten={1} | Primaer={2} | Uebersprungen={3} | Neu={4} | Vorhanden={5} | Ordner={6}" -f `
            $UpdateId,
            [int]$selection.CandidateCount,
            [int]@($selectedUrls).Count,
            [int]@($skippedUrls).Count,
            $downloadedCount,
            $skippedCount,
            $targetDir)
    } catch {}

    return [pscustomobject]@{
        UpdateId           = $UpdateId
        Title              = $Title
        KB                 = $KB
        DownloadDirectory  = $targetDir
        FileCount          = $files.Count
        DownloadedCount    = $downloadedCount
        SkippedCount       = $skippedCount
        CandidateCount     = [int]$selection.CandidateCount
        NonSelectedCount   = [int]@($skippedUrls).Count
        SelectionStrategy  = [string]$selection.Strategy
        Files              = @($files.ToArray())
        SkippedUrls        = @($skippedUrls)
    }
}
