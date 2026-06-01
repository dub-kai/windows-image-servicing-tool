Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StandaloneImageExtensions {
    return @('.wim', '.esd', '.swm')
}

function Convert-StandalonePathValueToList {
    param($Value)

    $items = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) { return @() }

    if ($Value -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $items.Add([string]$Value) | Out-Null
        }
        return @($items.ToArray())
    }

    try {
        foreach ($entry in @($Value)) {
            $text = [string]$entry
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $items.Add($text) | Out-Null
            }
        }
    } catch {}

    return @($items.ToArray())
}

function Resolve-StandaloneImagePaths {
    $raw = $null
    $candidates = New-Object System.Collections.Generic.List[string]

    try { $raw = Get-ImagesAppStateValueSafe -Key 'StandaloneImagePaths' -Default $null } catch { $raw = $null }
    foreach ($p in @(Convert-StandalonePathValueToList -Value $raw)) {
        $candidates.Add($p) | Out-Null
    }

    foreach ($key in @('StandaloneImagePath', 'SelectedImagePath', 'ImagePath')) {
        try { $raw = Get-ImagesAppStateValueSafe -Key $key -Default $null } catch { $raw = $null }
        foreach ($p in @(Convert-StandalonePathValueToList -Value $raw)) {
            $candidates.Add($p) | Out-Null
        }
    }

    $allowed = Get-StandaloneImageExtensions
    $seen = @{}
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @($candidates.ToArray())) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        $resolved = [string]$candidate
        try { $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path } catch {}

        $ext = [System.IO.Path]::GetExtension($resolved)
        if ($allowed -notcontains $ext.ToLowerInvariant()) { continue }
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { continue }

        $key = $resolved.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $result.Add($resolved) | Out-Null
        }
    }

    return @($result.ToArray())
}

function Format-StandaloneImagesSummary {
    param([string[]]$Paths)

    $items = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -eq 0) { return '-' }
    if ($items.Count -eq 1) { return [string]$items[0] }

    $dirs = @()
    try {
        $dirs = @($items | ForEach-Object { Split-Path -LiteralPath ([string]$_) -Parent } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    } catch { $dirs = @() }

    if ($dirs.Count -eq 1) {
        return ("{0} Dateien ausgewählt aus {1}" -f $items.Count, [string]$dirs[0])
    }

    return ("{0} Dateien ausgewählt" -f $items.Count)
}

function Clear-ImagesWimCache {
    try {
        $cacheRef = Ensure-WimCache
        if ($cacheRef) { $cacheRef.Clear() }
    } catch {}
}

function Set-StandaloneImageSelection {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [string]$StatusPrefix = 'Images gewählt'
    )

    $allowed = Get-StandaloneImageExtensions
    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[string]

    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        $resolved = [string]$path
        try { $resolved = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path } catch {}

        $ext = [System.IO.Path]::GetExtension($resolved)
        if ($allowed -notcontains $ext.ToLowerInvariant()) { continue }
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { continue }

        $key = $resolved.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $unique.Add($resolved) | Out-Null
        }
    }

    $resolvedPaths = @($unique.ToArray())
    if ($resolvedPaths.Count -eq 0) {
        throw 'Keine WIM/ESD/SWM-Dateien gefunden.'
    }

    $first = [string]$resolvedPaths[0]

    Set-ImagesAppStateValueSafe -Key 'StandaloneImagePaths' -Value $resolvedPaths
    Set-ImagesAppStateValueSafe -Key 'StandaloneImagePath'  -Value $first
    Set-ImagesAppStateValueSafe -Key 'SelectedImagePath'    -Value $first

    try {
        $parent = Split-Path -LiteralPath $first -Parent
        if ($parent) {
            Set-ImagesAppStateValueSafe -Key 'StandaloneLastDir' -Value $parent
        }
    } catch {}

    try { Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value 'Standalone' } catch {}

    Clear-ImagesWimCache

    if ($script:ctx) {
        try { $script:ctx.StandalonePaths = $resolvedPaths } catch {}
        try { $script:ctx.StandalonePath = $first } catch {}

        try {
            if ($script:ctx.TxtStandalone) {
                $script:ctx.TxtStandalone.Text = Format-StandaloneImagesSummary -Paths $resolvedPaths
            }
        } catch {}

        try { Set-ImagesComboByMode -Mode 'Standalone' } catch {}
        try { Refresh-ImagesUI } catch {}
        try { Show-ImagesIndexes -ForceReload } catch {}
    }

    try {
        if ($script:ctx -and $script:ctx.SetStatus) {
            & $script:ctx.SetStatus (Get-UiString -Key 'ImagesStandaloneStatusFormat' -Args @($StatusPrefix, $resolvedPaths.Count))
        }
    } catch {}
}

function Pick-StandaloneImageFolder {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = Get-UiString -Key 'ImagesFolderDialogDescription'
    $dlg.ShowNewFolderButton = $false

    $lastDir = Get-ImagesAppStateValueSafe -Key 'StandaloneLastDir' -Default $null
    if ($lastDir -and (Test-Path -LiteralPath $lastDir -PathType Container)) {
        try { $dlg.SelectedPath = $lastDir } catch {}
    }

    $result = $dlg.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $folder = [string]$dlg.SelectedPath
    if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        return
    }

    $paths = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { (Get-StandaloneImageExtensions) -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName |
        Select-Object -ExpandProperty FullName

    Set-ImagesAppStateValueSafe -Key 'StandaloneLastDir' -Value $folder
    Set-StandaloneImageSelection -Paths @($paths) -StatusPrefix 'Ordner geladen'
}
