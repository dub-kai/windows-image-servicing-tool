Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-MountRoot {
    # Priority:
    # 1) AppState MountRoot (user-chosen runtime)
    # 2) Config MountRoot (persisted)
    # 3) default Work\Mounts

    $root = $null

    if (Get-Command Get-AppStateValue -ErrorAction SilentlyContinue) {
        try { $root = Get-AppStateValue -Key "MountRoot" -Default $null } catch {}
    }

    if (-not $root -and (Get-Command Get-ConfigValue -ErrorAction SilentlyContinue)) {
        try { $root = Get-ConfigValue -Key "MountRoot" -Default $null } catch {}
    }

    if (-not $root) {
        $root = Resolve-ProjectPath "Work\Mounts"
    }

    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -ItemType Directory -Path $root -Force
    }

    return $root
}

function Set-MountRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Persist
    )

    $p = $Path.Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { throw "MountRoot ist leer." }

    # require local path
    if ($p.StartsWith('\\')) { throw "MountRoot darf kein UNC-Pfad sein (DISM Mount ist auf Netzpfaden unzuverlässig)." }

    if (-not (Test-Path -LiteralPath $p)) {
        $null = New-Item -ItemType Directory -Path $p -Force
    }

    if (Get-Command Set-AppStateValue -ErrorAction SilentlyContinue) {
        try { Set-AppStateValue -Key "MountRoot" -Value $p } catch {}
    }

    if ($Persist -and (Get-Command Set-ConfigValue -ErrorAction SilentlyContinue)) {
        try { Set-ConfigValue -Key "MountRoot" -Value $p } catch {}
    }

    return $p
}

function Test-DirectoryEmpty {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try { return (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop).Count -eq 0) } catch { return $false }
}

function New-MountDir {
    param(
        [Parameter(Mandatory)][ValidateSet("IsoInstall","IsoBoot","Standalone")] [string]$Mode,
        [Parameter(Mandatory)][int]$Index
    )

    $root = Get-MountRoot

    # stable structure: <MountRoot>\<Mode>\Index_<n>
    $modeDir = Join-Path $root $Mode
    if (-not (Test-Path -LiteralPath $modeDir)) {
        $null = New-Item -ItemType Directory -Path $modeDir -Force
    }

    $base = Join-Path $modeDir ("Index_{0}" -f $Index)
    if (-not (Test-Path -LiteralPath $base)) { return $base }
    if (Test-DirectoryEmpty -Path $base) { return $base }

    for ($i=2; $i -le 99; $i++) {
        $cand = "{0}_{1}" -f $base, $i
        if (-not (Test-Path -LiteralPath $cand)) { return $cand }
        if (Test-DirectoryEmpty -Path $cand) { return $cand }
    }

    throw "Kein freies Mount-Verzeichnis gefunden unter: $modeDir"
}

function Invoke-DismCompat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$Label = "DISM"
    )

    # Prefer DismService Invoke-Dism if available, but adapt to its parameter names.
    $cmd = Get-Command Invoke-Dism -ErrorAction SilentlyContinue
    if ($cmd) {
        $keys = @($cmd.Parameters.Keys)

        $splat = @{}

        # argument parameter detection
        if ($keys -contains "Args") { $splat["Args"] = $Arguments }
        elseif ($keys -contains "Arguments") { $splat["Arguments"] = $Arguments }
        elseif ($keys -contains "Argv") { $splat["Argv"] = $Arguments }
        elseif ($keys -contains "ArgumentList") { $splat["ArgumentList"] = $Arguments }
        elseif ($keys -contains "ArgList") { $splat["ArgList"] = $Arguments }
        else {
            # If no arg param found, fall back to native dism
            $cmd = $null
        }

        # optional label parameter
        if ($cmd -and ($keys -contains "Label")) { $splat["Label"] = $Label }

        if ($cmd) {
            $result = Invoke-Dism @splat
            if ($null -eq $result) {
                throw "{0} failed. Kein Ergebnis von Invoke-Dism erhalten." -f $Label
            }

            if ($result.PSObject.Properties.Name -contains 'ExitCode' -and [int]$result.ExitCode -ne 0) {
                $detail = ''
                if ($result.PSObject.Properties.Name -contains 'StdErr' -and -not [string]::IsNullOrWhiteSpace([string]$result.StdErr)) {
                    $detail = [string]$result.StdErr
                } elseif ($result.PSObject.Properties.Name -contains 'StdOut' -and -not [string]::IsNullOrWhiteSpace([string]$result.StdOut)) {
                    $detail = [string]$result.StdOut
                } elseif ($result.PSObject.Properties.Name -contains 'Output' -and -not [string]::IsNullOrWhiteSpace([string]$result.Output)) {
                    $detail = [string]$result.Output
                }

                if (-not [string]::IsNullOrWhiteSpace($detail)) {
                    throw "{0} failed (ExitCode={1}).`n`n{2}" -f $Label, [int]$result.ExitCode, $detail.Trim()
                }

                throw "{0} failed (ExitCode={1})." -f $Label, [int]$result.ExitCode
            }

            return $result
        }
    }

    # Fallback: call dism.exe directly
    $dismExe = Join-Path $env:WINDIR "System32\dism.exe"
    if (-not (Test-Path -LiteralPath $dismExe)) { $dismExe = "dism.exe" }

    $out = & $dismExe @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        throw "{0} failed (ExitCode={1}).`n`n{2}" -f $Label, $code, $out
    }

    return [pscustomobject]@{ ExitCode = 0; Output = $out }
}

function Mount-WimImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][ValidateSet("IsoInstall","IsoBoot","Standalone")] [string]$Mode,
        [switch]$ReadOnly
    )

    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "ImageFile nicht gefunden: $ImagePath"
    }

    $mountDir = New-MountDir -Mode $Mode -Index $Index

    if (-not (Test-Path -LiteralPath $mountDir)) {
        $null = New-Item -ItemType Directory -Path $mountDir -Force
    } elseif (-not (Test-DirectoryEmpty -Path $mountDir)) {
        throw "MountDir ist nicht leer: $mountDir"
    }

    $args = @(
        "/English",
        "/Mount-Image",
        "/ImageFile:$ImagePath",
        "/Index:$Index",
        "/MountDir:$mountDir"
    )
    if ($ReadOnly) { $args += "/ReadOnly" }

    $null = Invoke-DismCompat -Arguments $args -Label "DISM Mount-Image"

    return [pscustomobject]@{
        ImagePath = $ImagePath
        Index     = $Index
        Mode      = $Mode
        MountDir  = $mountDir
        ReadOnly  = [bool]$ReadOnly
    }
}

function Unmount-WimImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [switch]$Commit,
        [switch]$Discard
    )

    if ($Commit -and $Discard) { throw "Commit und Discard gleichzeitig ist nicht erlaubt." }
    if (-not $Commit -and -not $Discard) { $Discard = $true }

    if (-not (Test-Path -LiteralPath $MountDir)) {
        throw "MountDir nicht gefunden: $MountDir"
    }

    $args = @(
        "/English",
        "/Unmount-Image",
        "/MountDir:$MountDir"
    )
    if ($Commit) { $args += "/Commit" } else { $args += "/Discard" }

    $label = if ($Commit) { "DISM Unmount-Image Commit" } else { "DISM Unmount-Image Discard" }
    $null = Invoke-DismCompat -Arguments $args -Label $label

    return $true
}

Export-ModuleMember -Function Get-MountRoot, Set-MountRoot, Mount-WimImage, Unmount-WimImage
