Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-MountedWimList {
    [CmdletBinding()]
    param()

    $res = Invoke-Dism -Arguments @("/Get-MountedWimInfo") -EnsureEnglish

    if ($res.ExitCode -ne 0) {
        $msg = $res.StdErr
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $res.StdOut }
        throw "DISM /Get-MountedWimInfo fehlgeschlagen (ExitCode=$($res.ExitCode)). $msg"
    }

    $text = $res.StdOut
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    $lines = $text -split "`r?`n"

    $list = New-Object System.Collections.Generic.List[object]

    $script:curMountDir   = $null
    $script:curImageFile  = $null
    $script:curImageIndex = $null
    $script:curStatus     = $null
    $script:curRw         = $null

    function Flush-Current {
        if (-not $script:curMountDir) { return }

        $ix = $null
        if ($script:curImageIndex) {
            try { $ix = [int]$script:curImageIndex } catch { $ix = $null }
        }

        $list.Add([pscustomobject]@{
            MountDir   = $script:curMountDir
            ImageFile  = $script:curImageFile
            ImageIndex = $ix
            Status     = $script:curStatus
            ReadWrite  = $script:curRw
        }) | Out-Null
    }

    foreach ($ln in $lines) {
        $line = $ln.Trim()
        if ($line.Length -eq 0) { continue }

        if ($line -match '^Mount\s+Dir\s*:\s*(.+)\s*$') {
            Flush-Current
            $script:curMountDir   = $matches[1].Trim()
            $script:curImageFile  = $null
            $script:curImageIndex = $null
            $script:curStatus     = $null
            $script:curRw         = $null
            continue
        }

        if ($line -match '^Image\s+File\s*:\s*(.+)\s*$') {
            $script:curImageFile = $matches[1].Trim()
            continue
        }

        if ($line -match '^Image\s+Index\s*:\s*(\d+)\s*$') {
            $script:curImageIndex = $matches[1].Trim()
            continue
        }

        if ($line -match '^Mount\s+Status\s*:\s*(.+)\s*$') {
            $script:curStatus = $matches[1].Trim()
            continue
        }

        if ($line -match '^(Mount\s+Mode|Mounted\s+Read/Write|Read/Write|Read-Write)\s*:\s*(.+)\s*$') {
            $script:curRw = $matches[2].Trim()
            continue
        }

        if ($line -match '^Read\s+Only\s*:\s*(.+)\s*$') {
            $script:curRw = ("ReadOnly={0}" -f $matches[1].Trim())
            continue
        }
    }

    Flush-Current
    return @($list.ToArray())
}

Export-ModuleMember -Function Get-MountedWimList