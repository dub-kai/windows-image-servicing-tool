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

function Convert-DashboardJobView {
    param($Job)

    if (-not $Job) { return $null }

    $message = ''
    $detail = ''
    $errorText = ''
    try { $message = [string]$Job.Message } catch {}
    try { $detail = [string]$Job.Detail } catch {}
    try { $errorText = [string]$Job.Error } catch {}

    return [pscustomobject]@{
        Time      = Format-DashboardDate $Job.CreatedAt
        Status    = [string]$Job.Status
        Operation = [string]$Job.Operation
        Duration  = Format-DashboardDuration $Job.DurationMs
        Message   = $message
        Detail    = $detail
        Error     = $errorText
        Raw       = $Job
    }
}

function Format-DashboardJobDetails {
    param($JobView)

    if (-not $JobView) { return 'Job auswählen, um Details zu sehen.' }

    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add(("Aktion: {0}" -f [string]$JobView.Operation))
    [void]$parts.Add(("Status: {0}" -f [string]$JobView.Status))
    [void]$parts.Add(("Zeit: {0} | Dauer: {1}" -f [string]$JobView.Time, [string]$JobView.Duration))

    if (-not [string]::IsNullOrWhiteSpace([string]$JobView.Message)) {
        [void]$parts.Add(("Meldung: {0}" -f [string]$JobView.Message))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$JobView.Detail)) {
        [void]$parts.Add(("Details: {0}" -f [string]$JobView.Detail))
    }

    return ($parts -join "`n")
}

function Update-DashboardJobDetails {
    param(
        [Parameter(Mandatory)]$Root,
        $JobView = $null
    )

    Set-UiText -Root $Root -Name "TxtDashJobDetails" -Value (Format-DashboardJobDetails -JobView $JobView)

    $errorText = ''
    if ($JobView) {
        try { $errorText = [string]$JobView.Error } catch {}
    }
    if ($errorText.Length -gt 900) { $errorText = $errorText.Substring(0, 900) + '...' }
    Set-UiText -Root $Root -Name "TxtDashJobError" -Value $errorText
}

function Get-DashboardSelectedJobView {
    param($Root)

    if (-not $Root) { return $null }
    try {
        $grid = Find-Ui -Root $Root -Name "GridDashRecentJobs"
        if ($grid) { return $grid.SelectedItem }
    } catch {}

    return $null
}

function Get-DashboardSelectedJobText {
    param($Root)

    $job = Get-DashboardSelectedJobView -Root $Root
    $text = Format-DashboardJobDetails -JobView $job

    $errorText = ''
    if ($job) {
        try { $errorText = [string]$job.Error } catch {}
    }
    if (-not [string]::IsNullOrWhiteSpace($errorText)) {
        $text = $text + "`n`nFehler:`n" + $errorText
    }

    return $text
}

function Copy-DashboardSelectedJobDetails {
    param($Root)

    $text = Get-DashboardSelectedJobText -Root $Root
    if ([string]::IsNullOrWhiteSpace($text)) {
        Show-UiInfo -Message "Keine Jobdetails zum Kopieren vorhanden." -Title "Dashboard"
        return
    }

    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue | Out-Null
    [System.Windows.Clipboard]::SetText($text)
}

function Open-DashboardPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Pfad ist leer."
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Pfad nicht gefunden: $Path"
    }

    Start-Process -FilePath $Path | Out-Null
}

function Open-DashboardJobHistoryFile {
    if (-not (Get-Command Get-JobHistoryFilePath -ErrorAction SilentlyContinue)) {
        throw "JobHistory-Modul ist nicht geladen."
    }

    Open-DashboardPath -Path (Get-JobHistoryFilePath)
}

function Open-DashboardDismLog {
    $path = Join-Path $env:WINDIR "Logs\DISM\dism.log"
    Open-DashboardPath -Path $path
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

        $grid = Find-Ui -Root $Root -Name "GridDashRecentJobs"
        if ($grid) {
            $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
            foreach ($job in $jobs) {
                $view = Convert-DashboardJobView -Job $job
                if ($view) { [void]$items.Add($view) }
            }

            $grid.ItemsSource = $items
            if ($items.Count -gt 0 -and -not $grid.SelectedItem) {
                $grid.SelectedIndex = 0
            }
            if ($grid.SelectedItem) {
                Update-DashboardJobDetails -Root $Root -JobView $grid.SelectedItem
            } else {
                Update-DashboardJobDetails -Root $Root
            }

            foreach ($buttonName in @("BtnDashCopyJobDetails","BtnDashOpenHistory","BtnDashOpenDismLog")) {
                Set-UiEnabled -Root $Root -Name $buttonName -Enabled $true
            }
        }
    } catch {
        Set-UiText -Root $Root -Name "TxtDashLastJob" -Value "Job-Verlauf konnte nicht geladen werden"
        Set-UiText -Root $Root -Name "TxtDashLastJobDetail" -Value $_.Exception.Message
        try { Update-DashboardJobDetails -Root $Root } catch {}
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
