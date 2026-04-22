Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Merke beim Laden des Moduls, wo dieses Modul liegt.
# In deinem Projekt: <ProjectRoot>\Core\Bootstrap.psm1
$script:ModuleDir   = $PSScriptRoot
$script:ProjectRoot = $null

function Get-ModuleDir {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:ModuleDir)) {
        throw "ModuleDir ist nicht gesetzt. Modul wurde evtl. ungewöhnlich geladen."
    }
    return $script:ModuleDir
}

function Get-DefaultProjectRootCandidate {
    [CmdletBinding()]
    param()

    # Core\ liegt direkt unter ProjectRoot -> Parent ist ProjectRoot
    $coreDir = Get-ModuleDir
    $root = Split-Path -Parent $coreDir
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Konnte Default ProjectRoot nicht bestimmen (Split-Path leer)."
    }
    return $root
}

function Set-ProjectRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-DefaultProjectRootCandidate
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ProjectRoot existiert nicht: $Path"
    }

    $script:ProjectRoot = (Resolve-Path -LiteralPath $Path).Path
    return $script:ProjectRoot
}

function Get-ProjectRoot {
    [CmdletBinding()]
    param()

    if (-not $script:ProjectRoot) {
        $null = Set-ProjectRoot
    }
    return $script:ProjectRoot
}

function Resolve-ProjectPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [switch]$MustExist
    )

    $root = Get-ProjectRoot

    # RelativePath normalisieren (keine führenden Slashes)
    $rel = $RelativePath.TrimStart('\','/')

    $full = Join-Path $root $rel

    if ($MustExist) {
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Pfad existiert nicht: $full"
        }
        return (Resolve-Path -LiteralPath $full).Path
    }

    return $full
}

Export-ModuleMember -Function `
    Get-ModuleDir, `
    Get-DefaultProjectRootCandidate, `
    Set-ProjectRoot, `
    Get-ProjectRoot, `
    Resolve-ProjectPath