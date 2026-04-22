Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-DismDriversTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $lines = $Text -split "`r?`n"

    # Header suchen (stabil mit /English)
    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*Published Name\s*\|\s*Original File Name\s*\|\s*Inbox\s*\|') {
            $headerIdx = $i
            break
        }
    }
    if ($headerIdx -lt 0) { return @() }

    # Separatorline nach Header suchen
    $sepPattern = '^\s*-+\s*(\|\s*-+\s*){2,}$'
    $dataStart = $headerIdx + 1
    for ($i = $headerIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $sepPattern) {
            $dataStart = $i + 1
            break
        }
    }

    $items = New-Object System.Collections.Generic.List[object]

    for ($i = $dataStart; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '^\s*The operation completed successfully') { break }
        if ($line -match '^\s*Error:\s*\d+') { break }
        if ($line -match $sepPattern) { continue }

        if ($line -notmatch '\|') { continue }

        $cols = $line.Trim() -split '\s*\|\s*'
        if ($cols.Count -lt 7) { continue }

        $pub  = $cols[0].Trim()
        $orig = $cols[1].Trim()
        $inbx = $cols[2].Trim()
        $cls  = $cols[3].Trim()
        $prov = $cols[4].Trim()
        $date = $cols[5].Trim()
        $ver  = $cols[6].Trim()

        if ([string]::IsNullOrWhiteSpace($pub)) { continue }

        $items.Add([pscustomobject]@{
            PublishedName    = $pub
            OriginalFileName = $orig
            Inbox            = $inbx
            ClassName        = $cls
            ProviderName     = $prov
            Date             = $date
            Version          = $ver
        }) | Out-Null
    }

    return ,$items.ToArray()
}

function ConvertFrom-DismDriversList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    # Fallback für /Format:List (Key/Value Blöcke)
    $lines = $Text -split "`r?`n"

    $items = New-Object System.Collections.Generic.List[object]
    $cur = @{}

    function Flush-Current {
        if ($cur.ContainsKey('PublishedName') -and -not [string]::IsNullOrWhiteSpace([string]$cur.PublishedName)) {
            $items.Add([pscustomobject]@{
                PublishedName    = [string]$cur.PublishedName
                OriginalFileName = [string]$cur.OriginalFileName
                Inbox            = [string]$cur.Inbox
                ClassName        = [string]$cur.ClassName
                ProviderName     = [string]$cur.ProviderName
                Date             = [string]$cur.Date
                Version          = [string]$cur.Version
            }) | Out-Null
        }
        $script:cur = @{}
    }

    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t.Length -eq 0) { continue }

        if ($t -match '^\s*The operation completed successfully') { break }

        if ($t -match '^\s*Published\s+Name\s*:\s*(.+)\s*$') { Flush-Current; $cur['PublishedName'] = $Matches[1].Trim(); continue }
        if ($t -match '^\s*Original\s+File\s+Name\s*:\s*(.+)\s*$') { $cur['OriginalFileName'] = $Matches[1].Trim(); continue }
        if ($t -match '^\s*Inbox\s*:\s*(.+)\s*$') { $cur['Inbox'] = $Matches[1].Trim(); continue }
        if ($t -match '^\s*Class\s+Name\s*:\s*(.+)\s*$') { $cur['ClassName'] = $Matches[1].Trim(); continue }
        if ($t -match '^\s*Provider\s+Name\s*:\s*(.+)\s*$') { $cur['ProviderName'] = $Matches[1].Trim(); continue }
        if ($t -match '^\s*Date\s*:\s*(.+)\s*$') { $cur['Date'] = $Matches[1].Trim(); continue }
        if ($t -match '^\s*Version\s*:\s*(.+)\s*$') { $cur['Version'] = $Matches[1].Trim(); continue }
    }

    Flush-Current
    return ,$items.ToArray()
}

function ConvertFrom-DismDriversOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    # Normalfall: wenn nur 3rd-party gelistet wird und es gibt keine.
    if ($Text -match '(?i)No drivers found in the image matching the criteria') {
        return @()
    }
    if ($Text -match '(?i)\(No driver.*found.*matching the criteria\)') {
        return @()
    }

    $table = ConvertFrom-DismDriversTable -Text $Text
    if (@($table).Count -gt 0) { return ,$table }

    $list = ConvertFrom-DismDriversList -Text $Text
    if (@($list).Count -gt 0) { return ,$list }

    $lines = $Text -split "`r?`n"
    $excerpt = ($lines | Select-Object -First 140) -join "`n"
    throw ("Treiber-Parsing ergab 0 Einträge. DISM-Auszug:`n`n{0}`n" -f $excerpt)
}

Export-ModuleMember -Function ConvertFrom-DismDriversOutput