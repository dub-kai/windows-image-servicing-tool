Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-UniqueExistingPaths {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Paths
    )

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $items = New-Object System.Collections.Generic.List[string]

    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }

        $full = $null
        try { $full = [System.IO.Path]::GetFullPath([string]$path) } catch { $full = [string]$path }
        if ([string]::IsNullOrWhiteSpace($full)) { continue }
        if (-not (Test-Path -LiteralPath $full)) { continue }
        if (-not $seen.Add($full)) { continue }

        $items.Add($full) | Out-Null
    }

    return @($items.ToArray())
}

function Resolve-AdkRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { $full = $Path }
    if (-not (Test-Path -LiteralPath $full)) { return $null }

    $directTools = Join-Path $full 'Deployment Tools'
    $directWinPe = Join-Path $full 'Windows Preinstallation Environment'
    if ((Test-Path -LiteralPath $directTools) -or (Test-Path -LiteralPath $directWinPe)) {
        return $full
    }

    $nested = Join-Path $full 'Assessment and Deployment Kit'
    if (Test-Path -LiteralPath $nested) {
        return $nested
    }

    return $null
}

function Get-AdkRegistryRoots {
    [CmdletBinding()]
    param()

    $items = New-Object System.Collections.Generic.List[string]
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
    )

    foreach ($key in $keys) {
        try {
            $props = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        } catch {
            continue
        }

        foreach ($name in @('KitsRoot11','KitsRoot10','KitsRoot81')) {
            try {
                $value = [string]$props.$name
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $items.Add($value) | Out-Null
                }
            } catch {}
        }
    }

    return Get-UniqueExistingPaths -Paths @($items.ToArray())
}

function Find-AdkRoots {
    [CmdletBinding()]
    param()

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($root in @(Get-AdkRegistryRoots)) {
        $resolved = Resolve-AdkRoot -Path $root
        if ($resolved) { $candidates.Add($resolved) | Out-Null }
    }

    foreach ($root in @(
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'),
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\11'),
        (Join-Path $env:ProgramFiles 'Windows Kits\10'),
        (Join-Path $env:ProgramFiles 'Windows Kits\11')
    )) {
        $resolved = Resolve-AdkRoot -Path $root
        if ($resolved) { $candidates.Add($resolved) | Out-Null }
    }

    return Get-UniqueExistingPaths -Paths @($candidates.ToArray())
}

function Resolve-WinPeRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AdkRoot,

        [Parameter()]
        [string]$ConfiguredWinPeRoot
    )

    foreach ($candidate in @(
        $ConfiguredWinPeRoot,
        $(if ($AdkRoot) { Join-Path $AdkRoot 'Windows Preinstallation Environment' }),
        $(if ($AdkRoot) { Join-Path $AdkRoot 'Windows PE' })
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        if (Test-Path -LiteralPath $candidate) { return [System.IO.Path]::GetFullPath($candidate) }
    }

    return $null
}

function Resolve-OscdimgPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AdkRoot,

        [Parameter()]
        [string]$ConfiguredOscdimgPath
    )

    foreach ($candidate in @(
        $ConfiguredOscdimgPath,
        $(if ($AdkRoot) { Join-Path $AdkRoot 'Deployment Tools\amd64\Oscdimg\oscdimg.exe' }),
        $(if ($AdkRoot) { Join-Path $AdkRoot 'Deployment Tools\x86\Oscdimg\oscdimg.exe' })
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [System.IO.Path]::GetFullPath($candidate) }
    }

    return $null
}

function Resolve-AdkCommandPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$WinPeRoot,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    foreach ($candidate in @(
        $(if ($WinPeRoot) { Join-Path $WinPeRoot $FileName }),
        $(if ($WinPeRoot) { Join-Path $WinPeRoot ('amd64\' + $FileName) }),
        $(if ($WinPeRoot) { Join-Path $WinPeRoot ('x86\' + $FileName) })
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [System.IO.Path]::GetFullPath($candidate) }
    }

    return $null
}

function Get-AdkStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ConfiguredAdkRoot,

        [Parameter()]
        [string]$ConfiguredWinPeRoot,

        [Parameter()]
        [string]$ConfiguredOscdimgPath
    )

    $detectedRoot = $null
    $configuredResolved = Resolve-AdkRoot -Path $ConfiguredAdkRoot
    if ($configuredResolved) {
        $detectedRoot = $configuredResolved
    } else {
        $detectedRoot = @(Find-AdkRoots) | Select-Object -First 1
    }

    $winPeRoot = Resolve-WinPeRoot -AdkRoot $detectedRoot -ConfiguredWinPeRoot $ConfiguredWinPeRoot
    $oscdimgPath = Resolve-OscdimgPath -AdkRoot $detectedRoot -ConfiguredOscdimgPath $ConfiguredOscdimgPath
    $copypePath = Resolve-AdkCommandPath -WinPeRoot $winPeRoot -FileName 'copype.cmd'
    $makeWinPeMediaPath = Resolve-AdkCommandPath -WinPeRoot $winPeRoot -FileName 'MakeWinPEMedia.cmd'

    return [pscustomobject]@{
        AdkRoot            = $detectedRoot
        WinPeRoot          = $winPeRoot
        OscdimgPath        = $oscdimgPath
        CopypePath         = $copypePath
        MakeWinPEMediaPath = $makeWinPeMediaPath
        HasAdkRoot         = (-not [string]::IsNullOrWhiteSpace([string]$detectedRoot))
        HasWinPe           = (-not [string]::IsNullOrWhiteSpace([string]$winPeRoot))
        HasOscdimg         = (-not [string]::IsNullOrWhiteSpace([string]$oscdimgPath))
        HasCopype          = (-not [string]::IsNullOrWhiteSpace([string]$copypePath))
        HasMakeWinPeMedia  = (-not [string]::IsNullOrWhiteSpace([string]$makeWinPeMediaPath))
    }
}

Export-ModuleMember -Function `
    Get-AdkRegistryRoots, `
    Find-AdkRoots, `
    Get-AdkStatus, `
    Resolve-AdkRoot, `
    Resolve-WinPeRoot, `
    Resolve-OscdimgPath
