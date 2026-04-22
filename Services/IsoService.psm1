Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# File-Dialog (WPF)
try { Add-Type -AssemblyName PresentationFramework | Out-Null } catch {}

function Select-IsoFile {
    [CmdletBinding()]
    param()

    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "ISO auswählen"
    $dlg.Filter = "ISO (*.iso)|*.iso|Alle Dateien (*.*)|*.*"
    $dlg.Multiselect = $false

    $ok = $dlg.ShowDialog()
    if ($ok) { return $dlg.FileName }
    return $null
}

function Get-IsoDriveRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath,

        [int]$RetryCount = 25,
        [int]$RetryDelayMs = 200
    )

    for ($i = 0; $i -lt $RetryCount; $i++) {
        try {
            $di = Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop

            $vols = @()
            try { $vols = @($di | Get-Volume -ErrorAction Stop) } catch { $vols = @() }

            $vol = $vols | Where-Object { $_.DriveLetter } | Select-Object -First 1
            if ($vol -and $vol.DriveLetter) {
                return ("{0}:\\" -f $vol.DriveLetter)
            }
        } catch {
            # noch nicht verfügbar
        }

        Start-Sleep -Milliseconds $RetryDelayMs
    }

    throw "Konnte kein Laufwerk für ISO ermitteln (kein DriveLetter nach Mount)."
}

function Get-WindowsInstallMediaFromRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoRoot
    )

    if (-not (Test-Path -LiteralPath $IsoRoot)) {
        throw "IsoRoot existiert nicht: $IsoRoot"
    }

    $sources = Join-Path $IsoRoot "sources"
    if (-not (Test-Path -LiteralPath $sources)) {
        throw "Kein 'sources' Ordner gefunden unter: $IsoRoot"
    }

    $boot        = Join-Path $sources "boot.wim"
    $installWim  = Join-Path $sources "install.wim"
    $installEsd  = Join-Path $sources "install.esd"

    $bootPath = $null
    if (Test-Path -LiteralPath $boot) {
        $bootPath = $boot
    }

    $installPath = $null
    if (Test-Path -LiteralPath $installWim) {
        $installPath = $installWim
    } elseif (Test-Path -LiteralPath $installEsd) {
        $installPath = $installEsd
    }

    return [pscustomobject]@{
        IsoRoot          = $IsoRoot
        SourcesDir       = $sources
        BootImagePath    = $bootPath
        InstallImagePath = $installPath
    }
}

function Mount-IsoFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    if (-not (Test-Path -LiteralPath $IsoPath)) {
        throw "ISO Datei nicht gefunden: $IsoPath"
    }

    $retryCount = 25
    $retryDelay = 200

    try {
        $cfgRetry = Get-ConfigValue -Key "IsoMountRetry" -Default $null
        if ($cfgRetry) {
            if ($cfgRetry.ContainsKey("Count"))   { $retryCount = [int]$cfgRetry["Count"] }
            if ($cfgRetry.ContainsKey("DelayMs")) { $retryDelay = [int]$cfgRetry["DelayMs"] }
        }
    } catch {
        # Config evtl. noch nicht da -> defaults
    }

    $alreadyAttached = $false
    try {
        $di = Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop
        $alreadyAttached = [bool]$di.Attached
    } catch {
        $alreadyAttached = $false
    }

    if (-not $alreadyAttached) {
        try { Write-Log -Level INFO -Message ("ISO mounten: {0}" -f $IsoPath) } catch {}
        Mount-DiskImage -ImagePath $IsoPath -ErrorAction Stop | Out-Null
    } else {
        try { Write-Log -Level INFO -Message ("ISO bereits gemountet: {0}" -f $IsoPath) } catch {}
    }

    $root  = Get-IsoDriveRoot -IsoPath $IsoPath -RetryCount $retryCount -RetryDelayMs $retryDelay
    $media = Get-WindowsInstallMediaFromRoot -IsoRoot $root

    return [pscustomobject]@{
        IsoPath          = $IsoPath
        IsoRoot          = $media.IsoRoot
        BootImagePath    = $media.BootImagePath
        InstallImagePath = $media.InstallImagePath
    }
}

function Dismount-IsoFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    try {
        $di = Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop
        if ($di.Attached) {
            try { Write-Log -Level INFO -Message ("ISO aushängen: {0}" -f $IsoPath) } catch {}
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction Stop | Out-Null
        }
    } catch {
        # idempotent
        try { Write-Log -Level WARN -Message ("ISO aushängen (ignoriert): {0}" -f $_.Exception.Message) } catch {}
    }
}

function Find-MountedInstallMediaCandidates {
    [CmdletBinding()]
    param()

    $candidates = New-Object System.Collections.Generic.List[object]

    $vols = @(Get-CimInstance -ClassName Win32_Volume -Filter "DriveType=5" -ErrorAction SilentlyContinue)
    foreach ($v in $vols) {
        if (-not $v.DriveLetter) { continue }
        $root = ("{0}:\\" -f $v.DriveLetter)

        try {
            $media = Get-WindowsInstallMediaFromRoot -IsoRoot $root
            if ($media.InstallImagePath) {
                $candidates.Add([pscustomobject]@{
                    IsoRoot          = $media.IsoRoot
                    BootImagePath    = $media.BootImagePath
                    InstallImagePath = $media.InstallImagePath
                })
            }
        } catch {
            # ignore
        }
    }

    return $candidates
}

Export-ModuleMember -Function `
    Select-IsoFile, `
    Get-IsoDriveRoot, `
    Get-WindowsInstallMediaFromRoot, `
    Mount-IsoFile, `
    Dismount-IsoFile, `
    Find-MountedInstallMediaCandidates