function New-UpdatesDismInvokeParamsForMount {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$RetryCount = 0,
        [int]$RetryDelayMs = 1200,
        [string]$RetryPrefix = 'Updates',
        [string]$MountDir = ''
    )

    $params = @{
        Arguments    = $Arguments
        RetryCount   = $RetryCount
        RetryDelayMs = $RetryDelayMs
        RetryPrefix  = $RetryPrefix
    }

    try {
        $cmd = Get-Command Invoke-UpdatesDism -ErrorAction Stop
        if ($cmd.Parameters.ContainsKey('MountDir') -and -not [string]::IsNullOrWhiteSpace($MountDir)) {
            $params.MountDir = $MountDir
        }
    }
    catch {
    }

    return $params
}

function Get-MountedWimMeta {
    param(
        [Parameter(Mandatory)][string]$MountDir
    )

    $invokeParams = New-UpdatesDismInvokeParamsForMount `
        -Arguments @(
            '/English',
            '/Get-MountedWimInfo'
        ) `
        -RetryCount 1 `
        -RetryDelayMs 800 `
        -RetryPrefix 'Updates'

    $res = Invoke-UpdatesDism @invokeParams

    $blocks = Convert-DismTextToBlocks -Text $res.Text
    foreach ($b in $blocks) {
        $candidate = ''
        try { $candidate = [string]$b.'Mount Dir' } catch {}
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            try { $candidate = [string]$b.'Mount Directory' } catch {}
        }

        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            try {
                $resolvedA = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
            }
            catch {
                $resolvedA = $candidate
            }

            try {
                $resolvedB = (Resolve-Path -LiteralPath $MountDir -ErrorAction Stop).Path
            }
            catch {
                $resolvedB = $MountDir
            }

            if ($resolvedA -ieq $resolvedB) {
                $imageFile = ''
                $imageIndex = ''
                $mountMode = ''
                $mountStatus = ''

                try { $imageFile = [string]$b.'Image File' } catch {}
                try { $imageIndex = [string]$b.'Image Index' } catch {}
                try { $mountMode = [string]$b.'Mount Mode' } catch {}
                if ([string]::IsNullOrWhiteSpace($mountMode)) {
                    try { $mountMode = [string]$b.'Mounted Read/Write' } catch {}
                }
                if ([string]::IsNullOrWhiteSpace($mountMode)) {
                    try { $mountMode = [string]$b.'Read/Write' } catch {}
                }
                try { $mountStatus = [string]$b.'Mount Status' } catch {}

                $rw = '-'
                if ($mountMode -match '^(?i)(yes|true)$') {
                    $rw = 'Read/Write'
                }
                elseif ($mountMode -match '^(?i)(no|false)$') {
                    $rw = 'ReadOnly'
                }
                elseif ($mountMode -match 'read.?write') {
                    $rw = 'Read/Write'
                }
                elseif ($mountMode -match 'read.?only') {
                    $rw = 'ReadOnly'
                }

                return [pscustomobject]@{
                    MountDir    = $resolvedB
                    ImageFile   = $imageFile
                    ImageIndex  = $imageIndex
                    ReadWrite   = $rw
                    MountStatus = $mountStatus
                }
            }
        }
    }

    return [pscustomobject]@{
        MountDir    = $MountDir
        ImageFile   = ''
        ImageIndex  = ''
        ReadWrite   = '-'
        MountStatus = '-'
    }
}

function Get-CurrentEditionSafe {
    param(
        [Parameter(Mandatory)][string]$MountDir
    )

    try {
        $invokeParams = New-UpdatesDismInvokeParamsForMount `
            -Arguments @(
                '/English',
                "/Image:`"$MountDir`"",
                '/Get-CurrentEdition'
            ) `
            -RetryCount 10 `
            -RetryDelayMs 1200 `
            -RetryPrefix 'Updates' `
            -MountDir $MountDir

        $res = Invoke-UpdatesDism @invokeParams

        foreach ($line in ($res.Text -split "`r?`n")) {
            if ($line -match 'Current Edition\s*:\s*(.+)$') {
                return $matches[1].Trim()
            }
        }
    }
    catch {
        $message = [string]$_.Exception.Message
        $level = 'WARN'
        if ($message -match '(?i)(option is unknown|get-currentedition option is unknown|not recognized)') {
            $message = 'DISM /Get-CurrentEdition wird von diesem Image nicht unterstützt.'
            $level = 'INFO'
        }

        Write-UpdateLog -Level $level -Message ("Updates: Edition konnte nicht gelesen werden: {0}" -f $message)
    }

    return '-'
}

function Get-MountedImagePackagesInternal {
    param(
        [Parameter(Mandatory)][string]$MountDir
    )

    $invokeParams = New-UpdatesDismInvokeParamsForMount `
        -Arguments @(
            '/English',
            "/Image:`"$MountDir`"",
            '/Get-Packages'
        ) `
        -RetryCount 10 `
        -RetryDelayMs 1500 `
        -RetryPrefix 'Updates' `
        -MountDir $MountDir

    $res = Invoke-UpdatesDism @invokeParams

    Write-UpdateLog -Level DEBUG -Message ("Updates:Get-Packages raw length={0}" -f ([string]$res.Text).Length)
    $null = Save-UpdatesDebugText -Prefix 'GetPackages_raw' -Text ([string]$res.Text)

    $packages = ConvertTo-PackageObjectsFromDism -Text ([string]$res.Text)
    return @($packages)
}

function Get-BestInstalledPackageByKind {
    param(
        [AllowEmptyCollection()][object[]]$Packages = @(),
        [Parameter(Mandatory)][string]$Kind
    )

    if (-not $Packages -or @($Packages).Count -eq 0) {
        return $null
    }

    $filtered = @(
        $Packages | Where-Object {
            $_.Kind -eq $Kind -and (
                ([string]$_.State -match 'Installed') -or
                ([string]$_.State -match 'Superseded')
            )
        }
    )

    if ($filtered.Count -eq 0) { return $null }

    $withTime = foreach ($p in $filtered) {
        $dt = $null
        try { $dt = [datetime]::Parse([string]$p.InstallTime) } catch {}
        [pscustomobject]@{
            Package = $p
            SortKey = if ($dt) { $dt } else { [datetime]::MinValue }
        }
    }

    $best = @($withTime | Sort-Object SortKey -Descending | Select-Object -First 1)[0]
    if ($best) { return $best.Package }

    return $filtered[0]
}

function Get-InstalledKBs {
    param(
        [AllowEmptyCollection()][object[]]$Packages = @()
    )

    if (-not $Packages -or @($Packages).Count -eq 0) {
        return @()
    }

    $kbs = @(
        $Packages |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.KB) -and
            (
                ([string]$_.State -match 'Installed') -or
                ([string]$_.State -match 'Superseded')
            )
        } |
        ForEach-Object { ([string]$_.KB).ToUpperInvariant() } |
        Sort-Object -Unique
    )

    return @($kbs)
}

function Get-ProductFamilyFromImagePath {
    param([string]$ImageFile)

    $blob = ([string]$ImageFile).ToLowerInvariant()
    if ($blob -match 'win11' -or $blob -match 'windows.?11') { return 'Windows 11' }
    if ($blob -match 'win10' -or $blob -match 'windows.?10') { return 'Windows 10' }
    return 'Windows'
}

function Get-ArchitectureFromPackagesAndPath {
    param(
        [AllowEmptyCollection()][object[]]$Packages = @(),
        [string]$ImageFile
    )

    $identities = @()
    try {
        if ($Packages -and @($Packages).Count -gt 0) {
            $identities = @($Packages | Select-Object -ExpandProperty PackageIdentity -ErrorAction SilentlyContinue)
        }
    }
    catch {
        $identities = @()
    }

    $blob = (([string]$ImageFile) + ' ' + ($identities -join ' ')).ToLowerInvariant()

    if ($blob -match 'amd64' -or $blob -match '\bx64\b') { return 'x64' }
    if ($blob -match 'arm64') { return 'arm64' }
    if ($blob -match '\bx86\b') { return 'x86' }

    return 'x64'
}

function Get-BuildBranchFromPackages {
    param(
        [AllowEmptyCollection()][object[]]$Packages = @()
    )

    if (-not $Packages -or @($Packages).Count -eq 0) {
        return ''
    }

    foreach ($p in @($Packages)) {
        $id = ''
        try { $id = [string]$p.PackageIdentity } catch {}
        if ($id -match '10\.0\.(\d{4,5})') {
            return $matches[1]
        }
    }

    return ''
}

function Get-OfflineWindowsCurrentVersionInfo {
    param(
        [Parameter(Mandatory)][string]$MountDir
    )

    $softwareHive = Join-Path $MountDir 'Windows\System32\config\SOFTWARE'
    if (-not (Test-Path -LiteralPath $softwareHive)) {
        Write-UpdateLog -Level WARN -Message ("Updates: SOFTWARE-Hive nicht gefunden: {0}" -f $softwareHive)
        return $null
    }

    $keyName = 'WimOffline_' + [Guid]::NewGuid().ToString('N')
    $regKey  = "HKLM\$keyName"
    $loaded  = $false

    try {
        $loadOutput = & reg.exe load $regKey $softwareHive 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-UpdateLog -Level WARN -Message ("Updates: reg load fuer Offline-Hive fehlgeschlagen: {0}" -f $loadOutput.Trim())
            return $null
        }

        $loaded = $true

        $psPath = "Registry::HKEY_LOCAL_MACHINE\$keyName\Microsoft\Windows NT\CurrentVersion"
        $cv = Get-ItemProperty -LiteralPath $psPath -ErrorAction Stop

        $ubr = $null
        try {
            if ($null -ne $cv.UBR) {
                $ubr = [int]$cv.UBR
            }
        }
        catch {
            $ubr = $null
        }

        return [pscustomobject]@{
            ProductName        = [string]$cv.ProductName
            DisplayVersion     = [string]$cv.DisplayVersion
            ReleaseId          = [string]$cv.ReleaseId
            CurrentBuild       = [string]$cv.CurrentBuild
            CurrentBuildNumber = [string]$cv.CurrentBuildNumber
            BuildLabEx         = [string]$cv.BuildLabEx
            UBR                = $ubr
        }
    }
    catch {
        Write-UpdateLog -Level WARN -Message ("Updates: Offline-Registry konnte nicht gelesen werden: {0}" -f $_.Exception.Message)
        return $null
    }
    finally {
        if ($loaded) {
            $null = & reg.exe unload $regKey 2>$null
        }
    }
}

function Get-OfflineWindowsBuildBranch {
    param($Info)

    if ($null -eq $Info) { return '' }

    $candidates = @(
        [string]$Info.CurrentBuildNumber,
        [string]$Info.CurrentBuild,
        [string]$Info.BuildLabEx
    )

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        $m = [regex]::Match($candidate, '(?<build>\d{4,5})')
        if ($m.Success) {
            return [string]$m.Groups['build'].Value
        }
    }

    return ''
}

function Get-OfflineWindowsFullBuildVersion {
    param($Info)

    if ($null -eq $Info) { return '' }

    $build = Get-OfflineWindowsBuildBranch -Info $Info
    if ([string]::IsNullOrWhiteSpace($build)) {
        return ''
    }

    $ubr = $null
    try {
        if ($null -ne $Info.UBR) {
            $ubr = [int]$Info.UBR
        }
    }
    catch {
        $ubr = $null
    }

    if ($null -ne $ubr) {
        return ('{0}.{1}' -f $build, $ubr)
    }

    return $build
}

function Get-OfflineWindowsDisplayVersion {
    param($Info)

    if ($null -eq $Info) { return '' }

    $display = [string]$Info.DisplayVersion
    if ([string]::IsNullOrWhiteSpace($display)) {
        $display = [string]$Info.ReleaseId
    }

    if ([string]::IsNullOrWhiteSpace($display)) {
        return ''
    }

    $m = [regex]::Match($display.ToUpperInvariant(), '^\d{2}H[12]$')
    if ($m.Success) {
        return $m.Value
    }

    return ''
}

function Get-ProductFamilyFromOfflineInfoOrPath {
    param(
        $OfflineInfo,
        [string]$ImageFile
    )

    $fromPath = Get-ProductFamilyFromImagePath -ImageFile $ImageFile
    if ($fromPath -eq 'Windows 11' -or $fromPath -eq 'Windows 10') {
        return $fromPath
    }

    $productName = ''
    try { $productName = [string]$OfflineInfo.ProductName } catch {}

    if (-not [string]::IsNullOrWhiteSpace($productName)) {
        if ($productName -match 'Windows 11') { return 'Windows 11' }
        if ($productName -match 'Windows 10') { return 'Windows 10' }
    }

    return 'Windows'
}
