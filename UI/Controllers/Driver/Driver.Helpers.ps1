function New-WorkerScript {
    param([Parameter(Mandatory)][string]$Code)
    return [scriptblock]::Create($Code)
}

function Get-DisplayValue {
    param([object]$Value)

    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return "-" }
    return $s
}

function ConvertTo-InboxBool {
    param([string]$InboxText)

    $x = ([string]$InboxText).Trim().ToLowerInvariant()

    if ($x -in @('yes','true','ja','1'))   { return $true }
    if ($x -in @('no','false','nein','0')) { return $false }

    return $null
}

function Test-DriverMountUsable {
    param([string]$MountDir)

    if ([string]::IsNullOrWhiteSpace($MountDir)) { return $false }

    try {
        return (Test-Path -LiteralPath $MountDir -PathType Container)
    } catch {
        return $false
    }
}

function Assert-DriverMountUsable {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [string]$Message = "Kein gültiges MountDir ausgewählt."
    )

    if (-not (Test-DriverMountUsable -MountDir $MountDir)) {
        throw $Message
    }

    return $true
}

function Write-DriverMountLog {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [string]$MountDir
    )

    try {
        if ([string]::IsNullOrWhiteSpace($MountDir)) {
            Write-Log -Level INFO -Message ("Driver:{0} using MountDir=<leer>" -f $Operation)
        } else {
            Write-Log -Level INFO -Message ("Driver:{0} using MountDir={1}" -f $Operation, $MountDir)
        }
    } catch {}
}

function Test-DriverTransientDismError {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    $m = [string]$Message

    if ($m -match '(?i)An error occurred closing a servicing component in the image') { return $true }
    if ($m -match '(?i)Wait a few minutes and try running the command again') { return $true }
    if ($m -match '(?i)The system cannot find the path specified') { return $true }
    if ($m -match '(?i)cannot find the file specified') { return $true }
    if ($m -match '(?i)No driver packages were found on the specified path') { return $true }
    if ($m -match '(?i)problem opening the INF file') { return $true }
    if ($m -match '(?i)Unable to access the image') { return $true }

    return $false
}