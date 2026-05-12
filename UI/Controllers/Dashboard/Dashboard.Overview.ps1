function Format-DashboardDate {
    param($Value)

    if ($null -eq $Value) { return '-' }
    try { return ([DateTime]::Parse([string]$Value)).ToString('dd.MM. HH:mm:ss') } catch {}
    return [string]$Value
}

function Format-DashboardDuration {
    param($DurationMs)

    if ($null -eq $DurationMs) { return '-' }
    try {
        $ts = [TimeSpan]::FromMilliseconds([int64]$DurationMs)
        if ($ts.TotalHours -ge 1) { return ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds) }
        return ('{0:00}:{1:00}' -f $ts.Minutes, $ts.Seconds)
    } catch {
        return '-'
    }
}

function Format-DashboardJobLine {
    param($Job)

    if (-not $Job) { return '-' }
    $time = Format-DashboardDate $Job.CreatedAt
    $status = [string]$Job.Status
    $operation = [string]$Job.Operation
    $duration = Format-DashboardDuration $Job.DurationMs
    return ('{0} | {1,-9} | {2} | {3}' -f $time, $status, $operation, $duration)
}

function Refresh-DashboardJobOverview {
    param($Root)

    if (-not $Root) { return }

    try {
        if (-not (Get-Command Get-JobHistory -ErrorAction SilentlyContinue)) {
            Set-UiText -Root $Root -Name "TxtDashLastJob" -Value "Job-Verlauf nicht geladen"
            Set-UiText -Root $Root -Name "TxtDashLastJobDetail" -Value "-"
            Set-UiText -Root $Root -Name "TxtDashLastError" -Value "-"
            Set-UiText -Root $Root -Name "TxtDashLastErrorDetail" -Value "-"
            return
        }

        $jobs = @(Get-JobHistory -Limit 8)
        $last = $jobs | Select-Object -First 1
        $lastError = $jobs | Where-Object { [string]$_.Status -eq 'Failed' } | Select-Object -First 1

        if ($last) {
            Set-UiText -Root $Root -Name "TxtDashLastJob" -Value ("{0}: {1}" -f [string]$last.Status, [string]$last.Operation)
            Set-UiText -Root $Root -Name "TxtDashLastJobDetail" -Value ("{0} | {1}" -f (Format-DashboardDate $last.CreatedAt), (Format-DashboardDuration $last.DurationMs))
        } else {
            Set-UiText -Root $Root -Name "TxtDashLastJob" -Value "Noch keine Jobs"
            Set-UiText -Root $Root -Name "TxtDashLastJobDetail" -Value "Sobald eine lange Aktion läuft, erscheint sie hier."
        }

        if ($lastError) {
            Set-UiText -Root $Root -Name "TxtDashLastError" -Value ([string]$lastError.Operation)
            $errText = [string]$lastError.Error
            if ($errText.Length -gt 160) { $errText = $errText.Substring(0, 160) + '...' }
            Set-UiText -Root $Root -Name "TxtDashLastErrorDetail" -Value $errText
        } else {
            Set-UiText -Root $Root -Name "TxtDashLastError" -Value "Keine Fehler im Verlauf"
            Set-UiText -Root $Root -Name "TxtDashLastErrorDetail" -Value "-"
        }

        $list = Find-Ui -Root $Root -Name "LstDashRecentJobs"
        if ($list) {
            $items = New-Object System.Collections.ObjectModel.ObservableCollection[string]
            foreach ($job in $jobs) { [void]$items.Add((Format-DashboardJobLine -Job $job)) }
            if ($items.Count -eq 0) { [void]$items.Add('Noch keine Jobs erfasst.') }
            $list.ItemsSource = $items
        }
    } catch {
        Set-UiText -Root $Root -Name "TxtDashLastJob" -Value "Job-Verlauf konnte nicht geladen werden"
        Set-UiText -Root $Root -Name "TxtDashLastJobDetail" -Value $_.Exception.Message
    }
}

function Refresh-DashboardHealthOverview {
    param($Root)

    if (-not $Root) { return }

    try {
        $dismExe = Join-Path $env:WINDIR 'System32\dism.exe'
        if (Test-Path -LiteralPath $dismExe -PathType Leaf) {
            Set-UiText -Root $Root -Name "TxtDashDismStatus" -Value "DISM: OK"
        } else {
            Set-UiText -Root $Root -Name "TxtDashDismStatus" -Value "DISM: nicht gefunden"
        }
    } catch {
        Set-UiText -Root $Root -Name "TxtDashDismStatus" -Value "DISM: unbekannt"
    }

    try {
        if (Get-Command Get-AdkStatus -ErrorAction SilentlyContinue) {
            $adk = Get-AdkStatus
            $parts = New-Object System.Collections.Generic.List[string]
            if ($adk.HasAdkRoot) { [void]$parts.Add('ADK') }
            if ($adk.HasWinPe) { [void]$parts.Add('WinPE') }
            if ($adk.HasOscdimg) { [void]$parts.Add('oscdimg') }
            $text = if ($parts.Count -gt 0) { 'ADK: ' + ($parts -join ', ') } else { 'ADK: nicht eingerichtet' }
            Set-UiText -Root $Root -Name "TxtDashAdkStatus" -Value $text
        } else {
            Set-UiText -Root $Root -Name "TxtDashAdkStatus" -Value "ADK: nicht geprüft"
        }
    } catch {
        Set-UiText -Root $Root -Name "TxtDashAdkStatus" -Value "ADK: Fehler beim Prüfen"
    }

    try {
        if (-not (Get-Command Get-MountedWimList -ErrorAction SilentlyContinue)) {
            Set-UiText -Root $Root -Name "TxtDashActiveMounts" -Value "-"
            Set-UiText -Root $Root -Name "TxtDashMountHealth" -Value "Mount-Service nicht geladen"
            return
        }

        $mounts = @(Get-MountedWimList)
        $active = @($mounts | Where-Object {
            $registryOnly = $false
            try { $registryOnly = [bool]$_.RegistryOnly } catch {}
            -not $registryOnly
        })
        $problem = @($mounts | Where-Object {
            $health = ''
            try { $health = [string]$_.Health } catch {}
            $registryOnly = $false
            try { $registryOnly = [bool]$_.RegistryOnly } catch {}
            $registryOnly -or ($health -and $health -notmatch '^OK$')
        })

        Set-UiText -Root $Root -Name "TxtDashActiveMounts" -Value $active.Count
        if ($problem.Count -gt 0) {
            Set-UiText -Root $Root -Name "TxtDashMountHealth" -Value ("{0} Hinweis(e): Reparatur im Images-Bereich prüfen" -f $problem.Count)
        } else {
            Set-UiText -Root $Root -Name "TxtDashMountHealth" -Value "Mount-Zustand OK"
        }
    } catch {
        Set-UiText -Root $Root -Name "TxtDashActiveMounts" -Value "?"
        Set-UiText -Root $Root -Name "TxtDashMountHealth" -Value ("Mounts konnten nicht gelesen werden: {0}" -f $_.Exception.Message)
    }
}
