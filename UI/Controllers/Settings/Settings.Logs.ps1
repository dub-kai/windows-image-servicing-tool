function Format-SettingsByteSize {
    param([Int64]$Bytes)

    if ($Bytes -lt 0) { return '-' }
    if ($Bytes -lt 1024) { return ('{0} B' -f $Bytes) }

    $value = [double]$Bytes
    foreach ($unit in @('KB','MB','GB','TB')) {
        $value = $value / 1024
        if ($value -lt 1024 -or $unit -eq 'TB') {
            return ('{0:N1} {1}' -f $value, $unit)
        }
    }

    return ('{0} B' -f $Bytes)
}

function Test-SettingsPathWithinRoot {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$CandidatePath
    )

    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $candFull = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd('\')

    if ($candFull -eq $rootFull) { return $true }
    return $candFull.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-SettingsLogDirectory {
    $configured = $null
    try { $configured = [string](Get-SettingsConfigValue -Key 'LogDir' -Default $null) } catch {}
    if (-not [string]::IsNullOrWhiteSpace($configured)) {
        return $configured
    }

    return (Join-Path (Get-ProjectRoot) 'Logs')
}

function Get-SettingsDismLogPath {
    return (Join-Path $env:WINDIR 'Logs\DISM\dism.log')
}

function Get-SettingsCurrentLogPath {
    try {
        if (Get-Command Get-LogFilePath -ErrorAction SilentlyContinue) {
            $path = [string](Get-LogFilePath)
            if (-not [string]::IsNullOrWhiteSpace($path)) { return $path }
        }
    } catch {}

    return (Join-Path (Get-SettingsLogDirectory) ('WinImageAdmin_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')))
}

function Get-SettingsFileTail {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxLines = 140,
        [int]$MaxChars = 70000
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (Get-UiString -Key 'LogsPreviewMissing')
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $readBytes = [Math]::Min([int64]$stream.Length, [int64]([Math]::Max($MaxChars * 4, 16000)))
        if ($readBytes -le 0) {
            return (Get-UiString -Key 'LogsPreviewEmpty')
        }

        $buffer = New-Object byte[] ([int]$readBytes)
        $null = $stream.Seek(-1 * $readBytes, [System.IO.SeekOrigin]::End)
        $null = $stream.Read($buffer, 0, [int]$readBytes)
        $raw = [System.Text.Encoding]::UTF8.GetString($buffer)
        $wasTrimmed = ($stream.Length -gt $readBytes)
    } catch {
        return (Get-UiString -Key 'LogsPreviewReadFailed' -Args @($_.Exception.Message))
    } finally {
        if ($stream) { try { $stream.Dispose() } catch {} }
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return (Get-UiString -Key 'LogsPreviewEmpty')
    }

    if ($raw.Length -gt $MaxChars) {
        $raw = $raw.Substring($raw.Length - $MaxChars)
        $wasTrimmed = $true
    }

    $lines = @($raw -split "`r?`n")
    if ($lines.Count -gt $MaxLines) {
        $start = [Math]::Max(0, $lines.Count - $MaxLines)
        $lines = @($lines[$start..($lines.Count - 1)])
        $wasTrimmed = $true
    }

    if ($wasTrimmed) {
        $lines = @((Get-UiString -Key 'LogsPreviewTrimmed')) + $lines
    }

    return ($lines -join [Environment]::NewLine)
}

function Get-SettingsLogInventory {
    $logDir = Get-SettingsLogDirectory
    $currentLog = Get-SettingsCurrentLogPath
    $dismLog = Get-SettingsDismLogPath
    $files = @()

    try {
        if (Test-Path -LiteralPath $logDir -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $logDir -Filter 'WinImageAdmin_*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        }
    } catch {
        $files = @()
    }

    $totalBytes = [int64]0
    foreach ($file in $files) {
        try { $totalBytes += [int64]$file.Length } catch {}
    }

    $latestAppLog = if ($files.Count -gt 0) { $files[0] } else { $null }
    $dismInfo = $null
    try {
        if (Test-Path -LiteralPath $dismLog -PathType Leaf) {
            $dismInfo = Get-Item -LiteralPath $dismLog -ErrorAction Stop
        }
    } catch {
        $dismInfo = $null
    }

    return [pscustomobject]@{
        LogDir       = $logDir
        CurrentLog   = $currentLog
        DismLog      = $dismLog
        AppLogFiles  = $files
        AppLogCount  = $files.Count
        AppLogBytes  = $totalBytes
        LatestAppLog = $latestAppLog
        DismLogInfo  = $dismInfo
    }
}

function Get-SettingsLogPreviewSource {
    if ($script:ctx -and $script:ctx.CmbSettingsLogPreviewSource) {
        if (-not $script:ctx.CmbSettingsLogPreviewSource.SelectedItem) {
            Set-SettingsComboToTag -ComboBox $script:ctx.CmbSettingsLogPreviewSource -Tag 'App'
        }

        return (Get-SelectedSettingsComboTag -ComboBox $script:ctx.CmbSettingsLogPreviewSource -Default 'App')
    }

    return 'App'
}

function Refresh-SettingsLogsUI {
    if (-not $script:ctx) { return }

    try {
        $inventory = Get-SettingsLogInventory

        if ($script:ctx.TxtSettingsAppLogPath) {
            $script:ctx.TxtSettingsAppLogPath.Text = (Get-DisplayValue $inventory.CurrentLog)
        }

        if ($script:ctx.TxtSettingsDismLogPath) {
            $script:ctx.TxtSettingsDismLogPath.Text = (Get-DisplayValue $inventory.DismLog)
        }

        $latestText = '-'
        if ($inventory.LatestAppLog) {
            $latestText = ('{0} ({1})' -f $inventory.LatestAppLog.Name, $inventory.LatestAppLog.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
        }

        $dismText = Get-UiString -Key 'LogsMissing'
        if ($inventory.DismLogInfo) {
            $dismText = ('{0}, {1}' -f (Format-SettingsByteSize -Bytes ([int64]$inventory.DismLogInfo.Length)), $inventory.DismLogInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
        }

        if ($script:ctx.TxtSettingsLogsSummary) {
            $script:ctx.TxtSettingsLogsSummary.Text = (Get-UiString -Key 'LogsSummary' -Args @(
                [int]$inventory.AppLogCount,
                (Format-SettingsByteSize -Bytes ([int64]$inventory.AppLogBytes)),
                $latestText,
                $dismText
            ))
        }

        if ($script:ctx.LstSettingsLogFiles) {
            $items = New-Object System.Collections.ObjectModel.ObservableCollection[string]
            foreach ($file in @($inventory.AppLogFiles | Select-Object -First 30)) {
                [void]$items.Add(('{0} | {1} | {2}' -f $file.Name, (Format-SettingsByteSize -Bytes ([int64]$file.Length)), $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))
            }

            if ($items.Count -eq 0) {
                [void]$items.Add((Get-UiString -Key 'LogsNoAppLogs'))
            }

            $script:ctx.LstSettingsLogFiles.ItemsSource = $items
        }

        $source = Get-SettingsLogPreviewSource
        $previewPath = $inventory.CurrentLog
        $sourceLabel = Get-UiString -Key 'LogsPreviewApp'
        if ($source -eq 'Dism') {
            $previewPath = $inventory.DismLog
            $sourceLabel = Get-UiString -Key 'LogsPreviewDism'
        }

        if ($script:ctx.TxtSettingsLogPreviewTitle) {
            $script:ctx.TxtSettingsLogPreviewTitle.Text = (Get-UiString -Key 'LogsPreviewTitleWithSource' -Args @($sourceLabel))
        }

        if ($script:ctx.TxtSettingsLogPreview) {
            $script:ctx.TxtSettingsLogPreview.Text = Get-SettingsFileTail -Path $previewPath
        }
    } catch {
        if ($script:ctx.TxtSettingsLogsSummary) {
            try { $script:ctx.TxtSettingsLogsSummary.Text = (Get-UiString -Key 'LogsLoadFailed' -Args @($_.Exception.Message)) } catch {}
        }
    }
}

function Open-SettingsPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        throw (Get-UiString -Key 'LogsOpenMissing' -Args @((Get-DisplayValue $Path)))
    }

    Start-Process -FilePath $Path | Out-Null
}

function Remove-SettingsOldAppLogs {
    param([int]$RetentionDays = 30)

    $logDir = Get-SettingsLogDirectory
    if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
        return [pscustomobject]@{ RemovedCount = 0; RemovedBytes = [int64]0 }
    }

    $currentLog = $null
    try { $currentLog = [System.IO.Path]::GetFullPath((Get-SettingsCurrentLogPath)) } catch {}
    $cutoff = (Get-Date).AddDays(-1 * [Math]::Abs($RetentionDays))
    $removedCount = 0
    $removedBytes = [int64]0

    $files = @(Get-ChildItem -LiteralPath $logDir -Filter 'WinImageAdmin_*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff })
    foreach ($file in $files) {
        if (-not $file) { continue }

        $full = [System.IO.Path]::GetFullPath([string]$file.FullName)
        if (-not (Test-SettingsPathWithinRoot -RootPath $logDir -CandidatePath $full)) { continue }
        if ($currentLog -and $full.Equals($currentLog, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $length = [int64]0
        try { $length = [int64]$file.Length } catch {}
        Remove-Item -LiteralPath $full -Force
        $removedCount++
        $removedBytes += $length
    }

    return [pscustomobject]@{
        RemovedCount = $removedCount
        RemovedBytes = $removedBytes
    }
}

function Confirm-SettingsLogCleanup {
    param([int]$RetentionDays = 30)

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
    $message = Get-UiString -Key 'LogsCleanupConfirm' -Args @($RetentionDays)
    $title = Get-UiString -Key 'LogsCleanupTitle'
    $result = [System.Windows.MessageBox]::Show(
        $message,
        $title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    return ($result -eq [System.Windows.MessageBoxResult]::Yes)
}
