Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-UpdateIntegrationDismNeedsRemount {
    param(
        [int]$ExitCode,
        [AllowEmptyString()][string]$Text
    )

    $blob = [string]$Text

    if ($ExitCode -eq -1051655916) { return $true }
    if ($blob -match '0xc1510114') { return $true }
    if ($blob -match 'needs to be remounted') { return $true }
    if ($blob -match 'Remount the Wim') { return $true }

    return $false
}

function Invoke-UpdateIntegrationRemountImage {
    param(
        [Parameter(Mandatory)][string]$MountDir
    )

    $quotedMount = [char]34 + $MountDir + [char]34

    $remount = Invoke-Dism -Arguments @(
        '/Remount-Image',
        ('/MountDir:' + $quotedMount)
    ) -EnsureEnglish -TimeoutSec 1800

    if ($remount.ExitCode -ne 0) {
        $msg = [string]$remount.StdErr
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = [string]$remount.StdOut
        }
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = "DISM /Remount-Image fehlgeschlagen (ExitCode=$($remount.ExitCode))."
        }

        throw "$msg`nArgs=$($remount.Arguments)`nExitCode=$($remount.ExitCode)"
    }

    return $remount
}

function Get-UpdateIntegratableFiles {
    param(
        $DownloadResult
    )

    $list = New-Object System.Collections.Generic.List[object]

    if ($null -ne $DownloadResult) {
        foreach ($file in @($DownloadResult.Files)) {
            if ($null -eq $file) { continue }

            $path = [string]$file.LocalPath
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            if (-not (Test-Path -LiteralPath $path)) { continue }

            $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
            if ($ext -notin @('.msu', '.cab')) { continue }

            $list.Add([pscustomobject]@{
                LocalPath = $path
                FileName  = [System.IO.Path]::GetFileName($path)
                Extension = $ext
                Source    = 'DownloadResult'
            }) | Out-Null
        }

        $downloadDir = [string]$DownloadResult.DownloadDirectory
        if (-not [string]::IsNullOrWhiteSpace($downloadDir) -and (Test-Path -LiteralPath $downloadDir)) {
            $existingPaths = @{}
            foreach ($entry in @($list.ToArray())) {
                $existingPaths[[string]$entry.LocalPath] = $true
            }

            $scan = Get-ChildItem -LiteralPath $downloadDir -File -ErrorAction SilentlyContinue | Where-Object {
                ([System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant()) -in @('.msu', '.cab')
            }

            foreach ($file in @($scan)) {
                if ($existingPaths.ContainsKey([string]$file.FullName)) { continue }

                $list.Add([pscustomobject]@{
                    LocalPath = [string]$file.FullName
                    FileName  = [string]$file.Name
                    Extension = [System.IO.Path]::GetExtension($file.FullName).ToLowerInvariant()
                    Source    = 'DirectoryScan'
                }) | Out-Null
            }
        }
    }

    $ordered = @(
        $list.ToArray() | Sort-Object -Property @(
            @{ Expression = {
                if ([string]$_.Extension -eq '.cab') { return 0 }
                if ([string]$_.Extension -eq '.msu') { return 1 }
                return 9
            }; Descending = $false },
            @{ Expression = { [string]$_.FileName }; Descending = $false }
        )
    )

    return @($ordered)
}

function Invoke-UpdateAddPackageToMount {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$PackagePath
    )

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw "Paketdatei nicht gefunden: $PackagePath"
    }

    $quotedMount = [char]34 + $MountDir + [char]34
    $quotedPackage = [char]34 + $PackagePath + [char]34

    $args = @(
        ('/Image:' + $quotedMount),
        '/Add-Package',
        ('/PackagePath:' + $quotedPackage)
    )

    $res = Invoke-Dism -Arguments $args -EnsureEnglish -TimeoutSec 7200
    $combined = (([string]$res.StdOut) + "`r`n" + ([string]$res.StdErr)).Trim()

    if ($res.ExitCode -ne 0 -and (Test-UpdateIntegrationDismNeedsRemount -ExitCode $res.ExitCode -Text $combined)) {
        Write-UpdateLog -Level WARN -Message ("Updates: Add-Package meldet Remount für {0}. Remount und Retry." -f $MountDir)
        $null = Invoke-UpdateIntegrationRemountImage -MountDir $MountDir
        Start-Sleep -Milliseconds 800

        $res = Invoke-Dism -Arguments $args -EnsureEnglish -TimeoutSec 7200
        $combined = (([string]$res.StdOut) + "`r`n" + ([string]$res.StdErr)).Trim()
    }

    if ($res.ExitCode -ne 0) {
        $msg = [string]$res.StdErr
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = [string]$res.StdOut
        }
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = "DISM /Add-Package fehlgeschlagen (ExitCode=$($res.ExitCode))."
        }

        throw "$msg`nArgs=$($res.Arguments)`nExitCode=$($res.ExitCode)"
    }

    return [pscustomobject]@{
        PackagePath = $PackagePath
        FileName    = [System.IO.Path]::GetFileName($PackagePath)
        ExitCode    = $res.ExitCode
        DurationMs  = $res.DurationMs
        Arguments   = $res.Arguments
        OutputText  = $combined
    }
}

function Normalize-UpdateIntegrationPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch {
        return $Path.TrimEnd('\')
    }
}

function Test-UpdateMountWritable {
    param($MountItem)

    if ($null -eq $MountItem) { return $false }

    try {
        if ($MountItem.PSObject.Properties.Match('RegistryOnly').Count -gt 0 -and [bool]$MountItem.RegistryOnly) {
            return $false
        }
    } catch {}

    try {
        if ($MountItem.PSObject.Properties.Match('Status').Count -gt 0) {
            $status = [string]$MountItem.Status
            if (-not [string]::IsNullOrWhiteSpace($status)) {
                $s = $status.ToLowerInvariant()
                if ($s -notmatch '^(ok|mounted)$') { return $false }
            }
        }
    } catch {}

    try {
        if ($MountItem.PSObject.Properties.Match('CanCommit').Count -gt 0 -and -not [bool]$MountItem.CanCommit) {
            return $false
        }
    } catch {}

    $rw = ''
    try {
        if ($MountItem.PSObject.Properties.Match('ReadWrite').Count -gt 0) {
            $rw = [string]$MountItem.ReadWrite
        }
    } catch {}

    if ([string]::IsNullOrWhiteSpace($rw)) { return $false }

    $x = $rw.ToLowerInvariant()
    if ($x -match 'readonly') { return $false }
    if ($x -match 'read\s*only') { return $false }
    if ($x -match '^no$') { return $false }
    if ($x -match '^false$') { return $false }
    if ($x -match 'read/write') { return $true }
    if ($x -match 'readwrite') { return $true }
    if ($x -match '^yes$') { return $true }
    if ($x -match '^true$') { return $true }
    if ($x -match '\brw\b') { return $true }

    return $false
}

function Resolve-UpdateIntegrationMountTargets {
    param(
        [Parameter(Mandatory)][string[]]$MountDirs
    )

    $mounted = @()
    if (Get-Command Get-MountedWimList -ErrorAction SilentlyContinue) {
        try { $mounted = @(Get-MountedWimList) } catch { $mounted = @() }
    }

    $byMount = @{}
    foreach ($mount in @($mounted)) {
        $key = Normalize-UpdateIntegrationPath -Path ([string]$mount.MountDir)
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $byMount.ContainsKey($key)) {
            $byMount[$key] = $mount
        }
    }

    $seen = @{}
    $targets = New-Object System.Collections.Generic.List[object]

    foreach ($rawDir in @($MountDirs)) {
        if ([string]::IsNullOrWhiteSpace($rawDir)) { continue }

        $key = Normalize-UpdateIntegrationPath -Path $rawDir
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($seen.ContainsKey($key.ToLowerInvariant())) { continue }
        $seen[$key.ToLowerInvariant()] = $true

        $mountItem = if ($byMount.ContainsKey($key)) { $byMount[$key] } else { $null }
        $display = $rawDir
        $status = ''
        $readWrite = ''
        $health = ''
        $canCommit = $null
        $registryOnly = $null
        try {
            if ($mountItem) {
                $imageFile = [System.IO.Path]::GetFileName([string]$mountItem.ImageFile)
                $imageIndex = [string]$mountItem.ImageIndex
                if (-not [string]::IsNullOrWhiteSpace($imageFile)) {
                    $display = if ([string]::IsNullOrWhiteSpace($imageIndex)) { $imageFile } else { "{0} Index {1}" -f $imageFile, $imageIndex }
                }
                if ($mountItem.PSObject.Properties.Match('Status').Count -gt 0) { $status = [string]$mountItem.Status }
                if ($mountItem.PSObject.Properties.Match('ReadWrite').Count -gt 0) { $readWrite = [string]$mountItem.ReadWrite }
                if ($mountItem.PSObject.Properties.Match('Health').Count -gt 0) { $health = [string]$mountItem.Health }
                if ($mountItem.PSObject.Properties.Match('CanCommit').Count -gt 0) { $canCommit = [bool]$mountItem.CanCommit }
                if ($mountItem.PSObject.Properties.Match('RegistryOnly').Count -gt 0) { $registryOnly = [bool]$mountItem.RegistryOnly }
            }
        } catch {}

        $skipReason = ''
        if (-not (Test-Path -LiteralPath $rawDir -PathType Container)) {
            $skipReason = 'MountDir nicht gefunden'
        } elseif (-not $mountItem) {
            $skipReason = 'Mount ist nicht in der DISM-Mountliste'
        } elseif (-not (Test-UpdateMountWritable -MountItem $mountItem)) {
            $skipReason = 'Mount ist nicht Read/Write oder nicht gesund'
        }

        $targets.Add([pscustomobject]@{
            MountDir   = [string]$rawDir
            Display    = [string]$display
            MountItem  = $mountItem
            CanProcess = [string]::IsNullOrWhiteSpace($skipReason)
            SkipReason = $skipReason
            Status     = $status
            ReadWrite  = $readWrite
            Health     = $health
            CanCommit  = $canCommit
            RegistryOnly = $registryOnly
        }) | Out-Null
    }

    return @($targets.ToArray())
}

function Test-CatalogUpdateIntegrationTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$MountDirs,
        [string]$UpdateId = '',
        [string]$Title = '',
        [string]$KB = ''
    )

    $targets = @(Resolve-UpdateIntegrationMountTargets -MountDirs $MountDirs)
    $ready = @($targets | Where-Object { [bool]$_.CanProcess })
    $skipped = @($targets | Where-Object { -not [bool]$_.CanProcess })

    $dismProcesses = @(
        Get-Process -Name dism,dismhost -ErrorAction SilentlyContinue |
        Select-Object Id, ProcessName, StartTime, CPU
    )

    $updateText = ''
    if (-not [string]::IsNullOrWhiteSpace($KB)) {
        $updateText = $KB
    } elseif (-not [string]::IsNullOrWhiteSpace($Title)) {
        $updateText = $Title
    } elseif (-not [string]::IsNullOrWhiteSpace($UpdateId)) {
        $updateText = $UpdateId
    } else {
        $updateText = 'Kein Update ausgewählt'
    }

    return [pscustomobject]@{
        MountCount       = $targets.Count
        ReadyCount       = $ready.Count
        SkippedCount     = $skipped.Count
        HasDismProcesses = (@($dismProcesses).Count -gt 0)
        DismProcesses    = @($dismProcesses)
        UpdateId         = $UpdateId
        Title            = $Title
        KB               = $KB
        UpdateText       = $updateText
        Targets          = @($targets)
    }
}

function Invoke-CatalogUpdateIntegration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$MountDirs,
        [Parameter(Mandatory)][string]$UpdateId,
        [string]$Title = '',
        [string]$KB = ''
    )

    if (-not (Get-Command Download-CatalogUpdate -ErrorAction SilentlyContinue)) {
        throw 'Download-CatalogUpdate ist nicht verfügbar.'
    }

    $targetList = @(Resolve-UpdateIntegrationMountTargets -MountDirs $MountDirs)
    if ($targetList.Count -le 0) {
        throw 'Keine Mount-Ziele für die Integration gefunden.'
    }

    $readyTargets = @($targetList | Where-Object { [bool]$_.CanProcess })
    if ($readyTargets.Count -le 0) {
        $mountResults = @(
            foreach ($target in $targetList) {
                [pscustomobject]@{
                    MountDir        = [string]$target.MountDir
                    Display         = [string]$target.Display
                    Status          = 'Skipped'
                    Message         = [string]$target.SkipReason
                    IntegratedCount = 0
                    IntegratedFiles = @()
                }
            }
        )

        return [pscustomobject]@{
            MountDir          = if ($MountDirs.Count -eq 1) { [string]$MountDirs[0] } else { '' }
            MountCount        = $targetList.Count
            UpdateId          = $UpdateId
            Title             = $Title
            KB                = $KB
            DownloadDirectory = ''
            FileCount         = 0
            DownloadedCount   = 0
            SkippedCount      = 0
            IntegratableCount = 0
            IntegratedCount   = 0
            FailedCount       = 0
            SkippedMountCount = @($mountResults).Count
            MountResults      = @($mountResults)
        }
    }

    Write-UpdateLog -Level INFO -Message ("Updates: Integration startet | Mounts={0} | UpdateId={1} | KB={2}" -f $targetList.Count, $UpdateId, $KB)

    $downloadResult = Download-CatalogUpdate -UpdateId $UpdateId -Title $Title -KB $KB
    $filesToIntegrate = @(Get-UpdateIntegratableFiles -DownloadResult $downloadResult)

    if ($filesToIntegrate.Count -le 0) {
        throw 'Es wurde keine integrierbare .msu- oder .cab-Datei gefunden.'
    }

    $mountResults = New-Object System.Collections.Generic.List[object]

    foreach ($target in $targetList) {
        if (-not [bool]$target.CanProcess) {
            $mountResults.Add([pscustomobject]@{
                MountDir        = [string]$target.MountDir
                Display         = [string]$target.Display
                Status          = 'Skipped'
                Message         = [string]$target.SkipReason
                IntegratedCount = 0
                IntegratedFiles = @()
            }) | Out-Null
            continue
        }

        $integrated = New-Object System.Collections.Generic.List[object]
        $failedMessage = ''

        try {
            foreach ($file in $filesToIntegrate) {
                Write-UpdateLog -Level INFO -Message ("Updates: Add-Package -> Mount={0} Package={1}" -f [string]$target.MountDir, [string]$file.LocalPath)
                $result = Invoke-UpdateAddPackageToMount -MountDir ([string]$target.MountDir) -PackagePath ([string]$file.LocalPath)
                $integrated.Add($result) | Out-Null
            }
        } catch {
            $failedMessage = $_.Exception.Message
        }

        if ([string]::IsNullOrWhiteSpace($failedMessage)) {
            $mountResults.Add([pscustomobject]@{
                MountDir        = [string]$target.MountDir
                Display         = [string]$target.Display
                Status          = 'Integrated'
                Message         = 'OK'
                IntegratedCount = @($integrated.ToArray()).Count
                IntegratedFiles = @($integrated.ToArray())
            }) | Out-Null
        } else {
            $mountResults.Add([pscustomobject]@{
                MountDir        = [string]$target.MountDir
                Display         = [string]$target.Display
                Status          = 'Failed'
                Message         = $failedMessage
                IntegratedCount = @($integrated.ToArray()).Count
                IntegratedFiles = @($integrated.ToArray())
            }) | Out-Null
        }
    }

    $results = @($mountResults.ToArray())

    return [pscustomobject]@{
        MountDir          = if ($MountDirs.Count -eq 1) { [string]$MountDirs[0] } else { '' }
        MountCount        = $targetList.Count
        UpdateId          = $UpdateId
        Title             = $Title
        KB                = $KB
        DownloadDirectory = [string]$downloadResult.DownloadDirectory
        FileCount         = [int]$downloadResult.FileCount
        DownloadedCount   = [int]$downloadResult.DownloadedCount
        SkippedCount      = [int]$downloadResult.SkippedCount
        IntegratableCount = $filesToIntegrate.Count
        IntegratedCount   = @($results | Where-Object { [string]$_.Status -eq 'Integrated' }).Count
        FailedCount       = @($results | Where-Object { [string]$_.Status -eq 'Failed' }).Count
        SkippedMountCount = @($results | Where-Object { [string]$_.Status -eq 'Skipped' }).Count
        MountResults      = $results
    }
}

function New-LocalUpdateDownloadResult {
    param(
        [string]$PackagePath,
        [string]$PackageTitle = '',
        [string]$KB = ''
    )

    if ([string]::IsNullOrWhiteSpace($PackagePath)) {
        throw 'Keine Paketdatei angegeben.'
    }

    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "Paketdatei nicht gefunden: $PackagePath"
    }

    $ext = [System.IO.Path]::GetExtension($PackagePath).ToLowerInvariant()
    if ($ext -notin @('.msu', '.cab')) {
        throw "Nur .msu- und .cab-Dateien können als lokale Updates integriert werden: $PackagePath"
    }

    $item = Get-Item -LiteralPath $PackagePath -ErrorAction Stop
    $fileName = [System.IO.Path]::GetFileName($PackagePath)

    if ([string]::IsNullOrWhiteSpace($PackageTitle)) {
        $PackageTitle = $fileName
    }

    return [pscustomobject]@{
        UpdateId           = 'LOCAL'
        Title              = $PackageTitle
        KB                 = $KB
        DownloadDirectory  = ''
        FileCount          = 1
        DownloadedCount    = 0
        SkippedCount       = 1
        CandidateCount     = 1
        NonSelectedCount   = 0
        SelectionStrategy  = 'LocalFile'
        Files              = @(
            [pscustomobject]@{
                Url       = ''
                FileName  = $fileName
                LocalPath = [string]$item.FullName
                Status    = 'LocalFile'
            }
        )
        SkippedUrls        = @()
    }
}

function Invoke-LocalUpdateIntegration {
    param(
        [string[]]$MountDirs,
        [string]$PackagePath,
        [string]$Title = '',
        [string]$KB = ''
    )

    $targetList = @(Resolve-UpdateIntegrationMountTargets -MountDirs $MountDirs)
    if ($targetList.Count -le 0) {
        throw 'Keine Mount-Ziele für die Integration gefunden.'
    }

    $downloadResult = New-LocalUpdateDownloadResult -PackagePath $PackagePath -PackageTitle $Title -KB $KB
    $filesToIntegrate = @(Get-UpdateIntegratableFiles -DownloadResult $downloadResult)
    if ($filesToIntegrate.Count -le 0) {
        throw 'Es wurde keine integrierbare lokale .msu- oder .cab-Datei gefunden.'
    }

    Write-UpdateLog -Level INFO -Message ("Updates: Lokale Integration startet | Mounts={0} | Paket={1} | KB={2}" -f $targetList.Count, $PackagePath, $KB)

    $mountResults = New-Object System.Collections.Generic.List[object]

    foreach ($target in $targetList) {
        if (-not [bool]$target.CanProcess) {
            $mountResults.Add([pscustomobject]@{
                MountDir        = [string]$target.MountDir
                Display         = [string]$target.Display
                Status          = 'Skipped'
                Message         = [string]$target.SkipReason
                IntegratedCount = 0
                IntegratedFiles = @()
            }) | Out-Null
            continue
        }

        $integrated = New-Object System.Collections.Generic.List[object]
        $failedMessage = ''

        try {
            foreach ($file in $filesToIntegrate) {
                Write-UpdateLog -Level INFO -Message ("Updates: Add-Package lokal -> Mount={0} Package={1}" -f [string]$target.MountDir, [string]$file.LocalPath)
                $result = Invoke-UpdateAddPackageToMount -MountDir ([string]$target.MountDir) -PackagePath ([string]$file.LocalPath)
                $integrated.Add($result) | Out-Null
            }
        } catch {
            $failedMessage = $_.Exception.Message
        }

        if ([string]::IsNullOrWhiteSpace($failedMessage)) {
            $mountResults.Add([pscustomobject]@{
                MountDir        = [string]$target.MountDir
                Display         = [string]$target.Display
                Status          = 'Integrated'
                Message         = 'OK'
                IntegratedCount = @($integrated.ToArray()).Count
                IntegratedFiles = @($integrated.ToArray())
            }) | Out-Null
        } else {
            $mountResults.Add([pscustomobject]@{
                MountDir        = [string]$target.MountDir
                Display         = [string]$target.Display
                Status          = 'Failed'
                Message         = $failedMessage
                IntegratedCount = @($integrated.ToArray()).Count
                IntegratedFiles = @($integrated.ToArray())
            }) | Out-Null
        }
    }

    $results = @($mountResults.ToArray())

    return [pscustomobject]@{
        MountDir          = if ($MountDirs.Count -eq 1) { [string]$MountDirs[0] } else { '' }
        MountCount        = $targetList.Count
        UpdateId          = 'LOCAL'
        Title             = $Title
        KB                = $KB
        DownloadDirectory = [string]$downloadResult.DownloadDirectory
        FileCount         = [int]$downloadResult.FileCount
        DownloadedCount   = [int]$downloadResult.DownloadedCount
        SkippedCount      = [int]$downloadResult.SkippedCount
        IntegratableCount = $filesToIntegrate.Count
        IntegratedCount   = @($results | Where-Object { [string]$_.Status -eq 'Integrated' }).Count
        FailedCount       = @($results | Where-Object { [string]$_.Status -eq 'Failed' }).Count
        SkippedMountCount = @($results | Where-Object { [string]$_.Status -eq 'Skipped' }).Count
        MountResults      = $results
    }
}
