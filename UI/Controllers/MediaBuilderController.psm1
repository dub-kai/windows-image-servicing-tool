Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath 'UI\UiHelpers.psm1' -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath 'UI\UiAsync.psm1' -MustExist) -Force -DisableNameChecking -Global

$script:ctx = $null
$script:composeItems = New-Object System.Collections.Generic.List[object]
$script:mediaBusy = $false
$script:mediaProgressTimer = $null
$script:mediaBusyStartedAt = $null
$script:mediaProgressPath = $null
$script:mediaOutputPath = $null
$script:mediaBuildProcess = $null
$script:mediaBuildCleanupPaths = @()
$script:mediaBuildOutputPath = $null
$script:mediaBuildCancelled = $false

function Get-MediaCtxValue {
    param(
        [Parameter(Mandatory)]$Obj,
        [Parameter(Mandatory)][string]$Key
    )

    try {
        if ($Obj -is [System.Collections.IDictionary]) {
            return $Obj[$Key]
        }

        $prop = $Obj.PSObject.Properties[$Key]
        if ($prop) { return $prop.Value }
    } catch {}

    return $null
}

function Get-MediaAppStateValueSafe {
    param(
        [Parameter(Mandatory)][string]$Key,
        $Default = $null
    )

    try { return Get-AppStateValue -Key $Key -Default $Default } catch { return $Default }
}

function Set-MediaAppStateValueSafe {
    param(
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()]$Value
    )

    try { Set-AppStateValue -Key $Key -Value $Value } catch {}
}

function Remove-MediaAppStateValueSafe {
    param([Parameter(Mandatory)][string]$Key)

    try { Remove-AppStateValue -Key $Key } catch {}
}

function Format-MediaBytes {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Test-MediaIsAdministrator {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-MediaDriveInfo {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetPathRoot($fullPath)
        if ([string]::IsNullOrWhiteSpace($root)) { return $null }
        return New-Object System.IO.DriveInfo($root)
    } catch {
        return $null
    }
}

function Test-MediaInstallBuildPrerequisites {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$Mode
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $isAdmin = Test-MediaIsAdministrator

    if (-not $isAdmin) {
        [void]$errors.Add('Das Programm läuft nicht als Administrator. DISM-Export braucht Adminrechte.')
    }

    $dismExe = Join-Path $env:WINDIR 'System32\dism.exe'
    if (-not (Test-Path -LiteralPath $dismExe -PathType Leaf)) {
        try {
            $dismCmd = Get-Command dism.exe -ErrorAction Stop
            $dismExe = [string]$dismCmd.Source
        } catch {
            [void]$errors.Add('DISM wurde nicht gefunden. Ohne DISM kann kein Install-Image gebaut werden.')
        }
    }

    if ($Items.Count -lt 1) {
        [void]$errors.Add('Es ist keine Quell-WIM/ESD ausgewählt.')
    }

    $destinationFull = $null
    $destinationDir = $null
    try {
        $destinationFull = [System.IO.Path]::GetFullPath($DestinationPath)
        $destinationDir = [System.IO.Path]::GetDirectoryName($destinationFull)
    } catch {
        [void]$errors.Add("Der Zielpfad ist ungültig: $DestinationPath")
    }

    if ([string]::IsNullOrWhiteSpace($destinationDir)) {
        [void]$errors.Add("Der Zielordner konnte nicht bestimmt werden: $DestinationPath")
    } else {
        try {
            if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $destinationDir -Force
            }

            $probe = Join-Path $destinationDir ('.winimageadmin-write-test-{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
            [System.IO.File]::WriteAllText($probe, 'test', [System.Text.UTF8Encoding]::new($true))
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        } catch {
            [void]$errors.Add("Der Zielordner ist nicht beschreibbar: $destinationDir")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($destinationFull) -and (Test-Path -LiteralPath $destinationFull -PathType Leaf)) {
        try {
            $existing = Get-Item -LiteralPath $destinationFull -ErrorAction Stop
            if ($existing.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                [void]$errors.Add("Die Zieldatei ist schreibgeschützt: $destinationFull")
            } elseif ($existing.Length -le 4096) {
                Remove-Item -LiteralPath $destinationFull -Force -ErrorAction Stop
                [void]$warnings.Add('Eine alte, unvollständige Zieldatei wurde entfernt.')
            }
        } catch {
            [void]$errors.Add("Die vorhandene Zieldatei kann nicht ersetzt werden: $destinationFull")
        }
    }

    $totalSourceBytes = [int64]0
    $largestSourceBytes = [int64]0
    $seenSources = @{}

    foreach ($item in @($Items)) {
        $path = [string]$item.Path
        $index = 0
        if ($null -ne $item.Index) {
            [void][int]::TryParse([string]$item.Index, [ref]$index)
        }

        if ([string]::IsNullOrWhiteSpace($path)) {
            [void]$errors.Add('Ein Quell-Eintrag hat keinen Dateipfad.')
            continue
        }

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [void]$errors.Add("Quell-Datei nicht gefunden: $path")
            continue
        }

        $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
        if ($ext -notin @('.wim', '.esd')) {
            [void]$errors.Add("Quell-Datei ist keine WIM/ESD: $path")
        }

        if ($index -lt 1) {
            [void]$errors.Add("Ungültiger Image-Index bei $path")
        }

        try {
            $fullSource = [System.IO.Path]::GetFullPath($path)
            if ($destinationFull -and ([string]::Equals($fullSource, $destinationFull, [System.StringComparison]::OrdinalIgnoreCase))) {
                [void]$errors.Add('Quelle und Ziel dürfen nicht dieselbe Datei sein.')
            }

            if (-not $seenSources.ContainsKey($fullSource)) {
                $sourceInfo = Get-Item -LiteralPath $fullSource -ErrorAction Stop
                $seenSources[$fullSource] = $true
                $totalSourceBytes += [int64]$sourceInfo.Length
                if ([int64]$sourceInfo.Length -gt $largestSourceBytes) { $largestSourceBytes = [int64]$sourceInfo.Length }
            }
        } catch {
            [void]$errors.Add("Quell-Datei konnte nicht gelesen werden: $path")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($destinationFull)) {
        $drive = Get-MediaDriveInfo -Path $destinationFull
        if ($drive -and $drive.IsReady) {
            $recommendedBytes = if ($Mode -eq 'Esd') {
                [int64]([Math]::Max(8GB, [Math]::Max($largestSourceBytes * 0.9, $totalSourceBytes * 0.45)))
            } else {
                [int64]([Math]::Max(12GB, [Math]::Max($largestSourceBytes * 1.2, $totalSourceBytes * 0.75)))
            }

            $minimumBytes = [int64]([Math]::Max(4GB, $recommendedBytes * 0.5))
            if ([int64]$drive.AvailableFreeSpace -lt $minimumBytes) {
                [void]$errors.Add(("Zu wenig freier Speicher auf {0} Frei: {1}, Minimum: {2}." -f $drive.Name, (Format-MediaBytes $drive.AvailableFreeSpace), (Format-MediaBytes $minimumBytes)))
            } elseif ([int64]$drive.AvailableFreeSpace -lt $recommendedBytes) {
                [void]$warnings.Add(("Speicherplatz ist knapp auf {0} Frei: {1}, empfohlen: {2}." -f $drive.Name, (Format-MediaBytes $drive.AvailableFreeSpace), (Format-MediaBytes $recommendedBytes)))
            }
        } elseif ($drive) {
            [void]$errors.Add(("Ziellaufwerk ist nicht bereit: {0}" -f $drive.Name))
        }
    }

    if ($isAdmin -and (Get-Command Get-MountedWimList -ErrorAction SilentlyContinue)) {
        try {
            $mounted = @(Get-MountedWimList)
            if ($mounted.Count -gt 0) {
                $badMounts = @($mounted | Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_.Status) -and
                    ([string]$_.Status -notmatch '^(Ok|OK|Mounted)$')
                })

                if ($badMounts.Count -gt 0) {
                    [void]$errors.Add(("Es gibt problematische gemountete WIMs. Bitte erst im Mount-Bereich bereinigen: {0}" -f (($badMounts | ForEach-Object { $_.MountDir }) -join ', ')))
                } else {
                    [void]$warnings.Add(("Es sind {0} WIM-Mount(s) aktiv. Das ist ok, kann DISM aber verlangsamen." -f $mounted.Count))
                }
            }
        } catch {
            [void]$warnings.Add("Gemountete WIMs konnten nicht geprüft werden: $($_.Exception.Message)")
        }
    }

    return [pscustomobject]@{
        Success  = ($errors.Count -eq 0)
        Errors   = @($errors.ToArray())
        Warnings = @($warnings.ToArray())
    }
}

function Add-MediaBuildLog {
    param([Parameter(Mandatory)][string]$Message)

    if (-not $script:ctx) { return }
    $list = Get-MediaCtxValue -Obj $script:ctx -Key 'LstMediaBuildLog'
    if (-not $list) { return }

    try {
        $text = ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message)
        [void]$list.Items.Add($text)
        $list.ScrollIntoView($text)
    } catch {}
}

function Add-MediaJobHistory {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$Status,
        [string]$Message = $null,
        [string]$Detail = $null,
        [string]$ErrorText = $null,
        [Nullable[datetime]]$StartedAt = $null,
        [Nullable[datetime]]$EndedAt = $null
    )

    try {
        if (-not (Get-Command Add-JobHistoryEntry -ErrorAction SilentlyContinue)) { return }
        $params = @{
            Operation = $Operation
            Status = $Status
            Message = $Message
            Detail = $Detail
            ErrorText = $ErrorText
        }
        if ($null -ne $StartedAt) { $params.StartedAt = [datetime]$StartedAt }
        if ($null -ne $EndedAt) {
            $params.EndedAt = [datetime]$EndedAt
            if ($null -ne $StartedAt) {
                $params.DurationMs = [int64](([datetime]$EndedAt) - ([datetime]$StartedAt)).TotalMilliseconds
            }
        }
        Add-JobHistoryEntry @params | Out-Null

        if ($Status -in @('Completed','Failed') -and (Get-Command Show-UiTaskNotification -ErrorAction SilentlyContinue)) {
            $notificationStatus = if ($Status -eq 'Completed') { 'Completed' } else { 'Failed' }
            $durationMs = if ($params.ContainsKey('DurationMs')) { [int64]$params.DurationMs } else { $null }
            try {
                Show-UiTaskNotification -Label $Operation -Status $notificationStatus -DurationMs $durationMs -Detail $Detail -ErrorText $ErrorText | Out-Null
            } catch {}
        }
    } catch {}
}

function Set-MediaBuildStatus {
    param(
        [string]$Message = $null,
        [string]$Detail = $null,
        [Nullable[long]]$SizeBytes = $null,
        [string]$SizeText = $null
    )

    if (-not $script:ctx) { return }

    try {
        if ($script:ctx.TxtMediaCurrentStep -and -not [string]::IsNullOrWhiteSpace($Message)) {
            $script:ctx.TxtMediaCurrentStep.Text = $Message
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaCurrentDetail) {
            $script:ctx.TxtMediaCurrentDetail.Text = if ([string]::IsNullOrWhiteSpace($Detail)) { '-' } else { $Detail }
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaCurrentSize) {
            if (-not [string]::IsNullOrWhiteSpace($SizeText)) {
                $script:ctx.TxtMediaCurrentSize.Text = $SizeText
            }
            elseif ($null -ne $SizeBytes) {
                $script:ctx.TxtMediaCurrentSize.Text = (Format-MediaBytes -Bytes ([long]$SizeBytes))
            }
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaElapsed) {
            if ($script:mediaBusyStartedAt) {
                $elapsed = (Get-Date) - $script:mediaBusyStartedAt
                $script:ctx.TxtMediaElapsed.Text = ('{0:mm\:ss}' -f $elapsed)
            } else {
                $script:ctx.TxtMediaElapsed.Text = '00:00'
            }
        }
    } catch {}
}

function Stop-MediaProgressMonitor {
    if ($script:mediaProgressTimer) {
        try { $script:mediaProgressTimer.Stop() } catch {}
        $script:mediaProgressTimer = $null
    }
}

function Stop-MediaProcessTree {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process) { return }

    $ids = New-Object System.Collections.Generic.List[int]
    function Add-ChildProcessIds {
        param([int]$ParentId)

        try {
            $children = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $ParentId))
            foreach ($child in $children) {
                Add-ChildProcessIds -ParentId ([int]$child.ProcessId)
                [void]$ids.Add([int]$child.ProcessId)
            }
        } catch {}
    }

    try { Add-ChildProcessIds -ParentId ([int]$Process.Id) } catch {}
    try { [void]$ids.Add([int]$Process.Id) } catch {}

    foreach ($id in @($ids.ToArray() | Select-Object -Unique)) {
        try { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Remove-MediaBuildArtifacts {
    param(
        [string[]]$Paths = @(),
        [string]$OutputPath = $null
    )

    foreach ($path in @($Paths)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath) -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        try {
            $len = (Get-Item -LiteralPath $OutputPath).Length
            if ($len -le 4096) {
                Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function Stop-MediaBuild {
    if (-not $script:mediaBusy) { return }

    $script:mediaBuildCancelled = $true
    Add-MediaBuildLog 'Abbruch angefordert...'
    Add-MediaJobHistory `
        -Operation 'MediaBuilder:BuildInstallImage' `
        -Status 'Cancelled' `
        -Message 'Build abgebrochen.' `
        -Detail 'Worker und DISM wurden beendet.' `
        -StartedAt $script:mediaBusyStartedAt `
        -EndedAt (Get-Date)

    try { Stop-MediaProcessTree -Process $script:mediaBuildProcess } catch {}
    Remove-MediaBuildArtifacts -Paths $script:mediaBuildCleanupPaths -OutputPath $script:mediaBuildOutputPath

    $script:mediaBuildProcess = $null
    $script:mediaBuildCleanupPaths = @()
    $script:mediaBuildOutputPath = $null

    Set-MediaBusy -Busy $false
    Set-MediaBuildStatus -Message 'Build abgebrochen.' -Detail 'Worker und DISM wurden beendet.' -SizeBytes 0 -SizeText 'abgebrochen'
    if ($script:ctx.SetStatus) { & $script:ctx.SetStatus 'Build abgebrochen' }
    Refresh-MediaBuilderUI
}

function Start-MediaProgressMonitor {
    param(
        [string]$ProgressPath = $null,
        [string]$OutputPath = $null,
        [string]$TargetName = 'Install-Image',
        [string]$InitialMessage = 'Vorgang läuft...',
        [System.Diagnostics.Process]$Process = $null,
        [string]$ResultPath = $null,
        [string[]]$CleanupPaths = @(),
        [string]$JobOperation = $null,
        [object]$JobStartedAt = $null
    )

    Stop-MediaProgressMonitor

    $script:mediaProgressPath = $ProgressPath
    $script:mediaOutputPath = $OutputPath
    $script:mediaBusyStartedAt = if ($null -ne $JobStartedAt) { [datetime]$JobStartedAt } else { Get-Date }
    $initialDetail = if ($TargetName -eq 'install.esd') {
        'ESD-Komprimierung kann lange rechnen. Eine kleine Datei am Anfang ist normal.'
    } else {
        'DISM arbeitet im Hintergrund. Größere Images brauchen oft einige Minuten.'
    }
    Set-MediaBuildStatus -Message $InitialMessage -Detail $initialDetail -SizeBytes 0 -SizeText 'wartet auf DISM'
    Add-MediaBuildLog $InitialMessage

    $page = Get-MediaCtxValue -Obj $script:ctx -Key 'Page'
    if (-not $page -or -not $page.Dispatcher) { return }

    $fnSetBuildStatus = (Get-Item function:Set-MediaBuildStatus -ErrorAction Stop).ScriptBlock
    $fnAddBuildLog    = (Get-Item function:Add-MediaBuildLog -ErrorAction Stop).ScriptBlock
    $fnSetBusy        = (Get-Item function:Set-MediaBusy -ErrorAction Stop).ScriptBlock
    $fnRefreshUi      = (Get-Item function:Refresh-MediaBuilderUI -ErrorAction Stop).ScriptBlock
    $fnCleanup        = (Get-Item function:Remove-MediaBuildArtifacts -ErrorAction Stop).ScriptBlock
    $fnShowUiError    = (Get-Item function:Show-UiError -ErrorAction SilentlyContinue).ScriptBlock
    $fnAddJobHistory  = (Get-Item function:Add-MediaJobHistory -ErrorAction SilentlyContinue).ScriptBlock

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({
        try {
            if ($Process) {
                try { $Process.Refresh() } catch {}
                if ($Process.HasExited) {
                    $exitCode = -1
                    try { $exitCode = [int]$Process.ExitCode } catch {}

                    $result = $null
                    if (-not [string]::IsNullOrWhiteSpace($ResultPath) -and (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
                        try { $result = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
                    }

                    if ($exitCode -eq 0 -and $result -and $result.Success) {
                        $size = 0
                        try { $size = [long]$result.SizeBytes } catch {}
                        & $fnSetBuildStatus -Message ("{0} wurde erstellt." -f $TargetName) -Detail ([string]$result.OutputPath) -SizeBytes $size
                        & $fnAddBuildLog ("{0} fertig: {1}" -f $TargetName, [string]$result.OutputPath)
                        if ($fnAddJobHistory -and -not [string]::IsNullOrWhiteSpace([string]$JobOperation)) {
                            try {
                                & $fnAddJobHistory `
                                    -Operation $JobOperation `
                                    -Status 'Completed' `
                                    -Message ("{0} wurde erstellt." -f $TargetName) `
                                    -Detail ([string]$result.OutputPath) `
                                    -StartedAt $script:mediaBusyStartedAt `
                                    -EndedAt (Get-Date)
                            } catch {}
                        }
                        if ($script:ctx.SetStatus) {
                            & $script:ctx.SetStatus ("{0} erstellt: {1}" -f $TargetName, [string]$result.OutputPath)
                        }
                    } else {
                        $msg = "Install-Image konnte nicht erstellt werden. ExitCode=$exitCode"
                        if ($script:mediaBuildCancelled) {
                            $msg = 'Build wurde abgebrochen.'
                        }
                        if (-not $script:mediaBuildCancelled -and $result -and -not [string]::IsNullOrWhiteSpace([string]$result.Message)) {
                            $msg = [string]$result.Message
                        }
                        & $fnAddBuildLog ("Fehler: {0}" -f $msg)
                        if ($fnAddJobHistory -and -not [string]::IsNullOrWhiteSpace([string]$JobOperation)) {
                            try {
                                $status = if ($script:mediaBuildCancelled) { 'Cancelled' } else { 'Failed' }
                                $errorText = if ($script:mediaBuildCancelled) { $null } else { $msg }
                                & $fnAddJobHistory `
                                    -Operation $JobOperation `
                                    -Status $status `
                                    -Message $msg `
                                    -Detail $TargetName `
                                    -ErrorText $errorText `
                                    -StartedAt $script:mediaBusyStartedAt `
                                    -EndedAt (Get-Date)
                            } catch {}
                        }
                        if (-not $script:mediaBuildCancelled -and $fnShowUiError) { try { & $fnShowUiError -Message $msg } catch {} }
                        if ($script:ctx.SetStatus) { & $script:ctx.SetStatus 'Ready' }
                    }

                    try { $Process.Dispose() } catch {}
                    & $fnCleanup -Paths $CleanupPaths -OutputPath $script:mediaBuildOutputPath
                    $script:mediaBuildProcess = $null
                    $script:mediaBuildCleanupPaths = @()
                    $script:mediaBuildOutputPath = $null

                    & $fnSetBusy -Busy $false
                    & $fnRefreshUi
                    return
                }
            }

            $msg = $null
            $detail = $null
            $size = 0
            $sizeText = $null

            if (-not [string]::IsNullOrWhiteSpace($script:mediaProgressPath) -and (Test-Path -LiteralPath $script:mediaProgressPath -PathType Leaf)) {
                $progress = Get-Content -LiteralPath $script:mediaProgressPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $msg = [string]$progress.Message
                if ([int]$progress.Total -gt 0) {
                    $detail = ('Schritt {0} von {1} | {2}' -f [int]$progress.Current, [int]$progress.Total, [string]$progress.Status)
                } else {
                    $detail = [string]$progress.Status
                }
                $size = [long]$progress.SizeBytes

                $parts = New-Object System.Collections.Generic.List[string]
                if (-not [string]::IsNullOrWhiteSpace([string]$detail)) {
                    [void]$parts.Add([string]$detail)
                }

                $elapsedSec = 0
                try { $elapsedSec = [int]$progress.ElapsedSec } catch { $elapsedSec = 0 }
                if ($elapsedSec -gt 0) {
                    [void]$parts.Add(('DISM aktiv seit {0:mm\:ss}' -f ([TimeSpan]::FromSeconds($elapsedSec))))
                }

                $heartbeat = [string](Get-MediaCtxValue -Obj $progress -Key 'Heartbeat')
                if (-not [string]::IsNullOrWhiteSpace($heartbeat)) {
                    [void]$parts.Add(("DISM meldet: {0}" -f $heartbeat))
                } else {
                    $hint = [string](Get-MediaCtxValue -Obj $progress -Key 'Hint')
                    if (-not [string]::IsNullOrWhiteSpace($hint)) {
                        [void]$parts.Add($hint)
                    }
                }

                $detail = ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' | '
            }

            if ($size -le 0 -and -not [string]::IsNullOrWhiteSpace($script:mediaOutputPath) -and (Test-Path -LiteralPath $script:mediaOutputPath -PathType Leaf)) {
                $size = (Get-Item -LiteralPath $script:mediaOutputPath).Length
            }

            if ([string]::IsNullOrWhiteSpace($msg)) { $msg = 'Vorgang läuft...' }
            if ([string]::IsNullOrWhiteSpace($detail) -and $Process) {
                $detail = 'DISM arbeitet im Hintergrund. Das kann bei großen Images lange dauern.'
            }
            if ($Process -and $size -le 0) {
                $sizeText = '0 B (DISM schreibt oft erst am Ende)'
            }
            elseif ($Process -and $size -le 208) {
                $sizeText = 'wartet auf DISM-Ausgabe'
            }
            & $fnSetBuildStatus -Message $msg -Detail $detail -SizeBytes $size -SizeText $sizeText
        } catch {
            try { & $fnSetBuildStatus -Message 'Vorgang läuft...' -Detail 'Warte auf Statusdaten...' -SizeBytes 0 -SizeText 'warte...' } catch {}
        }
    }.GetNewClosure())

    $script:mediaProgressTimer = $timer
    $timer.Start()
}

function Set-MediaBusy {
    param(
        [Parameter(Mandatory)][bool]$Busy,
        [string]$Reason = $null
    )

    $script:mediaBusy = $Busy
    if (-not $script:ctx) { return }

    if (-not $Busy) {
        Stop-MediaProgressMonitor
        $script:mediaBusyStartedAt = $null
    }

    $targets = @(
        $script:ctx.BtnMediaPickInstallImage,
        $script:ctx.BtnMediaClearInstallImage,
        $script:ctx.BtnMediaPickBootImage,
        $script:ctx.BtnMediaClearBootImage,
        $script:ctx.BtnMediaBuildIso,
        $script:ctx.BtnMediaAddSourceImage,
        $script:ctx.BtnMediaRemoveSourceImage,
        $script:ctx.BtnMediaBuildInstallEsd,
        $script:ctx.BtnMediaPickUsbSource,
        $script:ctx.BtnMediaPickUsbTarget,
        $script:ctx.BtnMediaCheckUsb,
        $script:ctx.BtnMediaOpenUsbTarget,
        $script:ctx.BtnMediaResetUsb,
        $script:ctx.BtnMediaCopyToUsb,
        $script:ctx.RbMediaBuildWim,
        $script:ctx.RbMediaBuildEsd,
        $script:ctx.LstMediaComposeItems
    ) | Where-Object { $_ -ne $null }

    foreach ($ctrl in $targets) {
        try { $ctrl.IsEnabled = (-not $Busy) } catch {}
    }

    foreach ($cancelCtrl in @($script:ctx.BtnMediaCancelBuild, $script:ctx.BtnMediaCancelBuildOverlay)) {
        if ($cancelCtrl) {
            try { $cancelCtrl.IsEnabled = $Busy } catch {}
            try { $cancelCtrl.Visibility = if ($Busy) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed } } catch {}
        }
    }

    $overlay = Get-MediaCtxValue -Obj $script:ctx -Key 'BusyOverlay'
    if ($overlay) {
        try {
            $overlay.Visibility = if ($Busy) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        } catch {}
    }

    $txtBusy = Get-MediaCtxValue -Obj $script:ctx -Key 'TxtBusyMessage'
    if ($txtBusy) {
        try {
            $txtBusy.Text = if ($Busy -and $Reason) { $Reason } else { Get-UiString -Key 'MediaBusyDefault' }
        } catch {}
    }

    try {
        $page = Get-MediaCtxValue -Obj $script:ctx -Key 'Page'
        if ($Busy) {
            Start-UiBusyProgress -Root $page -Context $script:ctx -Message $(if ($Reason) { $Reason } else { Get-UiString -Key 'MediaBusyDefault' }) -Detail (Get-UiString -Key 'MediaBusyDetail') -ShowDismTail
        } else {
            Stop-UiBusyProgress -Root $page -Context $script:ctx
        }
    } catch {}

    try {
        $page = Get-MediaCtxValue -Obj $script:ctx -Key 'Page'
        if ($page) {
            $win = [System.Windows.Window]::GetWindow($page)
            if ($win) {
                $win.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { $null }
            }
        }
    } catch {}

    if ($Busy -and $Reason -and $script:ctx.SetStatus) {
        try { & $script:ctx.SetStatus $Reason } catch {}
    }
}

function Get-MediaIsoRoot {
    $root = Get-MediaAppStateValueSafe -Key 'IsoRoot' -Default $null
    if ([string]::IsNullOrWhiteSpace([string]$root)) {
        $root = Get-MediaAppStateValueSafe -Key 'IsoRootPath' -Default $null
    }
    return $root
}

function Get-MediaIsoInstallDefault {
    return (Get-MediaAppStateValueSafe -Key 'IsoInstallImagePath' -Default $null)
}

function Get-MediaIsoBootDefault {
    $value = Get-MediaAppStateValueSafe -Key 'BootImagePath' -Default $null
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        $value = Get-MediaAppStateValueSafe -Key 'IsoBootPath' -Default $null
    }
    return $value
}

function Get-DisplayOrDash {
    param($Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '-' }
    return [string]$Value
}

function Refresh-MediaBuilderComposeList {
    if (-not $script:ctx) { return }

    $items = @($script:composeItems.ToArray())
    try {
        if ($script:ctx.LstMediaComposeItems) {
            $script:ctx.LstMediaComposeItems.ItemsSource = $null
            $script:ctx.LstMediaComposeItems.ItemsSource = $items
            $script:ctx.LstMediaComposeItems.Items.Refresh()
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaComposeSummary) {
            if ($items.Count -gt 0) {
                $mode = Get-MediaInstallBuildMode
                $target = if ($mode -eq 'Esd') { 'install.esd' } else { 'install.wim' }
                $hint = if ($mode -eq 'Esd') { Get-UiString -Key 'MediaComposeSummaryEsdHint' } else { Get-UiString -Key 'MediaComposeSummaryWimHint' }
                $script:ctx.TxtMediaComposeSummary.Text = Get-UiString -Key 'MediaComposeSummaryFormat' -Args @($items.Count, $target, $hint)
            } else {
                $script:ctx.TxtMediaComposeSummary.Text = Get-UiString -Key 'MediaNoSourceFiles'
            }
        }
    } catch {}
}

function Get-MediaInstallBuildMode {
    try {
        if ($script:ctx -and $script:ctx.RbMediaBuildEsd -and $script:ctx.RbMediaBuildEsd.IsChecked -eq $true) {
            return 'Esd'
        }
    } catch {}
    return 'Wim'
}

function Refresh-MediaBuilderUI {
    if (-not $script:ctx) { return }

    $isoRoot = Get-MediaIsoRoot
    $installDefault = Get-MediaIsoInstallDefault
    $bootDefault = Get-MediaIsoBootDefault

    try { $script:ctx.TxtMediaSourceIso.Text = (Get-DisplayOrDash $isoRoot) } catch {}

    $effectiveInstall = $script:ctx.SelectedInstallImagePath
    if ([string]::IsNullOrWhiteSpace([string]$effectiveInstall)) { $effectiveInstall = $installDefault }
    $effectiveBoot = $script:ctx.SelectedBootImagePath
    if ([string]::IsNullOrWhiteSpace([string]$effectiveBoot)) { $effectiveBoot = $bootDefault }

    try { $script:ctx.TxtMediaInstallImage.Text = (Get-DisplayOrDash $effectiveInstall) } catch {}
    try { $script:ctx.TxtMediaBootImage.Text = (Get-DisplayOrDash $effectiveBoot) } catch {}

    try {
        if ($script:ctx.BtnMediaBuildIso) {
            $script:ctx.BtnMediaBuildIso.IsEnabled = ((-not $script:mediaBusy) -and (-not [string]::IsNullOrWhiteSpace([string]$isoRoot)))
        }
    } catch {}

    try {
        if ($script:ctx.BtnMediaBuildInstallEsd) {
            $mode = Get-MediaInstallBuildMode
            $target = if ($mode -eq 'Esd') { Get-UiString -Key 'MediaBuildInstallEsdButton' } else { Get-UiString -Key 'MediaBuildInstallWimButton' }
            $script:ctx.BtnMediaBuildInstallEsd.Content = $target
            $script:ctx.BtnMediaBuildInstallEsd.IsEnabled = ((-not $script:mediaBusy) -and ($script:composeItems.Count -gt 0))
        }
    } catch {}

    try {
        if ($script:ctx.RbMediaBuildWim) { $script:ctx.RbMediaBuildWim.IsEnabled = (-not $script:mediaBusy) }
        if ($script:ctx.RbMediaBuildEsd) { $script:ctx.RbMediaBuildEsd.IsEnabled = (-not $script:mediaBusy) }
    } catch {}

    try {
        if ($script:ctx.BtnMediaRemoveSourceImage -and $script:ctx.LstMediaComposeItems) {
            $script:ctx.BtnMediaRemoveSourceImage.IsEnabled = ((-not $script:mediaBusy) -and (@($script:ctx.LstMediaComposeItems.SelectedItems).Count -gt 0))
        }
    } catch {}

    Refresh-MediaUsbUI
    Refresh-MediaBuilderComposeList
}

function Pick-MediaImageFile {
    param(
        [Parameter(Mandatory)][string]$Title
    )

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = Get-LocalizedText -Text $Title
    $dlg.Filter = Get-UiString -Key 'MediaImageDialogFilter'
    $dlg.Multiselect = $false
    if ($dlg.ShowDialog() -ne $true) { return $null }
    return [string]$dlg.FileName
}

function Pick-MediaFolder {
    param([Parameter(Mandatory)][string]$Description)

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = Get-LocalizedText -Text $Description
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return [string]$dlg.SelectedPath
}

function Get-MediaUsbSource {
    $selected = $script:ctx.SelectedUsbSourcePath
    if (-not [string]::IsNullOrWhiteSpace([string]$selected)) { return [string]$selected }
    return [string](Get-MediaIsoRoot)
}

function Format-MediaUsbTargetDisplay {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '-' }

    try {
        $drive = Get-MediaDriveInfo -Path $Path
        if ($drive -and $drive.IsReady) {
            $fileSystem = [string]$drive.DriveFormat
            if ([string]::IsNullOrWhiteSpace($fileSystem)) { $fileSystem = '-' }
            return (Get-UiString -Key 'MediaUsbTargetDisplayFormat' -Args @(
                [string]$Path,
                $fileSystem,
                (Format-MediaBytes ([int64]$drive.AvailableFreeSpace))
            ))
        }
    } catch {}

    return [string]$Path
}

function Get-MediaDirectorySizeInfo {
    param([Parameter(Mandatory)][string]$Path)

    $totalBytes = [int64]0
    $largestFile = $null
    $fileCount = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue)) {
        $fileCount++
        $length = [int64]$file.Length
        $totalBytes += $length
        if (-not $largestFile -or $length -gt [int64]$largestFile.Length) {
            $largestFile = $file
        }
    }

    return [pscustomobject]@{
        TotalBytes  = $totalBytes
        FileCount   = $fileCount
        LargestFile = $largestFile
    }
}

function Refresh-MediaUsbUI {
    if (-not $script:ctx) { return }

    $source = Get-MediaUsbSource
    $target = $script:ctx.SelectedUsbTargetPath

    try { if ($script:ctx.TxtMediaUsbSource) { $script:ctx.TxtMediaUsbSource.Text = (Get-DisplayOrDash $source) } } catch {}
    try { if ($script:ctx.TxtMediaUsbTarget) { $script:ctx.TxtMediaUsbTarget.Text = (Format-MediaUsbTargetDisplay -Path $target) } } catch {}

    try {
        if ($script:ctx.BtnMediaCopyToUsb) {
            $script:ctx.BtnMediaCopyToUsb.IsEnabled = (
                (-not $script:mediaBusy) -and
                (-not [string]::IsNullOrWhiteSpace([string]$source)) -and
                (-not [string]::IsNullOrWhiteSpace([string]$target))
            )
        }
        if ($script:ctx.BtnMediaCheckUsb) {
            $script:ctx.BtnMediaCheckUsb.IsEnabled = (
                (-not $script:mediaBusy) -and
                (-not [string]::IsNullOrWhiteSpace([string]$source)) -and
                (-not [string]::IsNullOrWhiteSpace([string]$target))
            )
        }
        if ($script:ctx.BtnMediaOpenUsbTarget) {
            $script:ctx.BtnMediaOpenUsbTarget.IsEnabled = (
                (-not $script:mediaBusy) -and
                (-not [string]::IsNullOrWhiteSpace([string]$target)) -and
                (Test-Path -LiteralPath ([string]$target) -PathType Container)
            )
        }
        if ($script:ctx.BtnMediaResetUsb) {
            $script:ctx.BtnMediaResetUsb.IsEnabled = (
                (-not $script:mediaBusy) -and
                (
                    (-not [string]::IsNullOrWhiteSpace([string]$script:ctx.SelectedUsbSourcePath)) -or
                    (-not [string]::IsNullOrWhiteSpace([string]$script:ctx.SelectedUsbTargetPath))
                )
            )
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaUsbSummary) {
            if ([string]::IsNullOrWhiteSpace([string]$source)) {
                $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbSourceMissing'
            } elseif ([string]::IsNullOrWhiteSpace([string]$target)) {
                $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbTargetMissing'
            } else {
                $drive = Get-MediaDriveInfo -Path ([string]$target)
                if ($drive -and $drive.IsReady) {
                    $fileSystem = [string]$drive.DriveFormat
                    if ([string]::IsNullOrWhiteSpace($fileSystem)) { $fileSystem = '-' }
                    $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbReadyWithTargetFormat' -Args @(
                        [string]$target,
                        (Format-MediaBytes ([int64]$drive.AvailableFreeSpace)),
                        $fileSystem
                    )
                } else {
                    $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbReady'
                }
            }
        }
    } catch {}
}

function Open-MediaUsbTarget {
    if ($script:mediaBusy -or -not $script:ctx) { return }

    try {
        $target = [string]$script:ctx.SelectedUsbTargetPath
        if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-Path -LiteralPath $target -PathType Container)) {
            throw (Get-UiString -Key 'MediaUsbTargetOpenMissing')
        }

        Start-Process -FilePath $target | Out-Null
        $message = Get-UiString -Key 'MediaUsbTargetOpenedFormat' -Args @($target)
        Add-MediaBuildLog $message
        if ($script:ctx.SetStatus) { & $script:ctx.SetStatus $message }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Reset-MediaUsbSelection {
    if ($script:mediaBusy -or -not $script:ctx) { return }

    $script:ctx.SelectedUsbSourcePath = $null
    $script:ctx.SelectedUsbTargetPath = $null
    Remove-MediaAppStateValueSafe -Key 'MediaUsbSourcePath'
    Remove-MediaAppStateValueSafe -Key 'MediaUsbTargetPath'
    Refresh-MediaBuilderUI

    $message = Get-UiString -Key 'MediaUsbResetStatus'
    Add-MediaBuildLog $message
    if ($script:ctx.SetStatus) { & $script:ctx.SetStatus $message }
}

function Test-MediaUsbCopyPrerequisites {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw (Get-UiString -Key 'MediaUsbSourceMissingPathFormat' -Args @($SourcePath))
    }
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw (Get-UiString -Key 'MediaUsbTargetMissingPathFormat' -Args @($TargetPath))
    }

    $sourceFull = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\')
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
    if ($sourceFull.Equals($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (Get-UiString -Key 'MediaUsbSamePath')
    }
    if ($targetFull.StartsWith($sourceFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (Get-UiString -Key 'MediaUsbTargetInsideSource')
    }

    $bootFile = Join-Path $sourceFull 'bootmgr'
    $efiBoot = Join-Path $sourceFull 'efi\boot\bootx64.efi'
    $sourcesDir = Join-Path $sourceFull 'sources'
    $hasSources = Test-Path -LiteralPath $sourcesDir -PathType Container
    $hasBootFiles = (Test-Path -LiteralPath $bootFile -PathType Leaf) -or (Test-Path -LiteralPath $efiBoot -PathType Leaf)

    if (-not (Test-Path -LiteralPath $sourcesDir -PathType Container)) {
        Add-MediaBuildLog (Get-UiString -Key 'MediaUsbMissingSourcesWarning')
    }
    if (-not $hasBootFiles) {
        Add-MediaBuildLog (Get-UiString -Key 'MediaUsbMissingBootWarning')
    }

    $sizeInfo = Get-MediaDirectorySizeInfo -Path $sourceFull
    $drive = Get-MediaDriveInfo -Path $targetFull
    $fileSystem = ''
    $availableFreeSpace = [int64]0
    if ($drive -and $drive.IsReady) {
        try { $fileSystem = [string]$drive.DriveFormat } catch { $fileSystem = '' }
        try { $availableFreeSpace = [int64]$drive.AvailableFreeSpace } catch { $availableFreeSpace = 0 }

        if ([int64]$sizeInfo.TotalBytes -gt 0 -and $availableFreeSpace -lt [int64]$sizeInfo.TotalBytes) {
            throw (Get-UiString -Key 'MediaUsbInsufficientSpaceFormat' -Args @($drive.Name, (Format-MediaBytes $availableFreeSpace), (Format-MediaBytes $sizeInfo.TotalBytes)))
        }

        $largestFile = $sizeInfo.LargestFile
        if ($largestFile -and $fileSystem -eq 'FAT32' -and [int64]$largestFile.Length -ge 4GB) {
            throw (Get-UiString -Key 'MediaUsbFat32LargeFileFormat' -Args @([string]$largestFile.FullName, (Format-MediaBytes ([int64]$largestFile.Length))))
        }
    }

    return [pscustomobject]@{
        Source             = $sourceFull
        Target             = $targetFull
        SourceBytes        = [int64]$sizeInfo.TotalBytes
        SourceText         = Format-MediaBytes ([int64]$sizeInfo.TotalBytes)
        FileCount          = [int]$sizeInfo.FileCount
        TargetFreeBytes    = $availableFreeSpace
        TargetFreeText     = $(if ($availableFreeSpace -gt 0) { Format-MediaBytes $availableFreeSpace } else { '-' })
        TargetDriveName    = $(if ($drive) { [string]$drive.Name } else { '-' })
        TargetFileSystem   = $(if ([string]::IsNullOrWhiteSpace($fileSystem)) { '-' } else { $fileSystem })
        HasSources         = $hasSources
        HasBootFiles       = $hasBootFiles
    }
}

function Start-MediaUsbCheck {
    if ($script:mediaBusy) { return }

    try {
        $check = Test-MediaUsbCopyPrerequisites -SourcePath (Get-MediaUsbSource) -TargetPath $script:ctx.SelectedUsbTargetPath
        $message = Get-UiString -Key 'MediaUsbCheckOkMessageFormat' -Args @(
            [string]$check.Source,
            [string]$check.Target,
            [string]$check.TargetFileSystem,
            [string]$check.SourceText,
            [string]$check.TargetFreeText
        )
        Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCheckStatusFormat' -Args @([string]$check.SourceText, [string]$check.TargetFreeText, [string]$check.TargetDriveName))
        Set-MediaBuildStatus -Message (Get-UiString -Key 'MediaUsbCheckOkTitle') -Detail $message -SizeBytes ([int64]$check.SourceBytes) -SizeText ([string]$check.SourceText)
        if ($script:ctx.SetStatus) { & $script:ctx.SetStatus (Get-UiString -Key 'MediaUsbCheckStatusFormat' -Args @([string]$check.SourceText, [string]$check.TargetFreeText, [string]$check.TargetDriveName)) }
        Show-UiInfo -Title (Get-UiString -Key 'MediaUsbCheckOkTitle') -Message $message
        Refresh-MediaBuilderUI
    } catch {
        Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'MediaUsbCheckOkTitle')
    }
}

function Start-MediaUsbCopyAsync {
    if ($script:mediaBusy) { return }

    try {
        $source = Get-MediaUsbSource
        $target = $script:ctx.SelectedUsbTargetPath
        $check = Test-MediaUsbCopyPrerequisites -SourcePath $source -TargetPath $target

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $answer = [System.Windows.MessageBox]::Show(
            (Get-UiString -Key 'MediaUsbCopyConfirmFormat' -Args @([string]$check.Source, [string]$check.Target, [string]$check.SourceText, [string]$check.TargetFreeText, [string]$check.TargetFileSystem)),
            (Get-UiString -Key 'MediaUsbCopyTitle'),
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Information
        )
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Set-MediaBusy -Busy $true -Reason (Get-UiString -Key 'MediaUsbCopyBusy')
        Set-MediaBuildStatus -Message (Get-UiString -Key 'MediaUsbCopyBusy') -Detail (Get-UiString -Key 'MediaUsbCopyDetail') -SizeBytes ([int64]$check.SourceBytes) -SizeText (Get-UiString -Key 'MediaUsbCopySizeText')
        Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCopyStartLogFormat' -Args @([string]$check.Source, [string]$check.Target))

        $safeSource = ([string]$check.Source).Replace("'", "''")
        $safeTarget = ([string]$check.Target).Replace("'", "''")
        $code = @"
`$ErrorActionPreference = 'Stop'
`$source = '$safeSource'
`$target = '$safeTarget'
`$args = @(`$source, `$target, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/NP')
`$output = & robocopy.exe @args 2>&1 | Out-String
`$exitCode = `$LASTEXITCODE
if (`$exitCode -gt 7) {
    throw "__ROBOCOPY_FAILED__" -f `$exitCode, `$output
}
[pscustomobject]@{
    Source = `$source
    Target = `$target
    ExitCode = `$exitCode
    Output = `$output
}
"@
        $code = $code.Replace('__ROBOCOPY_FAILED__', (Get-UiString -Key 'MediaUsbRobocopyFailedFormat').Replace("'", "''"))

        Start-UiTask -Label 'MediaBuilder:UsbCopy' -Work ([scriptblock]::Create($code)) -OnCompleted {
            param($result)
            try {
                $item = @($result) | Select-Object -First 1
                Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCopyDoneLogFormat' -Args @([int]$item.ExitCode))
                $detail = Get-UiString -Key 'MediaUsbCopyDoneDetailFormat' -Args @([string]$item.Target, [int]$item.ExitCode)
                Set-MediaBuildStatus -Message (Get-UiString -Key 'MediaUsbCopyDone') -Detail $detail -SizeBytes 0 -SizeText (Get-UiString -Key 'MediaUsbCopyDone')
                if ($script:ctx.SetStatus) { & $script:ctx.SetStatus (Get-UiString -Key 'MediaUsbCopyDoneStatus') }
            } finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
            }
        } -OnError {
            param($ex)
            try {
                Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCopyErrorLogFormat' -Args @($ex.Message))
                Show-UiError -Message $ex.Message -Title (Get-UiString -Key 'MediaUsbCopyTitle')
            } finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
                if ($script:ctx.SetStatus) { & $script:ctx.SetStatus 'Ready' }
            }
        }
    } catch {
        Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'MediaUsbCopyTitle')
    }
}

function Start-MediaBuildIsoAsync {
    if ($script:mediaBusy) { return }

    try {
        $sourceRoot = Get-MediaIsoRoot
        if ([string]::IsNullOrWhiteSpace([string]$sourceRoot)) {
            throw "Bitte zuerst eine Windows-ISO mounten. Diese ISO ist die Grundlage für den Build."
        }

        $installImagePath = $script:ctx.SelectedInstallImagePath
        if ([string]::IsNullOrWhiteSpace([string]$installImagePath)) {
            $installImagePath = Get-MediaIsoInstallDefault
        }

        $bootImagePath = $script:ctx.SelectedBootImagePath
        if ([string]::IsNullOrWhiteSpace([string]$bootImagePath)) {
            $bootImagePath = Get-MediaIsoBootDefault
        }

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'ISO speichern unter'
        $dlg.Filter = 'ISO (*.iso)|*.iso|Alle Dateien (*.*)|*.*'
        $dlg.DefaultExt = '.iso'
        $dlg.AddExtension = $true
        $dlg.OverwritePrompt = $true
        $dlg.FileName = ('windows-custom-{0}.iso' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        if ($dlg.ShowDialog() -ne $true) { return }

        $dest = [string]$dlg.FileName
        if ([string]::IsNullOrWhiteSpace($dest)) { return }

        Set-MediaBusy -Busy $true -Reason 'Neue ISO wird gebaut...'
        Start-MediaProgressMonitor -OutputPath $dest -InitialMessage 'Neue ISO wird gebaut...'

        $bootstrapPath = (Resolve-ProjectPath 'Core\Bootstrap.psm1' -MustExist).Replace("'", "''")
        $projectRoot = (Get-ProjectRoot).Replace("'", "''")
        $servicePath = (Resolve-ProjectPath 'Services\IsoBuildService.psm1' -MustExist).Replace("'", "''")
        $safeSource = $sourceRoot.Replace("'", "''")
        $safeDest = $dest.Replace("'", "''")
        $safeInstall = ([string]$installImagePath).Replace("'", "''")
        $safeBoot = ([string]$bootImagePath).Replace("'", "''")

        $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__BOOTSTRAP__' -Force -DisableNameChecking
Set-ProjectRoot -Path '__PROJECTROOT__' | Out-Null
Import-Module '__SERVICE__' -Force -DisableNameChecking

$params = @{
    SourceRoot = '__SOURCE__'
    OutputPath = '__DEST__'
}

$install = '__INSTALL__'
if (-not [string]::IsNullOrWhiteSpace($install)) { $params.InstallImagePath = $install }

$boot = '__BOOT__'
if (-not [string]::IsNullOrWhiteSpace($boot)) { $params.BootImagePath = $boot }

Build-WindowsIso @params
'@
        $code = $code.Replace('__BOOTSTRAP__', $bootstrapPath).
            Replace('__PROJECTROOT__', $projectRoot).
            Replace('__SERVICE__', $servicePath).
            Replace('__SOURCE__', $safeSource).
            Replace('__DEST__', $safeDest).
            Replace('__INSTALL__', $safeInstall).
            Replace('__BOOT__', $safeBoot)

        Start-UiTask -Label 'MediaBuilder:BuildIso' -Work ([scriptblock]::Create($code)) -OnCompleted {
            param($result)
            try {
                $item = @($result) | Select-Object -First 1
                if ($script:ctx.SetStatus -and $item) {
                    & $script:ctx.SetStatus ("ISO erstellt: {0}" -f $item.OutputPath)
                }
                Add-MediaBuildLog ("ISO fertig: {0}" -f $item.OutputPath)
            } finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
            }
        } -OnError {
            param($ex)
            try { Show-UiError -Message $ex.Message }
            finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
                if ($script:ctx.SetStatus) { & $script:ctx.SetStatus 'Ready' }
            }
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Add-MediaComposeSourceImage {
    try {
        $path = Pick-MediaImageFile -Title (Get-UiString -Key 'MediaPickComposeSourceTitle')
        if ([string]::IsNullOrWhiteSpace([string]$path)) { return }

        $items = @(Get-WimImageList -ImagePath $path)
        if ($items.Count -lt 1) {
            throw "Im gewählten Image wurden keine exportierbaren Indexe gefunden."
        }

        foreach ($item in $items) {
            $script:composeItems.Add([pscustomobject]@{
                Path        = $path
                FileName    = [System.IO.Path]::GetFileName($path)
                Index       = [int]$item.Index
                Name        = [string]$item.Name
                Description = [string]$item.Description
            }) | Out-Null
        }

        if ($script:ctx.SetStatus) {
            & $script:ctx.SetStatus ("{0} Index(e) aus {1} übernommen" -f $items.Count, $path)
        }
        Refresh-MediaBuilderUI
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Remove-MediaComposeSelectedItems {
    if (-not $script:ctx -or -not $script:ctx.LstMediaComposeItems) { return }

    $selected = @($script:ctx.LstMediaComposeItems.SelectedItems)
    if ($selected.Count -lt 1) { return }

    foreach ($item in $selected) {
        [void]$script:composeItems.Remove($item)
    }

    if ($script:ctx.SetStatus) {
        & $script:ctx.SetStatus ("{0} Eintrag/Einträge entfernt" -f $selected.Count)
    }
    Refresh-MediaBuilderUI
}

function Start-MediaBuildInstallEsdAsync {
    if ($script:mediaBusy) { return }
    if ($script:composeItems.Count -lt 1) { return }

    $jobStartedAt = $null
    $dest = $null
    try {
        $mode = Get-MediaInstallBuildMode
        $isEsd = ($mode -eq 'Esd')
        $targetName = if ($isEsd) { 'install.esd' } else { 'install.wim' }
        $compression = if ($isEsd) { 'recovery' } else { 'max' }

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = "$targetName speichern unter"
        $dlg.Filter = if ($isEsd) { 'ESD (*.esd)|*.esd|WIM (*.wim)|*.wim|Alle Dateien (*.*)|*.*' } else { 'WIM (*.wim)|*.wim|ESD (*.esd)|*.esd|Alle Dateien (*.*)|*.*' }
        $dlg.DefaultExt = if ($isEsd) { '.esd' } else { '.wim' }
        $dlg.AddExtension = $true
        $dlg.OverwritePrompt = $true
        $dlg.FileName = $targetName
        if ($dlg.ShowDialog() -ne $true) { return }

        $dest = [string]$dlg.FileName
        if ([string]::IsNullOrWhiteSpace($dest)) { return }

        $jobStartedAt = Get-Date
        $precheck = Test-MediaInstallBuildPrerequisites -Items @($script:composeItems.ToArray()) -DestinationPath $dest -Mode $mode
        foreach ($warning in @($precheck.Warnings)) {
            Add-MediaBuildLog ("Check: {0}" -f $warning)
        }

        if (-not $precheck.Success) {
            $message = "Der Build wurde nicht gestartet, weil der Vorab-Check Probleme gefunden hat:`r`n`r`n"
            $message += (($precheck.Errors | ForEach-Object { "- $_" }) -join "`r`n")
            if ($precheck.Warnings.Count -gt 0) {
                $message += "`r`n`r`nHinweise:`r`n"
                $message += (($precheck.Warnings | ForEach-Object { "- $_" }) -join "`r`n")
            }

            foreach ($err in @($precheck.Errors)) {
                Add-MediaBuildLog ("Check fehlgeschlagen: {0}" -f $err)
            }
            Add-MediaJobHistory `
                -Operation 'MediaBuilder:BuildInstallImage' `
                -Status 'Skipped' `
                -Message 'Build nicht gestartet.' `
                -Detail $dest `
                -ErrorText (($precheck.Errors | ForEach-Object { [string]$_ }) -join "`n") `
                -StartedAt $jobStartedAt `
                -EndedAt (Get-Date)
            Set-MediaBuildStatus -Message 'Build nicht gestartet.' -Detail 'Der Vorab-Check hat Probleme gefunden.' -SizeBytes 0 -SizeText 'Check fehlgeschlagen'
            Show-UiError -Message $message
            return
        }

        Add-MediaBuildLog 'Vorab-Check erfolgreich.'
        Add-MediaJobHistory `
            -Operation 'MediaBuilder:BuildInstallImage' `
            -Status 'Started' `
            -Message ("{0} wird gebaut..." -f $targetName) `
            -Detail $dest `
            -StartedAt $jobStartedAt
        $script:mediaBuildCancelled = $false
        Set-MediaBusy -Busy $true -Reason ("{0} wird gebaut..." -f $targetName)

        $bootstrapPath = (Resolve-ProjectPath 'Core\Bootstrap.psm1' -MustExist).Replace("'", "''")
        $projectRoot = (Get-ProjectRoot).Replace("'", "''")
        $servicePath = (Resolve-ProjectPath 'Services\ImageCompositionService.psm1' -MustExist).Replace("'", "''")
        $safeDest = $dest.Replace("'", "''")
        $safeCompression = $compression.Replace("'", "''")
        $manifestPath = Join-Path ([System.IO.Path]::GetTempPath()) ('media-builder-compose-{0}.json' -f ([guid]::NewGuid().ToString('N')))
        $progressPath = Join-Path ([System.IO.Path]::GetTempPath()) ('media-builder-progress-{0}.json' -f ([guid]::NewGuid().ToString('N')))
        $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) ('media-builder-result-{0}.json' -f ([guid]::NewGuid().ToString('N')))
        $workerPath = Join-Path ([System.IO.Path]::GetTempPath()) ('media-builder-worker-{0}.ps1' -f ([guid]::NewGuid().ToString('N')))
        @($script:composeItems.ToArray()) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        $safeManifest = $manifestPath.Replace("'", "''")
        $safeProgress = $progressPath.Replace("'", "''")
        $safeResult = $resultPath.Replace("'", "''")

        $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__BOOTSTRAP__' -Force -DisableNameChecking
Set-ProjectRoot -Path '__PROJECTROOT__' | Out-Null
Import-Module '__SERVICE__' -Force -DisableNameChecking
try {
    $specs = Get-Content -LiteralPath '__MANIFEST__' -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = Build-CombinedInstallImage -ImageSpecs @($specs) -OutputPath '__DEST__' -ProgressPath '__PROGRESS__' -Compression '__COMPRESSION__'
    [pscustomobject]@{
        Success   = $true
        OutputPath = [string]$result.OutputPath
        ImageCount = [int]$result.ImageCount
        SizeBytes  = [long]$result.SizeBytes
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8
    exit 0
}
catch {
    [pscustomobject]@{
        Success = $false
        Message = $_.Exception.Message
        Details = [string]$_
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8
    exit 1
}
finally {
    if (Test-Path -LiteralPath '__MANIFEST__') {
        Remove-Item -LiteralPath '__MANIFEST__' -Force -ErrorAction SilentlyContinue
    }
}
'@
        $code = $code.Replace('__BOOTSTRAP__', $bootstrapPath).
            Replace('__PROJECTROOT__', $projectRoot).
            Replace('__SERVICE__', $servicePath).
            Replace('__MANIFEST__', $safeManifest).
            Replace('__PROGRESS__', $safeProgress).
            Replace('__RESULT__', $safeResult).
            Replace('__COMPRESSION__', $safeCompression).
            Replace('__DEST__', $safeDest)

        [System.IO.File]::WriteAllText($workerPath, $code, [System.Text.UTF8Encoding]::new($true))

        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $psExe
        $pinfo.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $workerPath.Replace('"','""'))
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $pinfo
        $null = $proc.Start()

        $script:mediaBuildProcess = $proc
        $script:mediaBuildCleanupPaths = @($manifestPath, $workerPath, $resultPath, $progressPath)
        $script:mediaBuildOutputPath = $dest

        Add-MediaBuildLog ("Worker gestartet: PID {0}" -f $proc.Id)
        Start-MediaProgressMonitor `
            -ProgressPath $progressPath `
            -OutputPath $dest `
            -TargetName $targetName `
            -InitialMessage ("{0} wird gebaut..." -f $targetName) `
            -Process $proc `
            -ResultPath $resultPath `
            -CleanupPaths @($manifestPath, $workerPath, $resultPath, $progressPath) `
            -JobOperation 'MediaBuilder:BuildInstallImage' `
            -JobStartedAt $jobStartedAt
    } catch {
        Add-MediaJobHistory `
            -Operation 'MediaBuilder:BuildInstallImage' `
            -Status 'Failed' `
            -Message 'Build konnte nicht gestartet werden.' `
            -Detail $dest `
            -ErrorText $_.Exception.Message `
            -StartedAt $jobStartedAt `
            -EndedAt (Get-Date)
        Set-MediaBusy -Busy $false
        $script:mediaBuildProcess = $null
        $script:mediaBuildCleanupPaths = @()
        $script:mediaBuildOutputPath = $null
        Show-UiError -Message $_.Exception.Message
    }
}

function Initialize-MediaBuilderController {
    param(
        [Parameter(Mandatory)]$MediaBuilderPage,
        [Parameter(Mandatory)][scriptblock]$SetStatus,
        [Parameter()][scriptblock]$OnStateChanged
    )

    $script:ctx = [ordered]@{
        Page                        = $MediaBuilderPage
        SetStatus                   = $SetStatus
        OnStateChanged              = $OnStateChanged
        SelectedInstallImagePath    = $null
        SelectedBootImagePath       = $null
        SelectedUsbSourcePath       = Get-MediaAppStateValueSafe -Key 'MediaUsbSourcePath' -Default $null
        SelectedUsbTargetPath       = Get-MediaAppStateValueSafe -Key 'MediaUsbTargetPath' -Default $null
        TxtMediaSourceIso           = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaSourceIso'
        TxtMediaInstallImage        = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaInstallImage'
        TxtMediaBootImage           = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaBootImage'
        BtnMediaPickInstallImage    = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaPickInstallImage'
        BtnMediaClearInstallImage   = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaClearInstallImage'
        BtnMediaPickBootImage       = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaPickBootImage'
        BtnMediaClearBootImage      = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaClearBootImage'
        BtnMediaBuildIso            = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaBuildIso'
        LstMediaComposeItems        = Find-Ui -Root $MediaBuilderPage -Name 'LstMediaComposeItems'
        TxtMediaComposeSummary      = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaComposeSummary'
        BtnMediaAddSourceImage      = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaAddSourceImage'
        BtnMediaRemoveSourceImage   = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaRemoveSourceImage'
        BtnMediaBuildInstallEsd     = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaBuildInstallEsd'
        BtnMediaCancelBuild         = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaCancelBuild'
        BtnMediaCancelBuildOverlay  = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaCancelBuildOverlay'
        TxtMediaUsbSource           = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaUsbSource'
        TxtMediaUsbTarget           = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaUsbTarget'
        TxtMediaUsbSummary          = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaUsbSummary'
        BtnMediaPickUsbSource       = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaPickUsbSource'
        BtnMediaPickUsbTarget       = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaPickUsbTarget'
        BtnMediaCheckUsb            = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaCheckUsb'
        BtnMediaOpenUsbTarget       = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaOpenUsbTarget'
        BtnMediaResetUsb            = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaResetUsb'
        BtnMediaCopyToUsb           = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaCopyToUsb'
        RbMediaBuildWim             = Find-Ui -Root $MediaBuilderPage -Name 'RbMediaBuildWim'
        RbMediaBuildEsd             = Find-Ui -Root $MediaBuilderPage -Name 'RbMediaBuildEsd'
        BusyOverlay                 = Find-Ui -Root $MediaBuilderPage -Name 'BusyOverlay'
        TxtBusyMessage              = Find-Ui -Root $MediaBuilderPage -Name 'TxtBusyMessage'
        TxtMediaCurrentStep         = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaCurrentStep'
        TxtMediaCurrentDetail       = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaCurrentDetail'
        TxtMediaCurrentSize         = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaCurrentSize'
        TxtMediaElapsed             = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaElapsed'
        LstMediaBuildLog            = Find-Ui -Root $MediaBuilderPage -Name 'LstMediaBuildLog'
    }

    if ($script:ctx.BtnMediaPickInstallImage) {
        $script:ctx.BtnMediaPickInstallImage.Add_Click({
            $path = Pick-MediaImageFile -Title (Get-UiString -Key 'MediaPickInstallTitle')
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                $script:ctx.SelectedInstallImagePath = $path
                Refresh-MediaBuilderUI
            }
        })
    }

    if ($script:ctx.BtnMediaClearInstallImage) {
        $script:ctx.BtnMediaClearInstallImage.Add_Click({
            $script:ctx.SelectedInstallImagePath = $null
            Refresh-MediaBuilderUI
        })
    }

    if ($script:ctx.BtnMediaPickBootImage) {
        $script:ctx.BtnMediaPickBootImage.Add_Click({
            $path = Pick-MediaImageFile -Title (Get-UiString -Key 'MediaPickBootTitle')
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                $script:ctx.SelectedBootImagePath = $path
                Refresh-MediaBuilderUI
            }
        })
    }

    if ($script:ctx.BtnMediaClearBootImage) {
        $script:ctx.BtnMediaClearBootImage.Add_Click({
            $script:ctx.SelectedBootImagePath = $null
            Refresh-MediaBuilderUI
        })
    }

    if ($script:ctx.BtnMediaBuildIso) {
        $script:ctx.BtnMediaBuildIso.Add_Click({ Start-MediaBuildIsoAsync })
    }

    if ($script:ctx.BtnMediaAddSourceImage) {
        $script:ctx.BtnMediaAddSourceImage.Add_Click({ Add-MediaComposeSourceImage })
    }

    if ($script:ctx.BtnMediaRemoveSourceImage) {
        $script:ctx.BtnMediaRemoveSourceImage.Add_Click({ Remove-MediaComposeSelectedItems })
    }

    if ($script:ctx.BtnMediaBuildInstallEsd) {
        $script:ctx.BtnMediaBuildInstallEsd.Add_Click({ Start-MediaBuildInstallEsdAsync })
    }

    if ($script:ctx.BtnMediaPickUsbSource) {
        $script:ctx.BtnMediaPickUsbSource.Add_Click({
            $path = Pick-MediaFolder -Description (Get-UiString -Key 'MediaPickUsbSourceDescription')
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                $script:ctx.SelectedUsbSourcePath = $path
                Set-MediaAppStateValueSafe -Key 'MediaUsbSourcePath' -Value $path
                Refresh-MediaBuilderUI
            }
        })
    }

    if ($script:ctx.BtnMediaPickUsbTarget) {
        $script:ctx.BtnMediaPickUsbTarget.Add_Click({
            $path = Pick-MediaFolder -Description (Get-UiString -Key 'MediaPickUsbTargetDescription')
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                $script:ctx.SelectedUsbTargetPath = $path
                Set-MediaAppStateValueSafe -Key 'MediaUsbTargetPath' -Value $path
                Refresh-MediaBuilderUI
            }
        })
    }

    if ($script:ctx.BtnMediaCheckUsb) {
        $script:ctx.BtnMediaCheckUsb.Add_Click({ Start-MediaUsbCheck })
    }

    if ($script:ctx.BtnMediaOpenUsbTarget) {
        $script:ctx.BtnMediaOpenUsbTarget.Add_Click({ Open-MediaUsbTarget })
    }

    if ($script:ctx.BtnMediaResetUsb) {
        $script:ctx.BtnMediaResetUsb.Add_Click({ Reset-MediaUsbSelection })
    }

    if ($script:ctx.BtnMediaCopyToUsb) {
        $script:ctx.BtnMediaCopyToUsb.Add_Click({ Start-MediaUsbCopyAsync })
    }

    if ($script:ctx.BtnMediaCancelBuild) {
        $script:ctx.BtnMediaCancelBuild.Add_Click({ Stop-MediaBuild })
    }

    if ($script:ctx.BtnMediaCancelBuildOverlay) {
        $script:ctx.BtnMediaCancelBuildOverlay.Add_Click({ Stop-MediaBuild })
    }

    if ($script:ctx.RbMediaBuildWim) {
        $script:ctx.RbMediaBuildWim.Add_Checked({ Refresh-MediaBuilderUI })
    }

    if ($script:ctx.RbMediaBuildEsd) {
        $script:ctx.RbMediaBuildEsd.Add_Checked({ Refresh-MediaBuilderUI })
    }

    if ($script:ctx.LstMediaComposeItems) {
        $script:ctx.LstMediaComposeItems.Add_SelectionChanged({ Refresh-MediaBuilderUI })
    }

    if ($MediaBuilderPage) {
        $MediaBuilderPage.Add_Loaded({ Refresh-MediaBuilderUI })
    }

    Refresh-MediaBuilderUI
    Set-MediaBuildStatus -Message (Get-UiString -Key 'MediaReady') -Detail (Get-UiString -Key 'StaticNoBuildStarted') -SizeBytes 0
}

Export-ModuleMember -Function Initialize-MediaBuilderController, Refresh-MediaBuilderUI
