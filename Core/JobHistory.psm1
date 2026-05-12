Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:JobHistoryFilePath = $null
$script:JobHistoryRootPath = $null

function Get-JobHistoryFilePath {
    [CmdletBinding()]
    param()

    $projectRoot = $null
    try { $projectRoot = Get-ProjectRoot } catch { $projectRoot = (Get-Location).Path }

    if ($script:JobHistoryFilePath -and $script:JobHistoryRootPath -eq $projectRoot) {
        return $script:JobHistoryFilePath
    }

    $dir = Join-Path $projectRoot "Work\History"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $script:JobHistoryFilePath = Join-Path $dir "job-history.json"
    $script:JobHistoryRootPath = $projectRoot
    return $script:JobHistoryFilePath
}

function Read-JobHistoryFile {
    [CmdletBinding()]
    param()

    $path = Get-JobHistoryFilePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

        $items = $raw | ConvertFrom-Json
        if ($null -eq $items) { return }

        if ($items -is [System.Array]) {
            foreach ($item in $items) { $item }
            return
        }

        $items
    } catch {
        try { Write-Log -Level WARN -Message ("JobHistory konnte nicht gelesen werden: {0}" -f $_.Exception.Message) } catch {}
        return @()
    }
}

function Write-JobHistoryFile {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Items = @()
    )

    $path = Get-JobHistoryFilePath
    $dir = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $json = ConvertTo-Json -InputObject @($Items) -Depth 8
    if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($path, $json, $utf8Bom)
}

function Add-JobHistoryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]
        [ValidateSet("Started","Completed","Failed","Cancelled","Skipped","Info")]
        [string]$Status,
        [string]$Message = $null,
        [string]$Detail = $null,
        [string]$ErrorText = $null,
        [Nullable[datetime]]$StartedAt = $null,
        [Nullable[datetime]]$EndedAt = $null,
        [Nullable[int64]]$DurationMs = $null,
        [hashtable]$Data = $null,
        [int]$MaxEntries = 250
    )

    if ($MaxEntries -lt 25) { $MaxEntries = 25 }

    $now = Get-Date
    $startedValue = if ($null -ne $StartedAt) { [datetime]$StartedAt } else { $now }
    $endedValue = if ($null -ne $EndedAt) { [datetime]$EndedAt } elseif ($Status -ne "Started") { $now } else { $null }
    $durationValue = if ($null -ne $DurationMs) { [int64]$DurationMs } else { $null }

    $entry = [ordered]@{
        Id         = [guid]::NewGuid().ToString("N")
        Operation  = $Operation
        Status     = $Status
        Message    = if ([string]::IsNullOrWhiteSpace($Message)) { $Operation } else { $Message }
        Detail     = $Detail
        Error      = $ErrorText
        StartedAt  = $startedValue.ToString("o")
        EndedAt    = if ($null -ne $endedValue) { ([datetime]$endedValue).ToString("o") } else { $null }
        DurationMs = $durationValue
        CreatedAt  = $now.ToString("o")
        Data       = $Data
    }

    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        try {
            $items = New-Object System.Collections.Generic.List[object]
            [void]$items.Add([pscustomobject]$entry)

            foreach ($item in @(Read-JobHistoryFile)) {
                if ($items.Count -ge $MaxEntries) { break }
                [void]$items.Add($item)
            }

            Write-JobHistoryFile -Items @($items.ToArray())
            return [pscustomobject]$entry
        } catch {
            if ($attempt -ge 3) {
                try { Write-Log -Level WARN -Message ("JobHistory konnte nicht geschrieben werden: {0}" -f $_.Exception.Message) } catch {}
                return [pscustomobject]$entry
            }
            Start-Sleep -Milliseconds (50 * ($attempt + 1))
        }
    }
}

function Get-JobHistory {
    [CmdletBinding()]
    param([int]$Limit = 50)

    if ($Limit -lt 1) { $Limit = 1 }
    return @(Read-JobHistoryFile | Select-Object -First $Limit)
}

function Get-JobHistorySummary {
    [CmdletBinding()]
    param()

    $items = @(Get-JobHistory -Limit 100)
    $last = $items | Select-Object -First 1
    $lastFinished = $items | Where-Object { [string]$_.Status -in @("Completed","Failed","Cancelled") } | Select-Object -First 1
    $lastError = $items | Where-Object { [string]$_.Status -eq "Failed" } | Select-Object -First 1

    return [pscustomobject]@{
        Count        = $items.Count
        Last         = $last
        LastFinished = $lastFinished
        LastError    = $lastError
    }
}

Export-ModuleMember -Function `
    Get-JobHistoryFilePath, `
    Add-JobHistoryEntry, `
    Get-JobHistory, `
    Get-JobHistorySummary
