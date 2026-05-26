Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Import-MountedWimDependencies {
    [CmdletBinding()]
    param()

    $bootstrapPath = Join-Path $PSScriptRoot '..\Core\Bootstrap.psm1'
    Import-Module $bootstrapPath -Global -Force -DisableNameChecking | Out-Null

    $dismPath = Resolve-ProjectPath 'Services\DismService.psm1' -MustExist
    Import-Module $dismPath -Global -Force -DisableNameChecking | Out-Null
}

function Normalize-MountedWimPath {
    [CmdletBinding()]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch {
        return $Path.TrimEnd('\')
    }
}

function Convert-MountedWimRegistryStatus {
    [CmdletBinding()]
    param([Nullable[int]]$StatusCode)

    if ($null -eq $StatusCode) {
        return [pscustomobject]@{
            Health            = 'Unbekannt'
            HealthHint        = 'DISM hat keinen eindeutigen Mount-Zustand geliefert.'
            RecommendedAction = 'Refresh oder DISM-Log prüfen'
            CanCommit         = $false
            CanDiscard        = $true
        }
    }

    switch ([int]$StatusCode) {
        2 {
            return [pscustomobject]@{
                Health            = 'OK'
                HealthHint        = 'Mount ist normal aktiv.'
                RecommendedAction = 'Commit oder Discard möglich'
                CanCommit         = $true
                CanDiscard        = $true
            }
        }
        3 {
            return [pscustomobject]@{
                Health            = 'Teilweise ausgehängt'
                HealthHint        = 'DISM meldet einen teilweisen Unmount. Commit darf nicht erneut ausgeführt werden.'
                RecommendedAction = 'Mount bereinigen'
                CanCommit         = $false
                CanDiscard        = $true
            }
        }
        default {
            return [pscustomobject]@{
                Health            = ("Unklar ({0})" -f [int]$StatusCode)
                HealthHint        = 'Der Mount hat einen unerwarteten WIMMount-Status.'
                RecommendedAction = 'DISM-Log prüfen oder ohne Commit bereinigen'
                CanCommit         = $false
                CanDiscard        = $true
            }
        }
    }
}

function Test-MountedWimReadOnlyText {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$ReadWrite)

    if ([string]::IsNullOrWhiteSpace($ReadWrite)) { return $false }

    $x = $ReadWrite.ToLowerInvariant()
    if ($x -match 'readonly') { return $true }
    if ($x -match 'read\s*only') { return $true }
    if ($x -match '^no$') { return $true }
    if ($x -match '^false$') { return $true }
    if ($x -match 'readonly\s*=\s*yes') { return $true }

    return $false
}

function Test-MountedWimReadWriteText {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$ReadWrite)

    if ([string]::IsNullOrWhiteSpace($ReadWrite)) { return $false }
    if (Test-MountedWimReadOnlyText -ReadWrite $ReadWrite) { return $false }

    $x = $ReadWrite.ToLowerInvariant()
    if ($x -match 'read/write') { return $true }
    if ($x -match 'readwrite') { return $true }
    if ($x -match '^yes$') { return $true }
    if ($x -match '^true$') { return $true }
    if ($x -match '\brw\b') { return $true }

    return $false
}

function Get-MountedWimKind {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$ImageFile)

    if ([string]::IsNullOrWhiteSpace($ImageFile)) { return 'Unbekannt' }

    try {
        $leaf = [System.IO.Path]::GetFileName($ImageFile)
        if ($leaf -ieq 'boot.wim') { return 'Boot/WinPE' }
        if ($leaf -ieq 'winre.wim') { return 'Recovery' }
        if ($leaf -match '(?i)^install\.(wim|esd)$') { return 'Install-Image' }
    } catch {}

    return 'Image'
}

function Get-MountedWimCapability {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$ImageFile,
        [AllowEmptyString()][string]$ReadWrite,
        [AllowEmptyString()][string]$Health,
        [bool]$RegistryOnly = $false,
        [bool]$CanCommit = $false,
        [bool]$CanDiscard = $false
    )

    $kind = Get-MountedWimKind -ImageFile $ImageFile
    $isReadOnly = Test-MountedWimReadOnlyText -ReadWrite $ReadWrite
    $isWritable = Test-MountedWimReadWriteText -ReadWrite $ReadWrite
    $isHealthy = ([string]::IsNullOrWhiteSpace($Health) -or $Health -eq 'OK')

    $capability = 'Prüfen'
    $guidance = 'Mount-Zustand prüfen, bevor du Updates, Treiber oder Commit ausführst.'
    $canIntegrateUpdates = $false

    if ($RegistryOnly) {
        $capability = 'Bereinigung nötig'
        $guidance = 'DISM führt diesen Mount nur noch als Rest. Bitte über Images reparieren oder Cleanup-Wim ausführen.'
    }
    elseif (-not $isHealthy) {
        $capability = 'Problem'
        $guidance = 'Mount ist nicht im normalen Zustand. Erst bereinigen oder DISM-Log prüfen, nicht committen.'
    }
    elseif ($isReadOnly) {
        $capability = 'Nur lesen'
        $guidance = 'ReadOnly-Mount: Anzeigen und Export sind ok, Updates/Treiber/Commit sind gesperrt.'
    }
    elseif ($kind -eq 'Boot/WinPE') {
        $capability = 'Boot/WinPE'
        $guidance = 'Boot-/WinPE-Image: normale Windows-Updates werden nicht automatisch integriert. Nur gezielte WinPE-/Treiber-Arbeiten.'
    }
    elseif ($isWritable -and $CanCommit) {
        $capability = 'Bearbeitbar'
        $guidance = 'Read/Write und gesund: Updates, Treiber und Commit sind möglich.'
        $canIntegrateUpdates = $true
    }
    elseif ($CanDiscard) {
        $capability = 'Nur bereinigen'
        $guidance = 'Commit ist nicht sicher freigegeben. Discard/Bereinigung ist möglich.'
    }

    return [pscustomobject]@{
        MountKind           = $kind
        IsReadOnly          = [bool]$isReadOnly
        IsReadWrite         = [bool]$isWritable
        MountCapability     = $capability
        MountGuidance       = $guidance
        CanIntegrateUpdates = [bool]$canIntegrateUpdates
    }
}

function Get-WimMountRegistryEntries {
    [CmdletBinding()]
    param()

    $base = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
    if (-not (Test-Path -LiteralPath $base)) { return @() }

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
        try {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop

            $mountProp = $props.PSObject.Properties['Mount Path']
            if ($null -eq $mountProp -or [string]::IsNullOrWhiteSpace([string]$mountProp.Value)) { continue }

            $status = $null
            $statusProp = $props.PSObject.Properties['Status']
            if ($statusProp) { try { $status = [int]$statusProp.Value } catch { $status = $null } }

            $wimPath = $null
            $wimProp = $props.PSObject.Properties['WIM Path']
            if ($wimProp) { $wimPath = [string]$wimProp.Value }

            $imageIndex = $null
            $indexProp = $props.PSObject.Properties['Image Index']
            if ($indexProp) { try { $imageIndex = [int]$indexProp.Value } catch { $imageIndex = $null } }

            $health = Convert-MountedWimRegistryStatus -StatusCode $status
            $capability = Get-MountedWimCapability `
                -ImageFile $wimPath `
                -ReadWrite '-' `
                -Health ([string]$health.Health) `
                -RegistryOnly $true `
                -CanCommit ([bool]$health.CanCommit) `
                -CanDiscard ([bool]$health.CanDiscard)

            $items.Add([pscustomobject]@{
                Key               = [string]$key.PSChildName
                MountDir          = [string]$mountProp.Value
                MountDirKey       = Normalize-MountedWimPath -Path ([string]$mountProp.Value)
                ImageFile         = $wimPath
                ImageIndex        = $imageIndex
                StatusCode        = $status
                Health            = [string]$health.Health
                HealthHint        = [string]$health.HealthHint
                RecommendedAction = [string]$health.RecommendedAction
                CanCommit         = [bool]$health.CanCommit
                CanDiscard        = [bool]$health.CanDiscard
                MountKind         = [string]$capability.MountKind
                IsReadOnly        = [bool]$capability.IsReadOnly
                IsReadWrite       = [bool]$capability.IsReadWrite
                MountCapability   = [string]$capability.MountCapability
                MountGuidance     = [string]$capability.MountGuidance
                CanIntegrateUpdates = [bool]$capability.CanIntegrateUpdates
                RegistryOnly      = $true
            }) | Out-Null
        } catch {}
    }

    return @($items.ToArray())
}

function Add-MountedWimRegistryHealth {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Items = @())

    $registryEntries = @(Get-WimMountRegistryEntries)
    $registryByMount = @{}
    foreach ($entry in $registryEntries) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.MountDirKey)) {
            $registryByMount[[string]$entry.MountDirKey] = $entry
        }
    }

    $merged = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($item in @($Items)) {
        $mountDir = [string]$item.MountDir
        $key = Normalize-MountedWimPath -Path $mountDir
        $registry = if ($key -and $registryByMount.ContainsKey($key)) { $registryByMount[$key] } else { $null }

        $statusCode = $null
        $health = $null
        if ($registry) {
            $statusCode = $registry.StatusCode
            $health = Convert-MountedWimRegistryStatus -StatusCode $statusCode
            $seen[$key] = $true
        } else {
            $health = [pscustomobject]@{
                Health            = 'OK'
                HealthHint        = 'DISM meldet den Mount als aktiv.'
                RecommendedAction = 'Commit oder Discard möglich'
                CanCommit         = $true
                CanDiscard        = $true
            }
        }

        $effectiveImageFile = if ($registry -and -not [string]::IsNullOrWhiteSpace([string]$registry.ImageFile)) { [string]$registry.ImageFile } else { [string]$item.ImageFile }
        $capability = Get-MountedWimCapability `
            -ImageFile $effectiveImageFile `
            -ReadWrite ([string]$item.ReadWrite) `
            -Health ([string]$health.Health) `
            -RegistryOnly $false `
            -CanCommit ([bool]$health.CanCommit) `
            -CanDiscard ([bool]$health.CanDiscard)

        $merged.Add([pscustomobject]@{
            MountDir          = $mountDir
            ImageFile         = $effectiveImageFile
            ImageIndex        = if ($registry -and $null -ne $registry.ImageIndex) { $registry.ImageIndex } else { $item.ImageIndex }
            Status            = [string]$item.Status
            StatusCode        = $statusCode
            ReadWrite         = [string]$item.ReadWrite
            Health            = [string]$health.Health
            HealthHint        = [string]$health.HealthHint
            RecommendedAction = [string]$health.RecommendedAction
            CanCommit         = [bool]$health.CanCommit
            CanDiscard        = [bool]$health.CanDiscard
            MountKind         = [string]$capability.MountKind
            IsReadOnly        = [bool]$capability.IsReadOnly
            IsReadWrite       = [bool]$capability.IsReadWrite
            MountCapability   = [string]$capability.MountCapability
            MountGuidance     = [string]$capability.MountGuidance
            CanIntegrateUpdates = [bool]$capability.CanIntegrateUpdates
            RegistryOnly      = $false
        }) | Out-Null
    }

    foreach ($entry in $registryEntries) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.MountDirKey)) { continue }
        if ($seen.ContainsKey([string]$entry.MountDirKey)) { continue }

        $registryOnlyHealth = 'Registry-Rest'
        $registryOnlyHint = if ($entry.StatusCode -eq 3) {
            'DISM führt diesen Pfad nur noch in der WIMMount-Registry, aber nicht mehr als gültigen Mount. Normaler Unmount funktioniert hier nicht.'
        } else {
            'Der Mount steht noch in der WIMMount-Registry, wird von DISM aber nicht mehr normal gelistet.'
        }
        $capability = Get-MountedWimCapability `
            -ImageFile ([string]$entry.ImageFile) `
            -ReadWrite '-' `
            -Health $registryOnlyHealth `
            -RegistryOnly $true `
            -CanCommit $false `
            -CanDiscard $false

        $merged.Add([pscustomobject]@{
            MountDir          = [string]$entry.MountDir
            ImageFile         = [string]$entry.ImageFile
            ImageIndex        = $entry.ImageIndex
            Status            = 'Nicht in DISM-Liste'
            StatusCode        = $entry.StatusCode
            ReadWrite         = '-'
            Health            = $registryOnlyHealth
            HealthHint        = $registryOnlyHint
            RecommendedAction = 'DISM Cleanup-Wim'
            CanCommit         = $false
            CanDiscard        = $false
            MountKind         = [string]$capability.MountKind
            IsReadOnly        = [bool]$capability.IsReadOnly
            IsReadWrite       = [bool]$capability.IsReadWrite
            MountCapability   = [string]$capability.MountCapability
            MountGuidance     = [string]$capability.MountGuidance
            CanIntegrateUpdates = [bool]$capability.CanIntegrateUpdates
            RegistryOnly      = $true
        }) | Out-Null
    }

    return @($merged.ToArray())
}

function Get-MountedWimList {
    [CmdletBinding()]
    param()

    Import-MountedWimDependencies
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
    return @(Add-MountedWimRegistryHealth -Items @($list.ToArray()))
}

Export-ModuleMember -Function Get-MountedWimList
