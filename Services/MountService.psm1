Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-UnmountSharingViolation {
    [CmdletBinding()]
    param($Result)

    if ($null -eq $Result) { return $false }

    $code = $null
    try { $code = [int]$Result.ExitCode } catch { $code = $null }
    if ($code -eq 32) { return $true }

    $text = ''
    try {
        $text = (([string]$Result.StdErr) + "`n" + ([string]$Result.StdOut))
    } catch {
        $text = ''
    }

    return (
        $text -match '0x80070020' -or
        $text -match '0xc144012f' -or
        $text -match 'sharing violation' -or
        $text -match 'Failed to unload offline registry' -or
        $text -match 'client may still need it open' -or
        $text -match 'E_ACCESSDENIED' -or
        $text -match 'Access is denied' -or
        $text -match 'Error:\s*32'
    )
}

function Test-UnmountPartialState {
    [CmdletBinding()]
    param($Result)

    if ($null -eq $Result) { return $false }

    $code = $null
    try { $code = [int]$Result.ExitCode } catch { $code = $null }
    if ($code -eq -1052638947) { return $true }

    $text = ''
    try {
        $text = (([string]$Result.StdErr) + "`n" + ([string]$Result.StdOut))
    } catch {
        $text = ''
    }

    return ($text -match '0xc142011d' -or $text -match 'partial unmount' -or $text -match 'cannot be committed back into the WIM')
}

function Get-WimMountRegistryState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MountDir)

    $base = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
    if (-not (Test-Path -LiteralPath $base)) { return $null }

    $wanted = $null
    try { $wanted = [System.IO.Path]::GetFullPath($MountDir).TrimEnd('\') } catch { $wanted = $MountDir.TrimEnd('\') }

    foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
        try {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            $mountProp = $props.PSObject.Properties['Mount Path']
            if ($null -eq $mountProp -or [string]::IsNullOrWhiteSpace([string]$mountProp.Value)) { continue }

            $current = $null
            try { $current = [System.IO.Path]::GetFullPath([string]$mountProp.Value).TrimEnd('\') } catch { $current = ([string]$mountProp.Value).TrimEnd('\') }
            if (-not [string]::Equals($current, $wanted, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            $status = $null
            $wimPath = $null
            $imageIndex = $null
            $statusProp = $props.PSObject.Properties['Status']
            $wimProp = $props.PSObject.Properties['WIM Path']
            $indexProp = $props.PSObject.Properties['Image Index']
            if ($statusProp) { try { $status = [int]$statusProp.Value } catch { $status = $null } }
            if ($wimProp) { $wimPath = [string]$wimProp.Value }
            if ($indexProp) { try { $imageIndex = [int]$indexProp.Value } catch { $imageIndex = $null } }

            return [pscustomobject]@{
                Key        = [string]$key.PSChildName
                MountDir   = [string]$mountProp.Value
                ImageFile  = $wimPath
                ImageIndex = $imageIndex
                Status     = $status
            }
        } catch {}
    }

    return $null
}

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
        try { Set-ConfigValue -Key "MountRoot" -Value $p -Persist } catch {}
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
        [string]$Label = "DISM",
        [int]$TimeoutSec = 0,
        [switch]$PassThruNonZero
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
        if ($cmd -and $TimeoutSec -gt 0 -and ($keys -contains "TimeoutSec")) { $splat["TimeoutSec"] = $TimeoutSec }

        if ($cmd) {
            $result = Invoke-Dism @splat
            if ($null -eq $result) {
                throw "{0} failed. Kein Ergebnis von Invoke-Dism erhalten." -f $Label
            }

            if ($result.PSObject.Properties.Name -contains 'ExitCode' -and [int]$result.ExitCode -ne 0) {
                if ($PassThruNonZero) {
                    return $result
                }

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
        if ($PassThruNonZero) {
            return [pscustomobject]@{ ExitCode = $code; Output = $out; StdOut = $out; StdErr = '' }
        }
        throw "{0} failed (ExitCode={1}).`n`n{2}" -f $Label, $code, $out
    }

    return [pscustomobject]@{ ExitCode = 0; Output = $out }
}

function Repair-WimMountRegistry {
    [CmdletBinding()]
    param([int]$TimeoutSec = 900)

    if ($TimeoutSec -lt 60) { $TimeoutSec = 60 }

    $label = "DISM Cleanup-Wim"
    $result = Invoke-DismCompat -Arguments @("/English", "/Cleanup-Wim") -Label $label -TimeoutSec $TimeoutSec -PassThruNonZero

    if ($result -and $result.PSObject.Properties.Name -contains 'ExitCode' -and [int]$result.ExitCode -ne 0) {
        $detail = ''
        if ($result.PSObject.Properties.Name -contains 'StdErr' -and -not [string]::IsNullOrWhiteSpace([string]$result.StdErr)) {
            $detail = [string]$result.StdErr
        } elseif ($result.PSObject.Properties.Name -contains 'StdOut' -and -not [string]::IsNullOrWhiteSpace([string]$result.StdOut)) {
            $detail = [string]$result.StdOut
        } elseif ($result.PSObject.Properties.Name -contains 'Output' -and -not [string]::IsNullOrWhiteSpace([string]$result.Output)) {
            $detail = [string]$result.Output
        }

        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            throw "{0} failed (ExitCode={1}).`n`n{2}" -f $label, [int]$result.ExitCode, $detail.Trim()
        }

        throw "{0} failed (ExitCode={1})." -f $label, [int]$result.ExitCode
    }

    return $true
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

    if (-not $ReadOnly) {
        try {
            $imageItem = Get-Item -LiteralPath $ImagePath -ErrorAction Stop
            if ($imageItem.IsReadOnly) {
                throw "Mount mit Commit ist nicht möglich, weil die Image-Datei schreibgeschützt ist: $ImagePath. Bitte ReadOnly mounten oder das Schreibschutz-Attribut der WIM/ESD-Kopie entfernen."
            }
        } catch {
            throw
        }
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
    $timeoutSec = 0
    $retryCount = 1
    $retryDelaySec = 0
    if ($Commit) {
        $mountState = Get-WimMountRegistryState -MountDir $MountDir
        if ($mountState -and $mountState.Status -eq 3) {
            $imageText = if ([string]::IsNullOrWhiteSpace([string]$mountState.ImageFile)) { 'unbekannte Quell-WIM' } else { [string]$mountState.ImageFile }
            throw "Commit ist für diesen Mount nicht mehr möglich, weil DISM ihn bereits als teilweise ausgehängt markiert hat (Status=3). Quelle: $imageText. Wenn der vorherige Commit erfolgreich war, bitte jetzt ohne Commit aushängen, damit DISM den Mount bereinigt."
        }

        try { $timeoutSec = [int](Get-ConfigValue -Key "DismUnmountCommitTimeoutSec" -Default 7200) } catch { $timeoutSec = 7200 }
        if ($timeoutSec -lt 900) { $timeoutSec = 900 }
        try { $retryCount = [int](Get-ConfigValue -Key "DismUnmountCommitRetryCount" -Default 3) } catch { $retryCount = 3 }
        try { $retryDelaySec = [int](Get-ConfigValue -Key "DismUnmountCommitRetryDelaySec" -Default 12) } catch { $retryDelaySec = 12 }
        if ($retryCount -lt 1) { $retryCount = 1 }
        if ($retryDelaySec -lt 1) { $retryDelaySec = 1 }
    }

    $lastResult = $null
    for ($attempt = 1; $attempt -le $retryCount; $attempt++) {
        $lastResult = Invoke-DismCompat -Arguments $args -Label $label -TimeoutSec $timeoutSec -PassThruNonZero
        if (Test-UnmountPartialState -Result $lastResult) {
            break
        }

        if (-not (Test-UnmountSharingViolation -Result $lastResult)) {
            break
        }

        if ($attempt -lt $retryCount) {
            try {
                Write-Log -Level WARN -Message ("Unmount-Commit retry {0}/{1} nach Sharing Violation fuer {2}. Warte {3}s." -f $attempt, $retryCount, $MountDir, $retryDelaySec)
            } catch {}
            Start-Sleep -Seconds $retryDelaySec
        }
    }

    if ($lastResult -and $lastResult.PSObject.Properties.Name -contains 'ExitCode' -and [int]$lastResult.ExitCode -ne 0 -and [int]$lastResult.ExitCode -eq 32) {
        $detail = ''
        if ($lastResult.PSObject.Properties.Name -contains 'StdErr' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdErr)) {
            $detail = [string]$lastResult.StdErr
        } elseif ($lastResult.PSObject.Properties.Name -contains 'StdOut' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdOut)) {
            $detail = [string]$lastResult.StdOut
        }

        $hint = "Die Quell-WIM ist noch gesperrt. Wahrscheinlich haelt ein laufender WIM/DISM-Zugriff oder ein anderer Mount die Datei noch offen."
        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            throw "{0} failed (ExitCode=32).`n`n{1}`n`n{2}" -f $label, $detail.Trim(), $hint
        }
        throw "{0} failed (ExitCode=32).`n`n{1}" -f $label, $hint
    }

    if ($lastResult -and $lastResult.PSObject.Properties.Name -contains 'ExitCode' -and [int]$lastResult.ExitCode -ne 0 -and (Test-UnmountPartialState -Result $lastResult)) {
        $detail = ''
        if ($lastResult.PSObject.Properties.Name -contains 'StdErr' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdErr)) {
            $detail = [string]$lastResult.StdErr
        } elseif ($lastResult.PSObject.Properties.Name -contains 'StdOut' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdOut)) {
            $detail = [string]$lastResult.StdOut
        } elseif ($lastResult.PSObject.Properties.Name -contains 'Output' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.Output)) {
            $detail = [string]$lastResult.Output
        }

        $hint = "DISM meldet einen teilweisen Unmount. Commit kann nicht erneut ausgefuehrt werden. Wenn der vorherige Commit erfolgreich war, den Mount jetzt ohne Commit aushaengen, um ihn zu bereinigen."
        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            throw "{0} failed (0xc142011d).`n`n{1}`n`n{2}" -f $label, $detail.Trim(), $hint
        }
        throw "{0} failed (0xc142011d).`n`n{1}" -f $label, $hint
    }

    if ($lastResult -and $lastResult.PSObject.Properties.Name -contains 'ExitCode' -and [int]$lastResult.ExitCode -ne 0 -and (Test-UnmountSharingViolation -Result $lastResult)) {
        $detail = ''
        if ($lastResult.PSObject.Properties.Name -contains 'StdErr' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdErr)) {
            $detail = [string]$lastResult.StdErr
        } elseif ($lastResult.PSObject.Properties.Name -contains 'StdOut' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdOut)) {
            $detail = [string]$lastResult.StdOut
        } elseif ($lastResult.PSObject.Properties.Name -contains 'Output' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.Output)) {
            $detail = [string]$lastResult.Output
        }

        $hint = "Der Mount ist noch in Benutzung. Bitte Mount-Ordner nicht im Explorer öffnen, kurz warten und erneut versuchen. Wenn DISM bereits teilweise ausgehängt hat und der Commit vorher fertig war, anschließend ohne Commit bereinigen."
        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            throw "{0} failed (ExitCode={1}).`n`n{2}`n`n{3}" -f $label, [int]$lastResult.ExitCode, $detail.Trim(), $hint
        }
        throw "{0} failed (ExitCode={1}).`n`n{2}" -f $label, [int]$lastResult.ExitCode, $hint
    }

    if ($lastResult -and $lastResult.PSObject.Properties.Name -contains 'ExitCode' -and [int]$lastResult.ExitCode -ne 0) {
        $detail = ''
        if ($lastResult.PSObject.Properties.Name -contains 'StdErr' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdErr)) {
            $detail = [string]$lastResult.StdErr
        } elseif ($lastResult.PSObject.Properties.Name -contains 'StdOut' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.StdOut)) {
            $detail = [string]$lastResult.StdOut
        } elseif ($lastResult.PSObject.Properties.Name -contains 'Output' -and -not [string]::IsNullOrWhiteSpace([string]$lastResult.Output)) {
            $detail = [string]$lastResult.Output
        }

        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            throw "{0} failed (ExitCode={1}).`n`n{2}" -f $label, [int]$lastResult.ExitCode, $detail.Trim()
        }
        throw "{0} failed (ExitCode={1})." -f $label, [int]$lastResult.ExitCode
    }

    return $true
}

Export-ModuleMember -Function Get-MountRoot, Set-MountRoot, Mount-WimImage, Unmount-WimImage, Repair-WimMountRegistry
