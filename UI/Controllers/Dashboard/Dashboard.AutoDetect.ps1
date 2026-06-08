function Try-AutoDetectIso_Local {
    param([switch]$Quiet)

    try {
        # Nur fürs Logging
        $roots = @(Get-MountedIsoRoots)
        try { Write-Log -Level INFO -Message ("AutoDetect: CDRom Roots={0}" -f $roots.Count) -ToConsole } catch {}

        $hits = @(Find-MountedWindowsInstallMedia)
        try { Write-Log -Level INFO -Message ("AutoDetect: Kandidaten={0}" -f $hits.Count) -ToConsole } catch {}

        if ($hits.Count -lt 1) {
            if (-not $Quiet) { Show-UiInfo -Message "Kein gemountetes Windows-Installmedium gefunden." }
            return $false
        }

        $best = $hits | Sort-Object -Property Score -Descending | Select-Object -First 1

        try { Set-AppStateValue -Key "IsoRoot" -Value $best.Root } catch {}
        try { Set-AppStateValue -Key "IsoRootPath" -Value $best.Root } catch {}
        try { Set-AppStateValue -Key "IsoInstallImagePath" -Value $best.Install } catch {}
        try { Set-AppStateValue -Key "BootImagePath" -Value $best.Boot } catch {}

        try {
            Write-Log -Level INFO -Message ("AutoDetect gewählt: Root={0}; Boot={1}; Install={2}" -f $best.Root, $best.Boot, $best.Install) -ToConsole
        } catch {}

        return $true
    } catch {
        if (-not $Quiet) { Show-UiError -Message $_.Exception.Message }
        return $false
    }
}

function Start-DashboardAutoDetectAsync {
    if (-not $script:ctx) { return }

    try {
        if ($script:ctx.ContainsKey('AutoDetectStarted') -and $script:ctx['AutoDetectStarted']) { return }
        $script:ctx['AutoDetectStarted'] = $true
    } catch {
        return
    }

    if (-not (Get-Command Start-UiTask -ErrorAction SilentlyContinue)) {
        try { $null = Try-AutoDetectIso_Local -Quiet } catch {}
        return
    }

    $projectRoot = (Get-ProjectRoot).Replace("'", "''")
    $code = @"
Import-Module '$projectRoot\Core\Bootstrap.psm1' -Global -Force -DisableNameChecking
Set-ProjectRoot -Path '$projectRoot' | Out-Null
Import-Module (Resolve-ProjectPath 'Core\Logger.psm1' -MustExist) -Force -DisableNameChecking -Global
try { Initialize-Logger | Out-Null } catch {}
Import-Module (Resolve-ProjectPath 'Services\IsoDetectService.psm1' -MustExist) -Force -DisableNameChecking -Global

`$roots = @(Get-MountedIsoRoots)
`$hits = @(Find-MountedWindowsInstallMedia)
`$best = `$null
if (`$hits.Count -gt 0) {
    `$best = `$hits | Sort-Object -Property Score -Descending | Select-Object -First 1
}

[pscustomobject]@{
    RootCount = [int]`$roots.Count
    HitCount = [int]`$hits.Count
    Found = (`$null -ne `$best)
    Root = `$(if (`$best) { [string]`$best.Root } else { `$null })
    Boot = `$(if (`$best) { [string]`$best.Boot } else { `$null })
    Install = `$(if (`$best) { [string]`$best.Install } else { `$null })
}
"@

    Start-UiTask `
        -Label 'Dashboard:AutoDetectIso' `
        -Work ([scriptblock]::Create($code)) `
        -OnCompleted {
            param($Result)

            try {
                $items = @($Result | Where-Object { $null -ne $_ } | Select-Object -First 1)
                if ($items.Count -lt 1) { return }
                $item = $items[0]
                if (-not $item) { return }

                try { Write-Log -Level INFO -Message ("AutoDetect: CDRom Roots={0}" -f [int]$item.RootCount) -ToConsole } catch {}
                try { Write-Log -Level INFO -Message ("AutoDetect: Kandidaten={0}" -f [int]$item.HitCount) -ToConsole } catch {}

                if (-not [bool]$item.Found) { return }

                try { Set-AppStateValue -Key 'IsoRoot' -Value ([string]$item.Root) } catch {}
                try { Set-AppStateValue -Key 'IsoRootPath' -Value ([string]$item.Root) } catch {}
                try { Set-AppStateValue -Key 'IsoInstallImagePath' -Value ([string]$item.Install) } catch {}
                try { Set-AppStateValue -Key 'BootImagePath' -Value ([string]$item.Boot) } catch {}

                try {
                    Write-Log -Level INFO -Message ("AutoDetect gewählt: Root={0}; Boot={1}; Install={2}" -f $item.Root, $item.Boot, $item.Install) -ToConsole
                } catch {}

                Invoke-StateChangedSafe
                Refresh-DashboardUI
            } catch {}
        } `
        -OnError {
            param($ErrorObject)

            try {
                $message = if ($ErrorObject) { [string]$ErrorObject.Message } else { 'Unbekannter Fehler' }
                Write-Log -Level WARN -Message ("AutoDetect async fehlgeschlagen: {0}" -f $message) -ToConsole
            } catch {}
        }
}

function Start-DashboardDeferredAutoDetect {
    param([int]$DelayMs = 1800)

    if (-not $script:ctx) { return }
    $startAutoDetect = ${function:Start-DashboardAutoDetectAsync}

    try {
        if ($script:ctx.ContainsKey('AutoDetectStarted') -and $script:ctx['AutoDetectStarted']) { return }
    } catch {
        return
    }

    $page = $null
    try { $page = $script:ctx.DashboardPage } catch {}
    if (-not $page -or -not $page.Dispatcher) {
        Start-DashboardAutoDetectAsync
        return
    }

    try {
        if ($script:ctx.ContainsKey('AutoDetectTimer') -and $script:ctx['AutoDetectTimer']) {
            try { $script:ctx['AutoDetectTimer'].Stop() } catch {}
            $script:ctx['AutoDetectTimer'] = $null
        }

        $timer = New-Object System.Windows.Threading.DispatcherTimer(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
            $page.Dispatcher
        )
        $timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(250, $DelayMs))
        $timer.Add_Tick({
            try {
                if ($script:ctx -and $script:ctx.ContainsKey('AutoDetectTimer')) {
                    try { $script:ctx['AutoDetectTimer'].Stop() } catch {}
                    $script:ctx['AutoDetectTimer'] = $null
                }
                & $startAutoDetect
            } catch {
                try { Write-Log -Level WARN -Message ("Dashboard AutoDetect delayed start failed: {0}" -f $_.Exception.Message) } catch {}
            }
        }.GetNewClosure())

        $script:ctx['AutoDetectTimer'] = $timer
        $timer.Start()
    } catch {
        Start-DashboardAutoDetectAsync
    }
}
