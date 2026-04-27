Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Import-IsoBuildDependencies {
    [CmdletBinding()]
    param()

    $bootstrapPath = Join-Path $PSScriptRoot '..\Core\Bootstrap.psm1'
    Import-Module $bootstrapPath -Global -Force -DisableNameChecking | Out-Null

    $configPath = Resolve-ProjectPath 'Core\Config.psm1' -MustExist
    $adkPath = Resolve-ProjectPath 'Services\AdkService.psm1' -MustExist

    Import-Module $configPath -Global -Force -DisableNameChecking | Out-Null
    Import-Module $adkPath -Global -Force -DisableNameChecking | Out-Null
}

function Write-IsoBuildLog {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')] [string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level $Level -Message $Message
        }
    } catch {}
}

function Get-IsoBuildWorkingRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$WorkingRoot
    )

    Import-IsoBuildDependencies

    if (-not [string]::IsNullOrWhiteSpace($WorkingRoot)) {
        return [System.IO.Path]::GetFullPath($WorkingRoot)
    }

    return (Resolve-ProjectPath 'Work\IsoBuild')
}

function Get-IsoBuildVolumeLabel {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$VolumeLabel,

        [Parameter()]
        [string]$SourceRoot
    )

    $label = [string]$VolumeLabel
    if ([string]::IsNullOrWhiteSpace($label)) {
        try {
            $drive = Get-PSDrive -Name ([System.IO.Path]::GetPathRoot($SourceRoot).TrimEnd('\',':')) -ErrorAction Stop
            $label = [string]$drive.Description
        } catch {
            $label = 'CUSTOM_WIN'
        }
    }

    $clean = ($label -replace '[^A-Za-z0-9_]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($clean)) {
        $clean = 'CUSTOM_WIN'
    }

    if ($clean.Length -gt 32) {
        $clean = $clean.Substring(0, 32)
    }

    return $clean.ToUpperInvariant()
}

function Copy-IsoBuildSourceTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$StageRoot
    )

    if (-not (Test-Path -LiteralPath $StageRoot)) {
        $null = New-Item -ItemType Directory -Path $StageRoot -Force
    }

    Copy-Item -Path (Join-Path $SourceRoot '*') -Destination $StageRoot -Recurse -Force
}

function Resolve-IsoBuildBootData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StageRoot
    )

    $biosBoot = Join-Path $StageRoot 'boot\etfsboot.com'
    $efiCandidates = @(
        (Join-Path $StageRoot 'efi\microsoft\boot\efisys.bin'),
        (Join-Path $StageRoot 'efi\microsoft\boot\efisys_noprompt.bin')
    )
    $efiBoot = $efiCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    if ((Test-Path -LiteralPath $biosBoot -PathType Leaf) -and $efiBoot) {
        return ('-bootdata:2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $biosBoot, $efiBoot)
    }

    if (Test-Path -LiteralPath $biosBoot -PathType Leaf) {
        return ('-b"{0}"' -f $biosBoot)
    }

    if ($efiBoot) {
        return ('-bootdata:1#pEF,e,b"{0}"' -f $efiBoot)
    }

    throw "Keine bootfähigen ISO-Startdateien in der Stage gefunden."
}

function Update-IsoBuildImagesInStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter()][string]$InstallImagePath,
        [Parameter()][string]$BootImagePath
    )

    $sourcesDir = Join-Path $StageRoot 'sources'
    if (-not (Test-Path -LiteralPath $sourcesDir -PathType Container)) {
        throw "Stage enthält keinen sources-Ordner: $sourcesDir"
    }

    $installDest = $null
    if (-not [string]::IsNullOrWhiteSpace($InstallImagePath)) {
        if (-not (Test-Path -LiteralPath $InstallImagePath -PathType Leaf)) {
            throw "Install-Image nicht gefunden: $InstallImagePath"
        }

        foreach ($existing in @(
            (Join-Path $sourcesDir 'install.wim'),
            (Join-Path $sourcesDir 'install.esd')
        )) {
            if (Test-Path -LiteralPath $existing -PathType Leaf) {
                Remove-Item -LiteralPath $existing -Force
            }
        }

        $ext = [System.IO.Path]::GetExtension($InstallImagePath)
        if ($ext -notin @('.wim', '.esd')) {
            $ext = '.wim'
        }

        $installDest = Join-Path $sourcesDir ('install{0}' -f $ext.ToLowerInvariant())
        Copy-Item -LiteralPath $InstallImagePath -Destination $installDest -Force
    }

    $bootDest = $null
    if (-not [string]::IsNullOrWhiteSpace($BootImagePath)) {
        if (-not (Test-Path -LiteralPath $BootImagePath -PathType Leaf)) {
            throw "Boot-Image nicht gefunden: $BootImagePath"
        }

        $bootDest = Join-Path $sourcesDir 'boot.wim'
        Copy-Item -LiteralPath $BootImagePath -Destination $bootDest -Force
    }

    return [pscustomobject]@{
        InstallImagePath = $installDest
        BootImagePath    = $bootDest
    }
}

function Invoke-OscdimgBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OscdimgPath,
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$VolumeLabel
    )

    $bootArg = Resolve-IsoBuildBootData -StageRoot $StageRoot
    $args = @(
        '-m',
        '-o',
        '-u2',
        '-udfver102',
        ('-l{0}' -f $VolumeLabel),
        $bootArg,
        $StageRoot,
        $OutputPath
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $OscdimgPath
    $psi.Arguments = [string]::Join(' ', $args)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw ("oscdimg fehlgeschlagen (ExitCode={0}).`n`nSTDOUT:`n{1}`nSTDERR:`n{2}" -f $process.ExitCode, $stdout, $stderr)
    }

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Command  = ('"{0}" {1}' -f $OscdimgPath, $psi.Arguments)
    }
}

function Build-WindowsIso {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$InstallImagePath,
        [Parameter()][string]$BootImagePath,
        [Parameter()][string]$OscdimgPath,
        [Parameter()][string]$WorkingRoot,
        [Parameter()][string]$VolumeLabel
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        throw "ISO-Quellordner nicht gefunden: $SourceRoot"
    }

    Import-IsoBuildDependencies

    $outputDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutputPath))
    if ([string]::IsNullOrWhiteSpace($outputDir)) {
        throw "Konnte Zielordner für ISO nicht bestimmen: $OutputPath"
    }
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $outputDir -Force
    }

    $adkStatus = Get-AdkStatus `
        -ConfiguredAdkRoot (Get-ConfigValue -Key 'AdkRoot' -Default $null) `
        -ConfiguredWinPeRoot (Get-ConfigValue -Key 'WinPeRoot' -Default $null) `
        -ConfiguredOscdimgPath (Get-ConfigValue -Key 'OscdimgPath' -Default $null)

    $resolvedOscdimg = $OscdimgPath
    if ([string]::IsNullOrWhiteSpace([string]$resolvedOscdimg)) {
        $resolvedOscdimg = $adkStatus.OscdimgPath
    }
    if ([string]::IsNullOrWhiteSpace([string]$resolvedOscdimg) -or -not (Test-Path -LiteralPath $resolvedOscdimg -PathType Leaf)) {
        throw "oscdimg.exe wurde nicht gefunden. Bitte ADK in Settings konfigurieren."
    }

    $resolvedSourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $resolvedWorkingRoot = Get-IsoBuildWorkingRoot -WorkingRoot $WorkingRoot
    if (-not (Test-Path -LiteralPath $resolvedWorkingRoot -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $resolvedWorkingRoot -Force
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $stageRoot = Join-Path $resolvedWorkingRoot ('Stage_{0}' -f $stamp)
    $resolvedLabel = Get-IsoBuildVolumeLabel -VolumeLabel $VolumeLabel -SourceRoot $resolvedSourceRoot

    Write-IsoBuildLog -Level INFO -Message ("ISO Build: SourceRoot={0}; Output={1}; Stage={2}" -f $resolvedSourceRoot, $resolvedOutputPath, $stageRoot)

    Copy-IsoBuildSourceTree -SourceRoot $resolvedSourceRoot -StageRoot $stageRoot
    $imageUpdate = Update-IsoBuildImagesInStage -StageRoot $stageRoot -InstallImagePath $InstallImagePath -BootImagePath $BootImagePath
    $oscdimgResult = Invoke-OscdimgBuild -OscdimgPath $resolvedOscdimg -StageRoot $stageRoot -OutputPath $resolvedOutputPath -VolumeLabel $resolvedLabel

    Write-IsoBuildLog -Level INFO -Message ("ISO Build abgeschlossen: {0}" -f $resolvedOutputPath)

    return [pscustomobject]@{
        OutputPath        = $resolvedOutputPath
        StageRoot         = $stageRoot
        SourceRoot        = $resolvedSourceRoot
        VolumeLabel       = $resolvedLabel
        OscdimgPath       = $resolvedOscdimg
        InstallImagePath  = $imageUpdate.InstallImagePath
        BootImagePath     = $imageUpdate.BootImagePath
        OscdimgCommand    = $oscdimgResult.Command
    }
}

Export-ModuleMember -Function Build-WindowsIso
