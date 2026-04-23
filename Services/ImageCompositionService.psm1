Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot '..\Core\Bootstrap.psm1') -Force
Import-Module (Resolve-ProjectPath 'Services\DismService.psm1' -MustExist) -Force

function Build-CombinedInstallImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ImageSpecs,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $items = @($ImageSpecs) | Where-Object { $_ -ne $null }
    if ($items.Count -lt 1) {
        throw "Keine Quellimages zum Kombinieren angegeben."
    }

    $outputFull = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDir = [System.IO.Path]::GetDirectoryName($outputFull)
    if ([string]::IsNullOrWhiteSpace($outputDir)) {
        throw "Zielordner für install.esd konnte nicht bestimmt werden: $OutputPath"
    }

    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $outputDir -Force
    }

    if (Test-Path -LiteralPath $outputFull -PathType Leaf) {
        Remove-Item -LiteralPath $outputFull -Force
    }

    $exported = New-Object System.Collections.Generic.List[object]

    foreach ($spec in $items) {
        $path = [string]$spec.Path
        $index = [int]$spec.Index

        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Quellimage nicht gefunden: $path"
        }

        $args = @(
            '/Export-Image',
            ('/SourceImageFile:"{0}"' -f $path),
            ('/SourceIndex:{0}' -f $index),
            ('/DestinationImageFile:"{0}"' -f $outputFull),
            '/Compress:recovery',
            '/CheckIntegrity'
        )

        $result = Invoke-Dism -Arguments $args -EnsureEnglish -TimeoutSec 7200
        if ($result.ExitCode -ne 0) {
            $msg = $result.StdErr
            if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $result.StdOut }
            throw ("DISM Export-Image fehlgeschlagen für {0} Index {1} (ExitCode={2}). {3}" -f $path, $index, $result.ExitCode, $msg)
        }

        $exported.Add([pscustomobject]@{
            Path        = $path
            Index       = $index
            Name        = [string]$spec.Name
            Description = [string]$spec.Description
        }) | Out-Null
    }

    return [pscustomobject]@{
        OutputPath = $outputFull
        ImageCount = $exported.Count
        Items      = @($exported.ToArray())
    }
}

Export-ModuleMember -Function Build-CombinedInstallImage
