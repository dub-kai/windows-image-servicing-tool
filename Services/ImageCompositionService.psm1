Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Import-ImageCompositionDependencies {
    [CmdletBinding()]
    param()

    $bootstrapPath = Join-Path $PSScriptRoot '..\Core\Bootstrap.psm1'
    Import-Module $bootstrapPath -Global -Force -DisableNameChecking | Out-Null

    $dismPath = Resolve-ProjectPath 'Services\DismService.psm1' -MustExist
    Import-Module $dismPath -Global -Force -DisableNameChecking | Out-Null
}

function Set-ImageCompositionProgress {
    [CmdletBinding()]
    param(
        [Parameter()][string]$ProgressPath,
        [Parameter(Mandatory)][string]$Status,
        [Parameter()][int]$Current = 0,
        [Parameter()][int]$Total = 0,
        [Parameter()][string]$Message = $null,
        [Parameter()][string]$OutputPath = $null
    )

    if ([string]::IsNullOrWhiteSpace($ProgressPath)) { return }

    try {
        $data = [ordered]@{
            Time       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Status     = $Status
            Current    = $Current
            Total      = $Total
            Message    = $Message
            OutputPath = $OutputPath
            SizeBytes  = 0
        }

        if (-not [string]::IsNullOrWhiteSpace($OutputPath) -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
            $data.SizeBytes = (Get-Item -LiteralPath $OutputPath).Length
        }

        $dir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ProgressPath))
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }

        $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ProgressPath -Encoding UTF8
    } catch {}
}

function Get-ImageSpecValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Spec,

        [Parameter(Mandatory)]
        [string[]]$Names
    )

    if ($Spec -is [System.Collections.IDictionary]) {
        foreach ($name in $Names) {
            if ($Spec.Contains($name)) { return $Spec[$name] }
        }
        return $null
    }

    foreach ($name in $Names) {
        $prop = $Spec.PSObject.Properties[$name]
        if ($null -ne $prop) { return $prop.Value }
    }

    return $null
}

function Build-CombinedInstallImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ImageSpecs,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string]$ProgressPath
    )

    $items = @(@($ImageSpecs) | Where-Object { $_ -ne $null })
    if ($items.Count -lt 1) {
        throw "Keine Quellimages zum Kombinieren angegeben."
    }

    Import-ImageCompositionDependencies

    $outputFull = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDir = [System.IO.Path]::GetDirectoryName($outputFull)
    if ([string]::IsNullOrWhiteSpace($outputDir)) {
        throw "Zielordner für install.esd konnte nicht bestimmt werden: $OutputPath"
    }

    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $outputDir -Force
    }

    $scratchDir = Resolve-ProjectPath 'Work\Temp\DismScratch'
    if (-not (Test-Path -LiteralPath $scratchDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $scratchDir -Force
    }

    if (Test-Path -LiteralPath $outputFull -PathType Leaf) {
        Remove-Item -LiteralPath $outputFull -Force
    }

    $exported = New-Object System.Collections.Generic.List[object]
    $position = 0
    Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Starting' -Current 0 -Total $items.Count -Message 'install.esd wird vorbereitet...' -OutputPath $outputFull

    try {
        foreach ($spec in $items) {
            $position++
            $path = [string](Get-ImageSpecValue -Spec $spec -Names @('Path', 'SourceImage', 'SourceImagePath'))
            $indexRaw = Get-ImageSpecValue -Spec $spec -Names @('Index', 'SourceIndex', 'ImageIndex')

            if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Quellimage nicht gefunden: $path"
            }

            $parsedIndex = 0
            if ($null -eq $indexRaw -or -not [int]::TryParse([string]$indexRaw, [ref]$parsedIndex)) {
                throw "Image-Index fehlt oder ist ungültig für: $path"
            }
            $index = $parsedIndex

            $displayName = [string](Get-ImageSpecValue -Spec $spec -Names @('Name', 'ImageName'))
            if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = [System.IO.Path]::GetFileName($path) }
            $msg = ("Exportiere {0}/{1}: {2} (Index {3})" -f $position, $items.Count, $displayName, $index)
            Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Exporting' -Current $position -Total $items.Count -Message $msg -OutputPath $outputFull

            try {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log -Level INFO -Message ("ImageComposition: Export {0}/{1} -> {2} (Index {3})" -f $position, $items.Count, $path, $index)
                }
            } catch {}

            $args = @(
                '/Export-Image',
                ('/SourceImageFile:"{0}"' -f $path),
                ('/SourceIndex:{0}' -f $index),
                ('/DestinationImageFile:"{0}"' -f $outputFull),
                '/Compress:recovery',
                '/CheckIntegrity',
                ('/ScratchDir:"{0}"' -f $scratchDir)
            )

            $result = Invoke-Dism -Arguments $args -EnsureEnglish -TimeoutSec 7200
            if ($result.ExitCode -ne 0) {
                $err = $result.StdErr
                if ([string]::IsNullOrWhiteSpace($err)) { $err = $result.StdOut }
                throw ("DISM Export-Image fehlgeschlagen für {0} Index {1} (ExitCode={2}). {3}" -f $path, $index, $result.ExitCode, $err)
            }

            $exported.Add([pscustomobject]@{
                Path        = $path
                Index       = $index
                Name        = [string](Get-ImageSpecValue -Spec $spec -Names @('Name', 'ImageName'))
                Description = [string](Get-ImageSpecValue -Spec $spec -Names @('Description', 'ImageDescription'))
            }) | Out-Null

            Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Exported' -Current $position -Total $items.Count -Message ("Fertig: {0}" -f $displayName) -OutputPath $outputFull
        }
    } catch {
        Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Failed' -Current $position -Total $items.Count -Message $_.Exception.Message -OutputPath $outputFull
        if (Test-Path -LiteralPath $outputFull -PathType Leaf) {
            try { Remove-Item -LiteralPath $outputFull -Force } catch {}
        }
        throw
    }

    if (-not (Test-Path -LiteralPath $outputFull -PathType Leaf)) {
        throw "install.esd wurde nicht erstellt: $outputFull"
    }

    $fileInfo = Get-Item -LiteralPath $outputFull -ErrorAction Stop
    if ($fileInfo.Length -le 0) {
        throw "install.esd wurde angelegt, ist aber leer: $outputFull"
    }

    Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Completed' -Current $items.Count -Total $items.Count -Message 'install.esd wurde erstellt.' -OutputPath $outputFull

    return [pscustomobject]@{
        OutputPath = $outputFull
        ImageCount = $exported.Count
        SizeBytes  = $fileInfo.Length
        Items      = @($exported.ToArray())
    }
}

Export-ModuleMember -Function Build-CombinedInstallImage
