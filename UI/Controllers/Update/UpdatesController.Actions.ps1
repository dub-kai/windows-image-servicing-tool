function Get-UiExactCatalogQueries {
    $queries = New-Object System.Collections.Generic.List[string]

    if (-not $script:ctx -or -not $script:ctx.Page) {
        return @()
    }

    $txt = Find-Ui -Root $script:ctx.Page -Name 'TxtUpdatesFilterText'
    if (-not $txt) {
        return @()
    }

    $raw = [string]$txt.Text
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $text = $raw.Trim()

    $kbMatches = [regex]::Matches($text, 'KB\d{6,8}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $kbMatches) {
        $kb = [string]$m.Value.ToUpperInvariant()
        if (-not $queries.Contains($kb)) {
            $queries.Add($kb) | Out-Null
        }
    }

    $verMatches = [regex]::Matches($text, '\b\d+\.\d+\.\d+\.\d+\b')
    foreach ($m in $verMatches) {
        $ver = [string]$m.Value
        if (-not $queries.Contains($ver)) {
            $queries.Add($ver) | Out-Null
        }
    }

    return @($queries.ToArray())
}

function Invoke-AutoCatalogSearchIfEnabled {
    if ($script:isBusy) {
        try { Write-Log -Level INFO -Message 'AutoCatalog: skipped (busy).' } catch {}
        return
    }

    $autoEnabled = Get-AutoCatalogEnabled
    if (-not $autoEnabled) {
        try { Write-Log -Level INFO -Message 'AutoCatalog: skipped (checkbox disabled).' } catch {}
        return
    }

    if ($null -eq $script:updateContext) {
        try { Write-Log -Level INFO -Message 'AutoCatalog: skipped (kein UpdateContext).' } catch {}
        return
    }

    $catalogSupported = $true
    try {
        if ($script:updateContext.PSObject.Properties.Match('CatalogSearchSupported').Count -gt 0) {
            $catalogSupported = [bool]$script:updateContext.CatalogSearchSupported
        }
    } catch { $catalogSupported = $true }

    if (-not $catalogSupported) {
        $reason = 'nicht geeignet'
        try {
            if ($script:updateContext.PSObject.Properties.Match('CatalogSkipReason').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$script:updateContext.CatalogSkipReason)) {
                $reason = [string]$script:updateContext.CatalogSkipReason
            }
        } catch {}
        try { Write-Log -Level INFO -Message ('AutoCatalog: skipped ({0}).' -f $reason) } catch {}
        return
    }

    $queries = @($script:updateContext.CatalogQueries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($queries.Count -le 0) {
        try { Write-Log -Level INFO -Message 'AutoCatalog: skipped (keine Queries).' } catch {}
        return
    }

    if (@($script:catalogAllResults).Count -gt 0) {
        try { Write-Log -Level INFO -Message 'AutoCatalog: skipped (Treffer bereits vorhanden).' } catch {}
        return
    }

    try {
        Write-Log -Level INFO -Message ('AutoCatalog: start (Queries={0}).' -f $queries.Count)
    } catch {}

    Invoke-CatalogSearchUi
}

function Test-UpdatesRefreshAllowed {
    param(
        [string]$Reason = $null,
        [int]$MinIntervalMs = 1200
    )

    $now = [DateTime]::UtcNow
    if ($script:lastRefreshTriggerAtUtc) {
        $elapsedMs = [int]($now - $script:lastRefreshTriggerAtUtc).TotalMilliseconds
        if ($elapsedMs -lt $MinIntervalMs) {
            try {
                Write-Log -Level INFO -Message ('Updates: Refresh skipped (debounced) | Reason={0} | LastReason={1} | ElapsedMs={2}' -f `
                    $(if ($Reason) { $Reason } else { '-' }),
                    $(if ($script:lastRefreshReason) { $script:lastRefreshReason } else { '-' }),
                    $elapsedMs)
            } catch {}
            return $false
        }
    }

    $script:lastRefreshTriggerAtUtc = $now
    $script:lastRefreshReason = $Reason
    return $true
}

function Invoke-UpdatesPageActivated {
    param(
        [string]$Reason = $null
    )

    if ($null -eq $script:ctx -or $null -eq $script:ctx.Page) { return }
    if ($script:isBusy) { return }

    $page = $script:ctx.Page
    try {
        if (-not [bool]$page.IsVisible) { return }
    } catch {}

    if (-not (Test-UpdatesRefreshAllowed -Reason $Reason)) { return }

    try {
        Write-Log -Level INFO -Message ('Updates: Activation refresh | Reason={0}' -f $(if ($Reason) { $Reason } else { '-' }))
    } catch {}

    Refresh-UpdatesUI
}

function Start-UpdatesMountRefresh {
    $preferredMountDir = $script:selectedMountDir
    $page = $null
    if ($script:ctx) {
        $page = $script:ctx.Page
    }

    Set-UpdatesBusy -Busy $true -Message 'Mounts werden gelesen...'

    $preamble = Get-UpdatesWorkerPreamble
    $preferredPs = ConvertTo-UpdatesPsLiteral -Value $preferredMountDir

    $workCode = @"
$preamble

`$preferredMountDir = $preferredPs
`$mountedRaw = @(Get-MountedWimList)

`$mounted = @(
    `$mountedRaw | Where-Object {
        `$null -ne `$_ -and
        -not [string]::IsNullOrWhiteSpace([string]`$_.MountDir) -and
        (Test-Path -LiteralPath ([string]`$_.MountDir))
    }
)

`$selectedMountDir = `$null
if (-not [string]::IsNullOrWhiteSpace(`$preferredMountDir)) {
    `$selectedMountDir = @(
        `$mounted |
        Where-Object { ([string]`$_.MountDir) -ieq `$preferredMountDir } |
        Select-Object -First 1
    )
    if (`$selectedMountDir) {
        `$selectedMountDir = [string]`$selectedMountDir.MountDir
    }
}

if ([string]::IsNullOrWhiteSpace(`$selectedMountDir) -and @(`$mounted).Count -gt 0) {
    `$selectedMountDir = [string]`$mounted[0].MountDir
}

[pscustomobject]@{
    Kind             = 'Mounts'
    Mounts           = @(`$mounted)
    SelectedMountDir = `$selectedMountDir
}
"@

    $cmdSetBusy             = Get-Command 'Set-UpdatesBusy' -ErrorAction SilentlyContinue
    $cmdClearUi             = Get-Command 'Clear-UpdatesUi' -ErrorAction SilentlyContinue
    $cmdSetStatus           = Get-Command 'Set-UpdatesStatusText' -ErrorAction SilentlyContinue
    $cmdUpdateMountSelector = Get-Command 'Update-MountSelectorUi' -ErrorAction SilentlyContinue
    $cmdGetSelectedMountDir = Get-Command 'Get-SelectedMountDir' -ErrorAction SilentlyContinue
    $cmdSetUiText           = Get-Command 'Set-UiText' -ErrorAction SilentlyContinue
    $cmdLoadMountContext    = Get-Command 'Start-SelectedMountContextLoad' -ErrorAction SilentlyContinue

    Start-UiTask `
        -Label 'Updates:RefreshMounts' `
        -Work (New-UpdatesWorkerScript -Code $workCode) `
        -OnCompleted ({
            param($result)

            if ($cmdSetBusy) {
                & $cmdSetBusy -Busy $false
            }

            $item = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
            $mounts = if ($item) { @($item.Mounts) } else { @() }
            $selected = if ($item) { [string]$item.SelectedMountDir } else { $null }
            $mountCount = @($mounts).Count

            if ($cmdUpdateMountSelector) {
                & $cmdUpdateMountSelector -Mounts @($mounts) -PreferredMountDir $selected
            }
            else {
                throw 'Update-MountSelectorUi ist nicht verfuegbar.'
            }

            $selectedMountDir = $null
            if ($cmdGetSelectedMountDir) {
                $selectedMountDir = & $cmdGetSelectedMountDir
            }

            if ([string]::IsNullOrWhiteSpace($selectedMountDir)) {
                $selectedMountDir = $selected
            }
            if ([string]::IsNullOrWhiteSpace($selectedMountDir) -and $mountCount -gt 0) {
                $selectedMountDir = [string]$mounts[0].MountDir
            }

            $script:selectedMountDir = $selectedMountDir

            try {
                Write-Log -Level INFO -Message ('Updates: RefreshMounts -> Count={0}; Preferred={1}; SelectedWorker={2}; SelectedFinal={3}' -f `
                    $mountCount,
                    $(if ($preferredMountDir) { $preferredMountDir } else { '-' }),
                    $(if ($selected) { $selected } else { '-' }),
                    $(if ($selectedMountDir) { $selectedMountDir } else { '-' }))
            } catch {}

            if ($mountCount -le 0) {
                if ($cmdClearUi) {
                    & $cmdClearUi
                }
                if ($cmdSetStatus) {
                    & $cmdSetStatus -Message 'Kein gemountetes Image gefunden.'
                }
                if ($page -and $cmdSetUiText) {
                    & $cmdSetUiText -Root $page -Name 'TxtUpdatesFooterHint' -Value 'Aktuell ist kein Mount aktiv. Bitte zuerst ein Image mounten.'
                }
                return
            }

            if ([string]::IsNullOrWhiteSpace($selectedMountDir)) {
                if ($cmdClearUi) {
                    & $cmdClearUi
                }
                if ($cmdSetStatus) {
                    & $cmdSetStatus -Message 'Es konnte kein Mount ausgewaehlt werden.'
                }
                if ($page -and $cmdSetUiText) {
                    & $cmdSetUiText -Root $page -Name 'TxtUpdatesFooterHint' -Value 'Mounts wurden gefunden, aber es konnte keine Auswahl bestimmt werden.'
                }
                return
            }

            if ($cmdLoadMountContext) {
                & $cmdLoadMountContext -MountDir $selectedMountDir -TriggerCatalogIfEnabled
            }
            else {
                throw 'Start-SelectedMountContextLoad ist nicht verfuegbar.'
            }
        }.GetNewClosure()) `
        -OnError ({
            param($ex)

            if ($cmdSetBusy) {
                & $cmdSetBusy -Busy $false
            }

            if ($cmdUpdateMountSelector) {
                & $cmdUpdateMountSelector -Mounts @() -PreferredMountDir $null
            }

            if ($cmdClearUi) {
                & $cmdClearUi
            }
            if ($cmdSetStatus) {
                & $cmdSetStatus -Message 'Fehler beim Lesen der Mount-Liste.'
            }

            Show-UiError -Message $ex.Message -Title 'Updates'
        }.GetNewClosure())
}

function Start-SelectedMountContextLoad {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [switch]$TriggerCatalogIfEnabled
    )

    if ([string]::IsNullOrWhiteSpace($MountDir)) { return }

    $currentMountDir = $null
    try { $currentMountDir = [string]$script:updateContext.MountDir } catch {}
    if ((-not $TriggerCatalogIfEnabled) -and -not [string]::IsNullOrWhiteSpace($currentMountDir) -and ($currentMountDir -ieq $MountDir)) {
        try {
            Write-Log -Level INFO -Message ('Updates: Kontext-Reload uebersprungen (Mount unveraendert): {0}' -f $MountDir)
        } catch {}
        return
    }

    $script:selectedMountDir = $MountDir
    $shouldTriggerCatalog = $TriggerCatalogIfEnabled.IsPresent

    $cmdSetBusy      = Get-Command 'Set-UpdatesBusy' -ErrorAction SilentlyContinue
    $cmdClearUi      = Get-Command 'Clear-UpdatesUi' -ErrorAction SilentlyContinue
    $cmdSetStatus    = Get-Command 'Set-UpdatesStatusText' -ErrorAction SilentlyContinue
    $cmdShowContext  = Get-Command 'Show-UpdateContext' -ErrorAction SilentlyContinue
    $cmdAutoCatalog  = Get-Command 'Invoke-AutoCatalogSearchIfEnabled' -ErrorAction SilentlyContinue
    $cmdDriverReload = Get-Command 'Request-DriversReload' -ErrorAction SilentlyContinue

    try {
        Set-AppStateValue -Key "IsImageServicingBusy" -Value $true
    } catch {}

    Set-UpdatesBusy -Busy $true -Message 'Mount-Kontext wird geladen...'

    $preamble = Get-UpdatesWorkerPreamble
    $mountPs = ConvertTo-UpdatesPsLiteral -Value $MountDir

    $workCode = @"
$preamble

`$mountDir = $mountPs
if ([string]::IsNullOrWhiteSpace(`$mountDir)) {
    throw 'Kein MountDir fuer den Kontext-Ladevorgang uebergeben.'
}

`$ctx = Get-MountedImageUpdateContext -MountDir `$mountDir

[pscustomobject]@{
    Kind     = 'Context'
    MountDir = `$mountDir
    Context  = `$ctx
}
"@

    Start-UiTask `
        -Label 'Updates:LoadSelectedMountContext' `
        -Work (New-UpdatesWorkerScript -Code $workCode) `
        -OnCompleted ({
            param($result)

            try {
                Set-AppStateValue -Key "IsImageServicingBusy" -Value $false
            } catch {}

            if ($cmdSetBusy) {
                & $cmdSetBusy -Busy $false
            }

            $item = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
            if ($null -eq $item -or $null -eq $item.Context) {
                if ($cmdClearUi) {
                    & $cmdClearUi
                }
                if ($cmdSetStatus) {
                    & $cmdSetStatus -Message 'Der Mount-Kontext konnte nicht geladen werden.'
                }
                if ($cmdDriverReload) {
                    try { & $cmdDriverReload -Reason "UpdatesContextEmpty" } catch {}
                }
                return
            }

            try {
                Write-Log -Level INFO -Message ('Updates: Ausgewaehlter Mount: {0}' -f [string]$item.MountDir)
            } catch {}

            if ($cmdShowContext) {
                & $cmdShowContext -Context $item.Context
            }

            if ($shouldTriggerCatalog -and $cmdAutoCatalog) {
                & $cmdAutoCatalog
            }

            if ($cmdDriverReload) {
                try { & $cmdDriverReload -Reason "UpdatesContextLoaded" } catch {}
            }
        }.GetNewClosure()) `
        -OnError ({
            param($ex)

            try {
                Set-AppStateValue -Key "IsImageServicingBusy" -Value $false
            } catch {}

            if ($cmdSetBusy) {
                & $cmdSetBusy -Busy $false
            }
            if ($cmdClearUi) {
                & $cmdClearUi
            }
            if ($cmdSetStatus) {
                & $cmdSetStatus -Message 'Fehler beim Lesen des Mount-Kontexts.'
            }

            if ($cmdDriverReload) {
                try { & $cmdDriverReload -Reason "UpdatesContextError" } catch {}
            }

            Show-UiError -Message $ex.Message -Title 'Updates'
        }.GetNewClosure())
}

function Refresh-UpdatesUI {
    if ($null -eq $script:ctx -or $null -eq $script:ctx.Page) { return }
    if ($script:isBusy) { return }

    Start-UpdatesMountRefresh
}

function Invoke-CatalogSearchUi {
    if ($script:isBusy) { return }

    if ($null -eq $script:updateContext) {
        Show-UiInfo -Message 'Es ist aktuell kein gemountetes Image verfuegbar.' -Title 'Updates'
        return
    }

    $catalogSupported = $true
    try {
        if ($script:updateContext.PSObject.Properties.Match('CatalogSearchSupported').Count -gt 0) {
            $catalogSupported = [bool]$script:updateContext.CatalogSearchSupported
        }
    } catch { $catalogSupported = $true }

    if (-not $catalogSupported) {
        $reason = 'Dieses Image ist fuer die automatische Catalog-Suche nicht geeignet.'
        try {
            if ($script:updateContext.PSObject.Properties.Match('CatalogSkipReason').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$script:updateContext.CatalogSkipReason)) {
                $reason = [string]$script:updateContext.CatalogSkipReason
            }
        } catch {}
        Show-UiInfo -Message $reason -Title 'Updates'
        return
    }

    $contextQueries = @($script:updateContext.CatalogQueries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $exactQueries = @(Get-UiExactCatalogQueries)

    $queries = New-Object System.Collections.Generic.List[string]
    foreach ($q in $exactQueries) {
        if (-not $queries.Contains([string]$q)) {
            $queries.Add([string]$q) | Out-Null
        }
    }
    foreach ($q in $contextQueries) {
        if (-not $queries.Contains([string]$q)) {
            $queries.Add([string]$q) | Out-Null
        }
    }

    $queryArray = @($queries.ToArray())
    if ($queryArray.Count -eq 0) {
        Show-UiInfo -Message 'Fuer das aktuelle Image konnten keine Catalog-Queries gebildet werden.' -Title 'Updates'
        return
    }

    $installedKBs = @($script:updateContext.InstalledKBs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $currentBuildVersion = ''
    try { $currentBuildVersion = [string]$script:updateContext.OsBuildVersion } catch {}
    if ([string]::IsNullOrWhiteSpace($currentBuildVersion) -or $currentBuildVersion -eq '-') {
        try { $currentBuildVersion = [string]$script:updateContext.CurrentBuildVersion } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($currentBuildVersion) -or $currentBuildVersion -eq '-') {
        try { $currentBuildVersion = [string]$script:updateContext.CurrentLCUVersion } catch {}
    }

    try {
        Write-Log -Level INFO -Message ('Catalog Search Start: Queries={0}; InstalledKBs={1}; Product={2}; Arch={3}; Build={4}; CurrentBuildVersion={5}' -f `
            $queryArray.Count,
            $installedKBs.Count,
            [string]$script:updateContext.ProductFamily,
            [string]$script:updateContext.Architecture,
            [string]$script:updateContext.BuildBranch,
            $(if ($currentBuildVersion) { $currentBuildVersion } else { '-' }))

        Write-Log -Level INFO -Message ('Catalog Search FirstQuery: {0}' -f [string]$queryArray[0])

        if ($exactQueries.Count -gt 0) {
            Write-Log -Level INFO -Message ('Catalog Search ExactQueries: {0}' -f ($exactQueries -join ', '))
        }
    } catch {}

    Set-UpdatesBusy -Busy $true -Message 'Microsoft Update Catalog wird durchsucht...'

    $queriesB64        = ConvertTo-UpdatesBase64Json -Value @($queryArray)
    $installedB64      = ConvertTo-UpdatesBase64Json -Value @($installedKBs)
    $productPs         = ConvertTo-UpdatesPsLiteral -Value $script:updateContext.ProductFamily
    $archPs            = ConvertTo-UpdatesPsLiteral -Value $script:updateContext.Architecture
    $buildPs           = ConvertTo-UpdatesPsLiteral -Value $script:updateContext.BuildBranch
    $buildVersionPs    = ConvertTo-UpdatesPsLiteral -Value $currentBuildVersion
    $lcuPs             = ConvertTo-UpdatesPsLiteral -Value $script:updateContext.CurrentLCUVersion
    $ssuPs             = ConvertTo-UpdatesPsLiteral -Value $script:updateContext.CurrentSSUVersion
    $dotnetPs          = ConvertTo-UpdatesPsLiteral -Value $script:updateContext.CurrentDotNetVersion

    $preamble = Get-UpdatesWorkerPreamble
    $workCode = @"
$preamble

function ConvertFrom-WorkerBase64Json {
    param([Parameter(Mandatory)][string]`$Base64)

    `$json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$Base64))
    if ([string]::IsNullOrWhiteSpace(`$json) -or `$json -eq 'null') {
        return `$null
    }

    return (`$json | ConvertFrom-Json)
}

`$queries = @([string[]](ConvertFrom-WorkerBase64Json -Base64 '$queriesB64'))
`$installed = @([string[]](ConvertFrom-WorkerBase64Json -Base64 '$installedB64'))

try {
    Write-Log -Level INFO -Message ('Catalog Worker Input: Queries={0}; InstalledKBs={1}' -f @(`$queries).Count, @(`$installed).Count)
    if (@(`$queries).Count -gt 0) {
        Write-Log -Level INFO -Message ('Catalog Worker FirstQuery: {0}' -f [string]`$queries[0])
    }
} catch {}

if (@(`$queries).Count -le 0) {
    throw 'Catalog-Suche: Queryliste leer nach Worker-Deserialisierung.'
}

`$params = @{
    Queries              = @(`$queries)
    InstalledKBs         = @(`$installed)
    ProductFamily        = $productPs
    Architecture         = $archPs
    BuildBranch          = $buildPs
    CurrentBuildVersion  = $buildVersionPs
    CurrentLcuVersion    = $lcuPs
    CurrentSsuVersion    = $ssuPs
    CurrentDotNetVersion = $dotnetPs
}

`$result = Search-WindowsUpdateCatalogBatch @params
`$result
"@

    Start-UiTask `
        -Label 'Updates:CatalogSearch' `
        -TimeoutSec 180 `
        -Work (New-UpdatesWorkerScript -Code $workCode) `
        -OnCompleted {
            param($result)

            Set-UpdatesBusy -Busy $false

            $item = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
            if ($null -eq $item) {
                Reset-CatalogState
                Apply-CatalogView
                Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesFooterHint' -Value 'Catalog-Suche abgeschlossen, aber ohne Treffer. Bei Insider-/Release-Preview-Updates kannst du die .msu/.cab manuell laden und über "MSU/CAB wählen" hinzufügen.'
                return
            }

            $script:catalogAllResults = @($item.AllResults)
            $script:catalogWorkResults = @($item.WorkResults)
            $script:catalogRecommendations = $item.Recommendations

            try {
                Write-Log -Level INFO -Message ('Catalog State set: All={0}; Work={1}' -f `
                    @($script:catalogAllResults).Count,
                    @($script:catalogWorkResults).Count)
            } catch {}

            Apply-CatalogView

            $footer = if (@($script:catalogAllResults).Count -gt 0) {
                'Catalog-Suche abgeschlossen. Treffer koennen jetzt gefiltert und ausgewaehlt werden. Tipp: "Alle Treffer" zeigt auch Preview- und nicht empfohlene Pakete.'
            } else {
                'Catalog-Suche abgeschlossen, aber ohne passende Treffer. Nutze "Alle Treffer" fuer Diagnose oder fuege eine heruntergeladene .msu/.cab ueber "MSU/CAB wählen" hinzu.'
            }

            Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesFooterHint' -Value $footer
        } `
        -OnError {
            param($ex)

            Set-UpdatesBusy -Busy $false
            Reset-CatalogState
            Apply-CatalogView
            Show-UiError -Message $ex.Message -Title 'Catalog-Suche'
        }
}

function Invoke-CatalogDownloadUi {
    $item = Get-SelectedCatalogItem
    if (-not $item) {
        Show-UiInfo -Message 'Bitte zuerst einen Catalog-Treffer auswaehlen.' -Title 'Catalog'
        return
    }

    $updateId = [string]$item.UpdateId
    $title    = [string]$item.Title
    $kb       = [string]$item.KB

    if ([string]::IsNullOrWhiteSpace($updateId)) {
        Show-UiInfo -Message 'Der ausgewaehlte Eintrag hat keine UpdateId und kann nicht direkt heruntergeladen werden.' -Title 'Download'
        return
    }

    Set-UpdatesBusy -Busy $true -Message 'Catalog-Update wird heruntergeladen...'

    $preamble   = Get-UpdatesWorkerPreamble
    $updateIdPs = ConvertTo-UpdatesPsLiteral -Value $updateId
    $titlePs    = ConvertTo-UpdatesPsLiteral -Value $title
    $kbPs       = ConvertTo-UpdatesPsLiteral -Value $kb

    $workCode = @"
$preamble

`$result = Download-CatalogUpdate -UpdateId $updateIdPs -Title $titlePs -KB $kbPs
`$result
"@

    Start-UiTask `
        -Label ('Updates:CatalogDownload:' + $updateId) `
        -TimeoutSec 3600 `
        -Work (New-UpdatesWorkerScript -Code $workCode) `
        -OnCompleted {
            param($result)

            Set-UpdatesBusy -Busy $false

            $downloadResult = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
            if ($null -eq $downloadResult) {
                Show-UiInfo -Message 'Der Download lieferte kein Ergebnisobjekt zurueck.' -Title 'Download'
                return
            }

            $message = "Download abgeschlossen.`n`nDateien: {0}`nNeu: {1}`nBereits vorhanden: {2}`nOrdner: {3}" -f `
                [int]$downloadResult.FileCount,
                [int]$downloadResult.DownloadedCount,
                [int]$downloadResult.SkippedCount,
                [string]$downloadResult.DownloadDirectory

            try {
                Write-Log -Level INFO -Message ("Updates: Download UI abgeschlossen | Dateien={0} | Neu={1} | Vorhanden={2} | Ordner={3}" -f `
                    [int]$downloadResult.FileCount,
                    [int]$downloadResult.DownloadedCount,
                    [int]$downloadResult.SkippedCount,
                    [string]$downloadResult.DownloadDirectory)
            } catch {}

            Show-UiInfo -Message $message -Title 'Download'
        } `
        -OnError {
            param($ex)

            Set-UpdatesBusy -Busy $false
            Show-UiError -Message $ex.Message -Title 'Download'
        }
}

function Invoke-CatalogIntegrateUi {
    if ($script:isBusy) { return }

    $item = Get-SelectedCatalogItem
    if (-not $item) {
        Show-UiInfo -Message 'Bitte zuerst einen Catalog-Treffer auswaehlen.' -Title 'Catalog'
        return
    }

    $mountDir = Get-SelectedMountDir
    if ([string]::IsNullOrWhiteSpace($mountDir) -and $script:updateContext) {
        try { $mountDir = [string]$script:updateContext.MountDir } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($mountDir)) {
        Show-UiInfo -Message 'Es ist aktuell kein gueltiger Mount ausgewaehlt.' -Title 'Integration'
        return
    }

    $mountMode = ''
    if ($script:updateContext) {
        try { $mountMode = [string]$script:updateContext.ReadWrite } catch {}
    }

    if ($mountMode -match 'ReadOnly' -and $mountMode -notmatch 'No|False|0') {
        Show-UiInfo -Message 'Der ausgewaehlte Mount ist schreibgeschuetzt. Bitte ein Read/Write-Mount verwenden.' -Title 'Integration'
        return
    }

    $updateId = [string]$item.UpdateId
    $title    = [string]$item.Title
    $kb       = [string]$item.KB

    if ([string]::IsNullOrWhiteSpace($updateId)) {
        Show-UiInfo -Message 'Der ausgewaehlte Eintrag hat keine UpdateId und kann nicht integriert werden.' -Title 'Integration'
        return
    }

    Set-UpdatesBusy -Busy $true -Message 'Update wird heruntergeladen und in den Mount integriert...'

    $preamble   = Get-UpdatesWorkerPreamble
    $mountPs    = ConvertTo-UpdatesPsLiteral -Value $mountDir
    $updateIdPs = ConvertTo-UpdatesPsLiteral -Value $updateId
    $titlePs    = ConvertTo-UpdatesPsLiteral -Value $title
    $kbPs       = ConvertTo-UpdatesPsLiteral -Value $kb

    $workCode = @"
$preamble

function Test-WorkerDismNeedsRemount {
    param(
        [int]`$ExitCode,
        [AllowEmptyString()][string]`$Text
    )

    `$blob = [string]`$Text

    if (`$ExitCode -eq -1051655916) { return `$true }
    if (`$blob -match '0xc1510114') { return `$true }
    if (`$blob -match 'needs to be remounted') { return `$true }
    if (`$blob -match 'Remount the Wim') { return `$true }

    return `$false
}

function Invoke-WorkerRemountImage {
    param(
        [Parameter(Mandatory)][string]`$MountDir
    )

    `$quotedMount = [char]34 + `$MountDir + [char]34

    `$remount = Invoke-Dism -Arguments @(
        '/Remount-Image',
        ('/MountDir:' + `$quotedMount)
    ) -EnsureEnglish -TimeoutSec 1800

    if (`$remount.ExitCode -ne 0) {
        `$msg = [string]`$remount.StdErr
        if ([string]::IsNullOrWhiteSpace(`$msg)) {
            `$msg = [string]`$remount.StdOut
        }
        if ([string]::IsNullOrWhiteSpace(`$msg)) {
            `$msg = "DISM /Remount-Image fehlgeschlagen (ExitCode=`$(`$remount.ExitCode))."
        }

        throw "`$msg`nArgs=`$(`$remount.Arguments)`nExitCode=`$(`$remount.ExitCode)"
    }

    return `$remount
}

function Get-WorkerIntegratableFiles {
    param(
        `$DownloadResult
    )

    `$list = New-Object System.Collections.Generic.List[object]

    if (`$null -ne `$DownloadResult) {
        foreach (`$file in @(`$DownloadResult.Files)) {
            if (`$null -eq `$file) { continue }

            `$path = [string]`$file.LocalPath
            if ([string]::IsNullOrWhiteSpace(`$path)) { continue }
            if (-not (Test-Path -LiteralPath `$path)) { continue }

            `$ext = [System.IO.Path]::GetExtension(`$path).ToLowerInvariant()
            if (`$ext -notin @('.msu', '.cab')) { continue }

            `$list.Add([pscustomobject]@{
                LocalPath = `$path
                FileName  = [System.IO.Path]::GetFileName(`$path)
                Extension = `$ext
                Source    = 'DownloadResult'
            }) | Out-Null
        }

        `$downloadDir = [string]`$DownloadResult.DownloadDirectory
        if (-not [string]::IsNullOrWhiteSpace(`$downloadDir) -and (Test-Path -LiteralPath `$downloadDir)) {
            `$existingPaths = @{}
            foreach (`$entry in @(`$list.ToArray())) {
                `$existingPaths[[string]`$entry.LocalPath] = `$true
            }

            `$scan = Get-ChildItem -LiteralPath `$downloadDir -File -ErrorAction SilentlyContinue | Where-Object {
                ([System.IO.Path]::GetExtension(`$_.FullName).ToLowerInvariant()) -in @('.msu', '.cab')
            }

            foreach (`$file in @(`$scan)) {
                if (`$existingPaths.ContainsKey([string]`$file.FullName)) { continue }

                `$list.Add([pscustomobject]@{
                    LocalPath = [string]`$file.FullName
                    FileName  = [string]`$file.Name
                    Extension = [System.IO.Path]::GetExtension(`$file.FullName).ToLowerInvariant()
                    Source    = 'DirectoryScan'
                }) | Out-Null
            }
        }
    }

    `$ordered = @(
        `$list.ToArray() | Sort-Object -Property @(
            @{ Expression = {
                if ([string]`$_.Extension -eq '.cab') { return 0 }
                if ([string]`$_.Extension -eq '.msu') { return 1 }
                return 9
            }; Descending = `$false },
            @{ Expression = { [string]`$_.FileName }; Descending = `$false }
        )
    )

    return @(`$ordered)
}

function Invoke-WorkerAddPackageToMount {
    param(
        [Parameter(Mandatory)][string]`$MountDir,
        [Parameter(Mandatory)][string]`$PackagePath
    )

    if (-not (Test-Path -LiteralPath `$PackagePath)) {
        throw "Paketdatei nicht gefunden: `$PackagePath"
    }

    `$quotedMount   = [char]34 + `$MountDir + [char]34
    `$quotedPackage = [char]34 + `$PackagePath + [char]34

    `$args = @(
        ('/Image:' + `$quotedMount),
        '/Add-Package',
        ('/PackagePath:' + `$quotedPackage)
    )

    `$res = Invoke-Dism -Arguments `$args -EnsureEnglish -TimeoutSec 7200
    `$combined = (([string]`$res.StdOut) + "`r`n" + ([string]`$res.StdErr)).Trim()

    if (`$res.ExitCode -ne 0 -and (Test-WorkerDismNeedsRemount -ExitCode `$res.ExitCode -Text `$combined)) {
        Write-Log -Level WARN -Message ("Updates: Add-Package meldet Remount fuer {0}. Remount und Retry." -f `$MountDir)
        `$null = Invoke-WorkerRemountImage -MountDir `$MountDir
        Start-Sleep -Milliseconds 800

        `$res = Invoke-Dism -Arguments `$args -EnsureEnglish -TimeoutSec 7200
        `$combined = (([string]`$res.StdOut) + "`r`n" + ([string]`$res.StdErr)).Trim()
    }

    if (`$res.ExitCode -ne 0) {
        `$msg = [string]`$res.StdErr
        if ([string]::IsNullOrWhiteSpace(`$msg)) {
            `$msg = [string]`$res.StdOut
        }
        if ([string]::IsNullOrWhiteSpace(`$msg)) {
            `$msg = "DISM /Add-Package fehlgeschlagen (ExitCode=`$(`$res.ExitCode))."
        }

        throw "`$msg`nArgs=`$(`$res.Arguments)`nExitCode=`$(`$res.ExitCode)"
    }

    [pscustomobject]@{
        PackagePath = `$PackagePath
        FileName    = [System.IO.Path]::GetFileName(`$PackagePath)
        ExitCode    = `$res.ExitCode
        DurationMs  = `$res.DurationMs
        Arguments   = `$res.Arguments
        OutputText  = `$combined
    }
}

`$mountDir = $mountPs
`$updateId = $updateIdPs
`$title    = $titlePs
`$kb       = $kbPs

if ([string]::IsNullOrWhiteSpace(`$mountDir)) {
    throw 'Integration: MountDir ist leer.'
}

if (-not (Test-Path -LiteralPath `$mountDir)) {
    throw "Integration: MountDir nicht gefunden: `$mountDir"
}

Write-Log -Level INFO -Message ("Updates: Integration startet | Mount={0} | UpdateId={1} | KB={2}" -f `$mountDir, `$updateId, `$kb)

`$downloadResult = Download-CatalogUpdate -UpdateId `$updateId -Title `$title -KB `$kb
`$filesToIntegrate = @(Get-WorkerIntegratableFiles -DownloadResult `$downloadResult)

if (`$filesToIntegrate.Count -le 0) {
    throw 'Es wurde keine integrierbare .msu- oder .cab-Datei gefunden.'
}

`$integrated = New-Object System.Collections.Generic.List[object]

foreach (`$file in `$filesToIntegrate) {
    Write-Log -Level INFO -Message ("Updates: Add-Package -> {0}" -f [string]`$file.LocalPath)
    `$result = Invoke-WorkerAddPackageToMount -MountDir `$mountDir -PackagePath ([string]`$file.LocalPath)
    `$integrated.Add(`$result) | Out-Null
}

[pscustomobject]@{
    MountDir           = `$mountDir
    UpdateId           = `$updateId
    Title              = `$title
    KB                 = `$kb
    DownloadDirectory  = [string]`$downloadResult.DownloadDirectory
    FileCount          = [int]`$downloadResult.FileCount
    DownloadedCount    = [int]`$downloadResult.DownloadedCount
    SkippedCount       = [int]`$downloadResult.SkippedCount
    IntegratableCount  = @(`$filesToIntegrate).Count
    IntegratedCount    = @(`$integrated.ToArray()).Count
    IntegratedFiles    = @(`$integrated.ToArray())
}
"@

    Start-UiTask `
        -Label ('Updates:CatalogIntegrate:' + $updateId) `
        -TimeoutSec 14400 `
        -Work (New-UpdatesWorkerScript -Code $workCode) `
        -OnCompleted {
            param($result)

            Set-UpdatesBusy -Busy $false

            $integrationResult = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
            if ($null -eq $integrationResult) {
                Show-UiInfo -Message 'Die Integration lieferte kein Ergebnisobjekt zurueck.' -Title 'Integration'
                return
            }

            try {
                Write-Log -Level INFO -Message ("Updates: Integration abgeschlossen | Mount={0} | Downloaded={1} | Integrated={2}" -f `
                    [string]$integrationResult.MountDir,
                    [int]$integrationResult.DownloadedCount,
                    [int]$integrationResult.IntegratedCount)
            } catch {}

            $fileNames = @()
            foreach ($f in @($integrationResult.IntegratedFiles)) {
                if ($null -eq $f) { continue }
                $name = ''
                try { $name = [string]$f.FileName } catch {}
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $fileNames += $name
                }
            }

            $details = if ($fileNames.Count -gt 0) {
                ($fileNames -join "`n")
            }
            else {
                '-'
            }

            $message = "Integration abgeschlossen.`n`nMount: {0}`nIntegrierte Dateien: {1}`nDownload-Ordner: {2}`n`nDateien:`n{3}" -f `
                [string]$integrationResult.MountDir,
                [int]$integrationResult.IntegratedCount,
                [string]$integrationResult.DownloadDirectory,
                $details

            Reset-CatalogState
            Apply-CatalogView
            Set-UpdatesStatusText -Message 'Integration abgeschlossen. Mount-Kontext wird neu geladen...'
            if ($script:ctx -and $script:ctx.Page) {
                Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesFooterHint' -Value 'Integration abgeschlossen. Mount- und Catalog-Daten werden aktualisiert...'
            }

            Show-UiInfo -Message $message -Title 'Integration'

            Start-SelectedMountContextLoad -MountDir ([string]$integrationResult.MountDir) -TriggerCatalogIfEnabled
        } `
        -OnError {
            param($ex)

            Set-UpdatesBusy -Busy $false
            Show-UiError -Message $ex.Message -Title 'Integration'
        }
}

function Get-UpdateBatchMountDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($mount in @($script:mountItems)) {
        if ($null -eq $mount) { continue }

        $dir = ''
        try { $dir = [string]$mount.MountDir } catch { $dir = '' }
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }

        $key = $dir.ToLowerInvariant().TrimEnd('\')
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $dirs.Add($dir) | Out-Null
    }

    return @($dirs.ToArray())
}

function Format-IntegrationBatchResultLine {
    param($Result)

    if ($null -eq $Result) { return '-' }

    $status = [string]$Result.Status
    $display = [string]$Result.Display
    if ([string]::IsNullOrWhiteSpace($display)) { $display = [string]$Result.MountDir }
    if ([string]::IsNullOrWhiteSpace($display)) { $display = '-' }

    switch ($status) {
        'Integrated' {
            return ("OK: {0} ({1} Datei(en))" -f $display, [int]$Result.IntegratedCount)
        }
        'Skipped' {
            return ("Übersprungen: {0} ({1})" -f $display, [string]$Result.Message)
        }
        'Failed' {
            return ("Fehler: {0} ({1})" -f $display, [string]$Result.Message)
        }
        default {
            return ("{0}: {1}" -f $status, $display)
        }
    }
}

function Format-IntegrationPreflightResultLine {
    param($Result)

    if ($null -eq $Result) { return '-' }

    $display = [string]$Result.Display
    if ([string]::IsNullOrWhiteSpace($display)) { $display = [string]$Result.MountDir }
    if ([string]::IsNullOrWhiteSpace($display)) { $display = '-' }

    if ([bool]$Result.CanProcess) {
        return ("OK: {0} | {1} | {2}" -f $display, [string]$Result.ReadWrite, [string]$Result.Health)
    }

    return ("Übersprungen: {0} | {1}" -f $display, [string]$Result.SkipReason)
}

function Show-IntegrationPreflightResult {
    param(
        [Parameter(Mandatory)]$PreflightResult,
        [switch]$FromBatchRun
    )

    $targets = @($PreflightResult.Targets)
    $lines = @($targets | ForEach-Object { Format-IntegrationPreflightResultLine -Result $_ })
    $dismLines = @()
    foreach ($proc in @($PreflightResult.DismProcesses)) {
        if ($null -eq $proc) { continue }
        $dismLines += ("{0} PID {1} CPU {2}" -f [string]$proc.ProcessName, [int]$proc.Id, [string]$proc.CPU)
    }

    $dismText = if ($dismLines.Count -gt 0) {
        $dismLines -join "`n"
    } else {
        'Keine laufenden DISM-Prozesse gefunden.'
    }

    $message = "Batch-Prüfung abgeschlossen.`n`nUpdate: {0}`nMounts: {1}`nBereit: {2}`nÜbersprungen: {3}`nDISM aktiv: {4}`n`nZiele:`n{5}`n`nDISM-Prozesse:`n{6}" -f `
        [string]$PreflightResult.UpdateText,
        [int]$PreflightResult.MountCount,
        [int]$PreflightResult.ReadyCount,
        [int]$PreflightResult.SkippedCount,
        $(if ([bool]$PreflightResult.HasDismProcesses) { 'Ja' } else { 'Nein' }),
        ($lines -join "`n"),
        $dismText

    if ($script:ctx -and $script:ctx.Page) {
        $plan = "Batch-Prüfung: {0}/{1} Mounts bereit, {2} übersprungen. Update: {3}" -f `
            [int]$PreflightResult.ReadyCount,
            [int]$PreflightResult.MountCount,
            [int]$PreflightResult.SkippedCount,
            [string]$PreflightResult.UpdateText
        Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesBatchPlan' -Value $plan
        Set-UpdatesStatusText -Message $plan
    }

    $title = if ($FromBatchRun) { 'Batch Preflight' } else { 'Batch prüfen' }
    Show-UiInfo -Message $message -Title $title
}

function Invoke-CatalogPreflightUi {
    if ($script:isBusy) { return }

    $item = Get-SelectedCatalogItem
    if (-not $item) {
        Show-UiInfo -Message 'Bitte zuerst einen Catalog-Treffer auswählen.' -Title 'Catalog'
        return
    }

    $mountDirs = @(Get-UpdateBatchMountDirs)
    if ($mountDirs.Count -lt 1) {
        Show-UiInfo -Message 'Es sind aktuell keine Mounts in der Updates-Liste vorhanden.' -Title 'Batch prüfen'
        return
    }

    $updateId = [string]$item.UpdateId
    $title = [string]$item.Title
    $kb = [string]$item.KB

    Set-UpdatesBusy -Busy $true -Message 'Batch-Prüfung läuft...'

    $preamble = Get-UpdatesWorkerPreamble
    $mountDirsB64 = ConvertTo-UpdatesBase64Json -Value @($mountDirs)
    $updateIdPs = ConvertTo-UpdatesPsLiteral -Value $updateId
    $titlePs = ConvertTo-UpdatesPsLiteral -Value $title
    $kbPs = ConvertTo-UpdatesPsLiteral -Value $kb

    $workCode = @"
$preamble

function ConvertFrom-WorkerBase64Json {
    param([Parameter(Mandatory)][string]`$Base64)

    `$json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$Base64))
    if ([string]::IsNullOrWhiteSpace(`$json) -or `$json -eq 'null') {
        return @()
    }

    return @(`$json | ConvertFrom-Json)
}

`$mountDirs = @([string[]](ConvertFrom-WorkerBase64Json -Base64 '$mountDirsB64'))
Test-CatalogUpdateIntegrationTargets -MountDirs `$mountDirs -UpdateId $updateIdPs -Title $titlePs -KB $kbPs
"@

    Start-UiTask `
        -Label ('Updates:CatalogPreflight:' + $updateId) `
        -TimeoutSec 300 `
        -Work (New-UpdatesWorkerScript -Code $workCode) `
        -OnCompleted {
            param($result)

            Set-UpdatesBusy -Busy $false
            $preflight = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
            if ($null -eq $preflight) {
                Show-UiInfo -Message 'Die Batch-Prüfung lieferte kein Ergebnisobjekt zurück.' -Title 'Batch prüfen'
                return
            }

            Show-IntegrationPreflightResult -PreflightResult $preflight
        } `
        -OnError {
            param($ex)

            Set-UpdatesBusy -Busy $false
            Show-UiError -Message $ex.Message -Title 'Batch prüfen'
        }
}

function Invoke-CatalogIntegrateAllUi {
    if ($script:isBusy) { return }

    $item = Get-SelectedCatalogItem
    if (-not $item) {
        Show-UiInfo -Message 'Bitte zuerst einen Catalog-Treffer auswählen.' -Title 'Catalog'
        return
    }

    $mountDirs = @(Get-UpdateBatchMountDirs)
    if ($mountDirs.Count -lt 1) {
        Show-UiInfo -Message 'Es sind aktuell keine Mounts in der Updates-Liste vorhanden.' -Title 'Integration'
        return
    }

    $updateId = [string]$item.UpdateId
    $title    = [string]$item.Title
    $kb       = [string]$item.KB

    if ([string]::IsNullOrWhiteSpace($updateId)) {
        Show-UiInfo -Message 'Der ausgewählte Eintrag hat keine UpdateId und kann nicht integriert werden.' -Title 'Integration'
        return
    }

    try {
        Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesBatchPlan' -Value ("Batch läuft: Update wird auf {0} Mount(s) nacheinander angewendet. Ungeeignete Mounts werden übersprungen." -f $mountDirs.Count)
    } catch {}

    Set-UpdatesBusy -Busy $true -Message ("Update wird in {0} Mount(s) integriert..." -f $mountDirs.Count)

    $preamble = Get-UpdatesWorkerPreamble
    $mountDirsB64 = ConvertTo-UpdatesBase64Json -Value @($mountDirs)
    $updateIdPs = ConvertTo-UpdatesPsLiteral -Value $updateId
    $titlePs = ConvertTo-UpdatesPsLiteral -Value $title
    $kbPs = ConvertTo-UpdatesPsLiteral -Value $kb

    $workCode = @"
$preamble

function ConvertFrom-WorkerBase64Json {
    param([Parameter(Mandatory)][string]`$Base64)

    `$json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$Base64))
    if ([string]::IsNullOrWhiteSpace(`$json) -or `$json -eq 'null') {
        return @()
    }

    return @(`$json | ConvertFrom-Json)
}

`$mountDirs = @([string[]](ConvertFrom-WorkerBase64Json -Base64 '$mountDirsB64'))
`$result = Invoke-CatalogUpdateIntegration -MountDirs `$mountDirs -UpdateId $updateIdPs -Title $titlePs -KB $kbPs
`$result
"@

    Start-UiTask `
        -Label ('Updates:CatalogIntegrateAll:' + $updateId) `
        -TimeoutSec 28800 `
        -Work (New-UpdatesWorkerScript -Code $workCode) `
        -OnCompleted {
            param($result)

            Set-UpdatesBusy -Busy $false

            $integrationResult = if (@($result).Count -gt 0) { @($result)[0] } else { $null }
            if ($null -eq $integrationResult) {
                Show-UiInfo -Message 'Die Batch-Integration lieferte kein Ergebnisobjekt zurück.' -Title 'Integration'
                return
            }

            $mountResults = @($integrationResult.MountResults)
            $lines = @($mountResults | ForEach-Object { Format-IntegrationBatchResultLine -Result $_ })

            $message = "Batch-Integration abgeschlossen.`n`nMounts: {0}`nOK: {1}`nÜbersprungen: {2}`nFehler: {3}`nDownload-Ordner: {4}`n`nDetails:`n{5}" -f `
                [int]$integrationResult.MountCount,
                [int]$integrationResult.IntegratedCount,
                [int]$integrationResult.SkippedMountCount,
                [int]$integrationResult.FailedCount,
                [string]$integrationResult.DownloadDirectory,
                ($lines -join "`n")

            try {
                Write-Log -Level INFO -Message ("Updates: Batch-Integration abgeschlossen | Mounts={0} | OK={1} | Skip={2} | Fehler={3}" -f `
                    [int]$integrationResult.MountCount,
                    [int]$integrationResult.IntegratedCount,
                    [int]$integrationResult.SkippedMountCount,
                    [int]$integrationResult.FailedCount)
            } catch {}

            Reset-CatalogState
            Apply-CatalogView
            Set-UpdatesStatusText -Message 'Batch-Integration abgeschlossen. Mount-Kontext wird neu geladen...'
            if ($script:ctx -and $script:ctx.Page) {
                Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesFooterHint' -Value 'Batch-Integration abgeschlossen. Mount- und Catalog-Daten werden aktualisiert...'
                Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesBatchPlan' -Value ("Letzter Batch: {0} OK, {1} übersprungen, {2} Fehler." -f [int]$integrationResult.IntegratedCount, [int]$integrationResult.SkippedMountCount, [int]$integrationResult.FailedCount)
            }

            Show-UiInfo -Message $message -Title 'Integration'

            $mountDir = Get-SelectedMountDir
            if ([string]::IsNullOrWhiteSpace($mountDir) -and $script:updateContext) {
                try { $mountDir = [string]$script:updateContext.MountDir } catch {}
            }
            if (-not [string]::IsNullOrWhiteSpace($mountDir)) {
                Start-SelectedMountContextLoad -MountDir $mountDir -TriggerCatalogIfEnabled
            } else {
                Refresh-UpdatesUI
            }
        } `
        -OnError {
            param($ex)

            Set-UpdatesBusy -Busy $false
            Show-UiError -Message $ex.Message -Title 'Integration'
        }
}
