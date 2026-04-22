Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-MountedIsoRoots {
    <#
      Returns drive roots like "H:\" for mounted ISOs / CD-ROM drives.
      Uses .NET DriveInfo first (robust), CIM as supplemental.
    #>
    $roots = New-Object System.Collections.Generic.List[string]

    # Primary: .NET DriveInfo (fast, no WMI dependency)
    try {
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            try {
                if ($d.DriveType -eq [System.IO.DriveType]::CDRom) {
                    $r = [string]$d.RootDirectory.FullName
                    if (-not [string]::IsNullOrWhiteSpace($r)) {
                        if (-not $r.EndsWith('\')) { $r += '\' }
                        $roots.Add($r) | Out-Null
                    }
                }
            } catch {}
        }
    } catch {}

    # Secondary: Win32_Volume DriveType=5 (CDROM)
    try {
        $vols = Get-CimInstance -ClassName Win32_Volume -Filter "DriveType=5 AND DriveLetter IS NOT NULL" -ErrorAction Stop
        foreach ($v in $vols) {
            $dl = [string]$v.DriveLetter
            if ([string]::IsNullOrWhiteSpace($dl)) { continue }
            if (-not $dl.EndsWith('\')) { $dl += '\' }
            $roots.Add($dl) | Out-Null
        }
    } catch {}

    return ($roots | Select-Object -Unique)
}

function Find-MountedWindowsInstallMedia {
    <#
      Finds mounted media that looks like Windows install media.
      Indicator: \sources\install.wim OR \sources\install.esd and/or \sources\boot.wim

      Returns objects: Root, Install, Boot, Score
      Score prefers Install+Boot (3) > Install only (2) > Boot only (1)
    #>
    $hits = @()

    foreach ($root in (Get-MountedIsoRoots)) {
        $r = [string]$root
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        if (-not $r.EndsWith('\')) { $r += '\' }

        $installWim = Join-Path $r 'sources\install.wim'
        $installEsd = Join-Path $r 'sources\install.esd'
        $bootWim    = Join-Path $r 'sources\boot.wim'

        $install = $null
        if (Test-Path -LiteralPath $installWim) { $install = $installWim }
        elseif (Test-Path -LiteralPath $installEsd) { $install = $installEsd }

        $boot = $null
        if (Test-Path -LiteralPath $bootWim) { $boot = $bootWim }

        if ($install -or $boot) {
            # PS5.1 safe score (keine "if"-Ausdrücke in Klammern)
            $score = ([int][bool]$install) * 2 + ([int][bool]$boot) * 1

            $hits += [pscustomobject]@{
                Root    = $r
                Install = $install
                Boot    = $boot
                Score   = $score
            }
        }
    }

    return $hits
}

function Sync-IsoStateFromMountedMedia {
    <#
      Synchronizes AppState for ISO Boot/Install paths based on mounted media.

      Behavior:
      - If existing AppState values are set but files no longer exist -> clear them (unmounted).
      - If both are empty -> scan mounted ISO roots for install.wim/esd and/or boot.wim.
      - Set:
          IsoRootPath (optional)
          IsoInstallImagePath (install.wim/esd)
          BootImagePath (boot.wim)
      - Does NOT overwrite existing valid values.
    #>

    if (-not (Get-Command Get-AppStateValue -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command Set-AppStateValue -ErrorAction SilentlyContinue)) { return }

    $curInstall = $null
    $curBoot    = $null

    try { $curInstall = Get-AppStateValue -Key 'IsoInstallImagePath' -Default $null } catch {}
    try { $curBoot    = Get-AppStateValue -Key 'BootImagePath'       -Default $null } catch {}

    if ($curInstall -and -not (Test-Path -LiteralPath $curInstall)) {
        try { Set-AppStateValue -Key 'IsoInstallImagePath' -Value $null } catch {}
        $curInstall = $null
    }
    if ($curBoot -and -not (Test-Path -LiteralPath $curBoot)) {
        try { Set-AppStateValue -Key 'BootImagePath' -Value $null } catch {}
        $curBoot = $null
    }

    # If already set and valid, keep it
    if ($curInstall -or $curBoot) { return }

    $hits = Find-MountedWindowsInstallMedia
    if (@($hits).Count -lt 1) { return }

    $best = $hits | Sort-Object -Property Score -Descending | Select-Object -First 1

    try { Set-AppStateValue -Key 'IsoRootPath' -Value $best.Root } catch {}

    if ($best.Install) {
        try { Set-AppStateValue -Key 'IsoInstallImagePath' -Value $best.Install } catch {}
    }
    if ($best.Boot) {
        try { Set-AppStateValue -Key 'BootImagePath' -Value $best.Boot } catch {}
    }
}

Export-ModuleMember -Function Get-MountedIsoRoots, Find-MountedWindowsInstallMedia, Sync-IsoStateFromMountedMedia