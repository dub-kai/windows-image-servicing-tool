Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Import-WimInfoDependencies {
    [CmdletBinding()]
    param()

    $bootstrapPath = Join-Path $PSScriptRoot '..\Core\Bootstrap.psm1'
    Import-Module $bootstrapPath -Global -Force -DisableNameChecking | Out-Null

    $dismPath = Resolve-ProjectPath 'Services\DismService.psm1' -MustExist
    Import-Module $dismPath -Global -Force -DisableNameChecking | Out-Null
}

function Get-WimImageList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath
    )

    Import-WimInfoDependencies

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        throw "ImagePath nicht gefunden: $ImagePath"
    }

    $args = @(
        "/Get-WimInfo",
        ("/WimFile:`"{0}`"" -f $ImagePath)
    )

    $res = Invoke-Dism -Arguments $args -EnsureEnglish

    if ($res.ExitCode -ne 0) {
        $msg = $res.StdErr
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $res.StdOut }
        throw "DISM /Get-WimInfo fehlgeschlagen (ExitCode=$($res.ExitCode)). $msg"
    }

    $text = $res.StdOut
    if ([string]::IsNullOrWhiteSpace($text)) {
        # WICHTIG: immer eine Collection als EIN Objekt zurückgeben
        return ,@()
    }

    $lines = $text -split "`r?`n"

    $list = New-Object System.Collections.Generic.List[object]

    $curIndex = $null
    $curName  = $null
    $curDesc  = $null

    function Flush-Current {
        if ($null -ne $curIndex) {
            $list.Add([pscustomobject]@{
                Index       = [int]$curIndex
                Name        = $curName
                Description = $curDesc
            }) | Out-Null
        }
    }

    foreach ($ln in $lines) {
        $line = $ln.Trim()
        if ($line.Length -eq 0) { continue }

        if ($line -match '^Index\s*:\s*(\d+)\s*$') {
            Flush-Current
            $curIndex = $matches[1]
            $curName  = $null
            $curDesc  = $null
            continue
        }

        if ($line -match '^Name\s*:\s*(.+)\s*$') {
            $curName = $matches[1].Trim()
            continue
        }

        if ($line -match '^Description\s*:\s*(.+)\s*$') {
            $curDesc = $matches[1].Trim()
            continue
        }
    }

    Flush-Current

    # GANZ WICHTIG:
    # Als EIN Objekt zurückgeben (object[]), damit UI immer IEnumerable bekommt – auch bei 1 Eintrag.
    return ,($list.ToArray())
}

Export-ModuleMember -Function Get-WimImageList
