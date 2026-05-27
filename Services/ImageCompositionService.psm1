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
        [Parameter()][string]$OutputPath = $null,
        [Parameter()][string]$Hint = $null,
        [Parameter()][int]$ElapsedSec = 0,
        [Parameter()][string]$Heartbeat = $null
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
            Hint       = $Hint
            ElapsedSec = $ElapsedSec
            Heartbeat  = $Heartbeat
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

function Get-ImageCompositionTargetLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputPath)

    $ext = [System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant()
    if ($ext -eq '.wim') { return 'install.wim' }
    if ($ext -eq '.esd') { return 'install.esd' }
    return [System.IO.Path]::GetFileName($OutputPath)
}

function Get-ImageCompositionRunningHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetLabel,
        [Parameter(Mandatory)][string]$Compression
    )

    if ($TargetLabel -eq 'install.esd' -or $Compression -eq 'recovery') {
        return 'ESD-Komprimierung kann lange rechnen. Eine sehr kleine Datei ist dabei am Anfang normal.'
    }

    return 'DISM arbeitet. Bei großen WIMs kann der Export mehrere Minuten dauern.'
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
        [string]$ProgressPath,

        [Parameter()]
        [ValidateSet('max', 'recovery')]
        [string]$Compression = 'recovery'
    )

    $items = @(@($ImageSpecs) | Where-Object { $_ -ne $null })
    if ($items.Count -lt 1) {
        throw "Keine Quellimages zum Kombinieren angegeben."
    }

    Import-ImageCompositionDependencies

    $outputFull = [System.IO.Path]::GetFullPath($OutputPath)
    $targetLabel = Get-ImageCompositionTargetLabel -OutputPath $outputFull
    $outputDir = [System.IO.Path]::GetDirectoryName($outputFull)
    if ([string]::IsNullOrWhiteSpace($outputDir)) {
        throw "Zielordner für $targetLabel konnte nicht bestimmt werden: $OutputPath"
    }

    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $outputDir -Force
    }

    $scratchDir = Resolve-ProjectPath 'Work\Temp\DismScratch'
    if (-not (Test-Path -LiteralPath $scratchDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $scratchDir -Force
    }

    $validatedItems = New-Object System.Collections.Generic.List[object]
    foreach ($spec in $items) {
        $path = [string](Get-ImageSpecValue -Spec $spec -Names @('Path', 'SourceImage', 'SourceImagePath'))
        $indexRaw = Get-ImageSpecValue -Spec $spec -Names @('Index', 'SourceIndex', 'ImageIndex')

        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Quellimage nicht gefunden: $path"
        }

        $parsedIndex = 0
        if ($null -eq $indexRaw -or -not [int]::TryParse([string]$indexRaw, [ref]$parsedIndex)) {
            throw "Image-Index fehlt oder ist ungültig für: $path"
        }

        $displayName = [string](Get-ImageSpecValue -Spec $spec -Names @('Name', 'ImageName'))
        if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = [System.IO.Path]::GetFileName($path) }

        $validatedItems.Add([pscustomobject]@{
            Path        = $path
            Index       = $parsedIndex
            DisplayName = $displayName
            Name        = [string](Get-ImageSpecValue -Spec $spec -Names @('Name', 'ImageName'))
            Description = [string](Get-ImageSpecValue -Spec $spec -Names @('Description', 'ImageDescription'))
        }) | Out-Null
    }

    if (Test-Path -LiteralPath $outputFull -PathType Leaf) {
        Remove-Item -LiteralPath $outputFull -Force
    }

    $exported = New-Object System.Collections.Generic.List[object]
    $position = 0
    $runningHint = Get-ImageCompositionRunningHint -TargetLabel $targetLabel -Compression $Compression
    Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Starting' -Current 0 -Total $items.Count -Message ("{0} wird vorbereitet..." -f $targetLabel) -OutputPath $outputFull -Hint $runningHint

    try {
        foreach ($item in @($validatedItems.ToArray())) {
            $position++
            $path = [string]$item.Path
            $index = [int]$item.Index
            $displayName = [string]$item.DisplayName
            $msg = ("Exportiere {0}/{1}: {2} (Index {3})" -f $position, $items.Count, $displayName, $index)
            Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Exporting' -Current $position -Total $items.Count -Message $msg -OutputPath $outputFull -Hint $runningHint

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
                ('/Compress:{0}' -f $Compression),
                '/CheckIntegrity',
                ('/ScratchDir:"{0}"' -f $scratchDir)
            )

            $heartbeatAction = {
                param($state)

                $heartbeatText = $null
                if (-not [string]::IsNullOrWhiteSpace([string]$state.StdErrTail)) {
                    $heartbeatText = ([string]$state.StdErrTail).Trim()
                } elseif (-not [string]::IsNullOrWhiteSpace([string]$state.StdOutTail)) {
                    $heartbeatText = ([string]$state.StdOutTail).Trim()
                }

                if (-not [string]::IsNullOrWhiteSpace($heartbeatText)) {
                    $heartbeatText = $heartbeatText -replace '\s+', ' '
                    if ($heartbeatText.Length -gt 220) {
                        $heartbeatText = $heartbeatText.Substring($heartbeatText.Length - 220)
                    }
                }

                Set-ImageCompositionProgress `
                    -ProgressPath $ProgressPath `
                    -Status 'Exporting' `
                    -Current $position `
                    -Total $items.Count `
                    -Message $msg `
                    -OutputPath $outputFull `
                    -Hint $runningHint `
                    -ElapsedSec ([int]$state.ElapsedSec) `
                    -Heartbeat $heartbeatText
            }.GetNewClosure()

            $result = Invoke-Dism -Arguments $args -EnsureEnglish -TimeoutSec 7200 -OnHeartbeat $heartbeatAction -HeartbeatIntervalSec 3
            if ($result.ExitCode -ne 0) {
                $err = $result.StdErr
                if ([string]::IsNullOrWhiteSpace($err)) { $err = $result.StdOut }
                throw ("DISM Export-Image fehlgeschlagen für {0} Index {1} (ExitCode={2}). {3}" -f $path, $index, $result.ExitCode, $err)
            }

            $exported.Add([pscustomobject]@{
                Path        = $path
                Index       = $index
                Name        = [string]$item.Name
                Description = [string]$item.Description
            }) | Out-Null

            Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Exported' -Current $position -Total $items.Count -Message ("Fertig: {0}" -f $displayName) -OutputPath $outputFull -Hint $runningHint
        }
    } catch {
        Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Failed' -Current $position -Total $items.Count -Message $_.Exception.Message -OutputPath $outputFull -Hint $runningHint
        if (Test-Path -LiteralPath $outputFull -PathType Leaf) {
            try { Remove-Item -LiteralPath $outputFull -Force } catch {}
        }
        throw
    }

    if (-not (Test-Path -LiteralPath $outputFull -PathType Leaf)) {
        throw "$targetLabel wurde nicht erstellt: $outputFull"
    }

    $fileInfo = Get-Item -LiteralPath $outputFull -ErrorAction Stop
    if ($fileInfo.Length -le 0) {
        throw "$targetLabel wurde angelegt, ist aber leer: $outputFull"
    }

    Set-ImageCompositionProgress -ProgressPath $ProgressPath -Status 'Completed' -Current $items.Count -Total $items.Count -Message ("{0} wurde erstellt." -f $targetLabel) -OutputPath $outputFull -Hint $runningHint

    return [pscustomobject]@{
        OutputPath = $outputFull
        ImageCount = $exported.Count
        SizeBytes  = $fileInfo.Length
        Items      = @($exported.ToArray())
    }
}

Export-ModuleMember -Function Build-CombinedInstallImage
