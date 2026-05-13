Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:UiDispatcher = $null
$script:UiThreadId   = $null
$script:UiBusyProgressTimers = @{}

function Write-UiAsyncLog {
    param(
        [Parameter(Mandatory)][ValidateSet("INFO","WARN","ERROR")] [string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [switch]$ToConsole
    )
    try {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level $Level -Message $Message -ToConsole:$ToConsole
            return
        }
    } catch {}

    try {
        $prefix = "[{0}] " -f $Level
        Write-Host ($prefix + $Message)
    } catch {}
}

function Write-UiTaskHistory {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][ValidateSet("Started","Completed","Failed","Cancelled","Skipped","Info")][string]$Status,
        [datetime]$StartedAt = (Get-Date),
        [Nullable[datetime]]$EndedAt = $null,
        [Nullable[int64]]$DurationMs = $null,
        [string]$Message = $null,
        [string]$Detail = $null,
        [string]$ErrorText = $null,
        [hashtable]$Data = $null
    )

    try {
        $cmd = Get-Command Add-JobHistoryEntry -ErrorAction SilentlyContinue
        if (-not $cmd) { return }

        $maxEntries = 250
        try {
            if (Get-Command Get-ConfigValue -ErrorAction SilentlyContinue) {
                $maxEntries = [int](Get-ConfigValue -Key "JobHistoryMaxEntries" -Default 250)
            }
        } catch {
            $maxEntries = 250
        }

        $params = @{
            Operation  = $Label
            Status     = $Status
            Message    = if ([string]::IsNullOrWhiteSpace($Message)) { $Label } else { $Message }
            Detail     = $Detail
            ErrorText  = $ErrorText
            StartedAt  = $StartedAt
            MaxEntries = $maxEntries
            Data       = $Data
        }

        if ($null -ne $EndedAt) { $params.EndedAt = [datetime]$EndedAt }
        if ($null -ne $DurationMs) { $params.DurationMs = [int64]$DurationMs }

        Add-JobHistoryEntry @params | Out-Null
    } catch {}
}

function Initialize-UiAsync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Window
    )

    $script:UiDispatcher = $Window.Dispatcher
    try { $script:UiThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId } catch { $script:UiThreadId = $null }

    Write-UiAsyncLog -Level INFO -Message ("UiAsync: Dispatcher set. UiThreadId={0}" -f $script:UiThreadId) -ToConsole
}

function Invoke-Ui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [System.Windows.Threading.DispatcherPriority]$Priority = [System.Windows.Threading.DispatcherPriority]::Normal
    )

    $d = $script:UiDispatcher
    if ($null -eq $d) { & $Action; return }

    try {
        if ($d.CheckAccess()) { & $Action; return }
    } catch {}

    $sb  = $Action
    $act = [Action]{ & $sb }

    try {
        $null = $d.Invoke($act, $Priority)
    } catch {
        try { $null = $d.BeginInvoke($act, $Priority) }
        catch { & $Action }
    }
}

function Get-UiBusyProgressKey {
    param($Root, $Context)

    try {
        if ($Root) { return ('root:{0}' -f $Root.GetHashCode()) }
    } catch {}

    try {
        if ($Context) { return ('ctx:{0}' -f $Context.GetHashCode()) }
    } catch {}

    return 'global'
}

function Resolve-UiBusyProgressRoot {
    param($Root, $Context)

    if ($Root) { return $Root }

    foreach ($key in @('Page', 'ImagesPage', 'DriverPage', 'MediaBuilderPage')) {
        try {
            if ($Context -is [System.Collections.IDictionary] -and $Context.Contains($key) -and $Context[$key]) {
                return $Context[$key]
            }
        } catch {}

        try {
            $prop = $Context.PSObject.Properties[$key]
            if ($prop -and $prop.Value) { return $prop.Value }
        } catch {}
    }

    return $null
}

function Resolve-UiBusyProgressControl {
    param($Root, $Context, [Parameter(Mandatory)][string]$Name)

    try {
        if ($Context -is [System.Collections.IDictionary] -and $Context.Contains($Name) -and $Context[$Name]) {
            return $Context[$Name]
        }
    } catch {}

    try {
        $prop = $Context.PSObject.Properties[$Name]
        if ($prop -and $prop.Value) { return $prop.Value }
    } catch {}

    try {
        if ($Root) {
            $ctrl = $Root.FindName($Name)
            if ($ctrl) { return $ctrl }
        }
    } catch {}

    return $null
}

function Set-UiBusyProgressText {
    param($Root, $Context, [Parameter(Mandatory)][string]$Name, [string]$Text)

    $ctrl = Resolve-UiBusyProgressControl -Root $Root -Context $Context -Name $Name
    if (-not $ctrl) { return }

    try { $ctrl.Text = $Text } catch {}
}

function Format-UiBusyElapsed {
    param([TimeSpan]$Elapsed)

    if ($Elapsed.TotalHours -ge 1) {
        return ('{0:00}:{1:00}:{2:00}' -f [int]$Elapsed.TotalHours, $Elapsed.Minutes, $Elapsed.Seconds)
    }

    return ('{0:00}:{1:00}' -f $Elapsed.Minutes, $Elapsed.Seconds)
}

function Get-UiDismLogLastLine {
    [CmdletBinding()]
    param([int]$MaxBytes = 12000)

    $path = Join-Path $env:WINDIR 'Logs\DISM\dism.log'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $length = $stream.Length
        if ($length -le 0) { return '' }

        $readBytes = [Math]::Min([int64]$MaxBytes, [int64]$length)
        $buffer = New-Object byte[] ([int]$readBytes)
        $null = $stream.Seek(-1 * $readBytes, [System.IO.SeekOrigin]::End)
        $null = $stream.Read($buffer, 0, [int]$readBytes)
        $text = [System.Text.Encoding]::UTF8.GetString($buffer)

        $lines = @($text -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -lt 1) { return '' }

        $line = [string]$lines[-1]
        if ($line.Length -gt 220) { $line = $line.Substring(0, 220) + '...' }
        return $line
    } catch {
        return ''
    } finally {
        if ($stream) { try { $stream.Dispose() } catch {} }
    }
}

function Update-UiBusyProgress {
    [CmdletBinding()]
    param(
        $Root,
        $Context,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [string]$Message,
        [string]$Detail,
        [string]$Hint,
        [switch]$ShowDismTail
    )

    $rootLocal = Resolve-UiBusyProgressRoot -Root $Root -Context $Context
    if ($Message) { Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyMessage' -Text $Message }

    $elapsed = [DateTime]::Now - $StartedAt
    Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyElapsed' -Text ('Laufzeit: {0}' -f (Format-UiBusyElapsed -Elapsed $elapsed))

    $detailText = $Detail
    if ([string]::IsNullOrWhiteSpace($detailText)) {
        $detailText = 'Vorgang läuft. Bei großen Images kann DISM mehrere Minuten ohne sichtbare Dateigrößenänderung arbeiten.'
    }
    Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyDetail' -Text $detailText

    $hintText = $Hint
    if ([string]::IsNullOrWhiteSpace($hintText)) {
        $hintText = 'Bitte nicht abbrechen, solange DISM CPU/Datenträger nutzt. Beim Abbruch kann ein Mount bereinigt werden müssen.'
    }
    Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyHint' -Text $hintText

    if ($ShowDismTail) {
        $lastLine = Get-UiDismLogLastLine
        if ([string]::IsNullOrWhiteSpace($lastLine)) {
            $lastLine = 'Noch kein DISM-Logeintrag gelesen.'
        }
        Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyDismLastLine' -Text ('DISM: {0}' -f $lastLine)
    }
}

function Start-UiBusyProgress {
    [CmdletBinding()]
    param(
        $Root,
        $Context,
        [string]$Message = 'Bitte warten...',
        [string]$Detail = $null,
        [string]$Hint = $null,
        [switch]$ShowDismTail
    )

    $rootLocal = Resolve-UiBusyProgressRoot -Root $Root -Context $Context
    $key = Get-UiBusyProgressKey -Root $rootLocal -Context $Context

    Stop-UiBusyProgress -Root $rootLocal -Context $Context

    $startedAt = [DateTime]::Now
    Update-UiBusyProgress -Root $rootLocal -Context $Context -StartedAt $startedAt -Message $Message -Detail $Detail -Hint $Hint -ShowDismTail:$ShowDismTail

    $dispatcher = $script:UiDispatcher
    try {
        if ($rootLocal -and $rootLocal.Dispatcher) { $dispatcher = $rootLocal.Dispatcher }
    } catch {}

    if (-not $dispatcher) { return }

    $timer = New-Object System.Windows.Threading.DispatcherTimer(
        [System.Windows.Threading.DispatcherPriority]::Background,
        $dispatcher
    )
    $timer.Interval = [TimeSpan]::FromSeconds(1)

    $rootCapture = $rootLocal
    $ctxCapture = $Context
    $messageCapture = $Message
    $detailCapture = $Detail
    $hintCapture = $Hint
    $showDismCapture = [bool]$ShowDismTail
    $startedCapture = $startedAt

    $tick = {
        Update-UiBusyProgress -Root $rootCapture -Context $ctxCapture -StartedAt $startedCapture -Message $messageCapture -Detail $detailCapture -Hint $hintCapture -ShowDismTail:$showDismCapture
    }.GetNewClosure()

    $timer.Add_Tick($tick)
    $script:UiBusyProgressTimers[$key] = $timer
    $timer.Start()
}

function Stop-UiBusyProgress {
    [CmdletBinding()]
    param($Root, $Context)

    $rootLocal = Resolve-UiBusyProgressRoot -Root $Root -Context $Context
    $key = Get-UiBusyProgressKey -Root $rootLocal -Context $Context

    if ($script:UiBusyProgressTimers.ContainsKey($key)) {
        try { $script:UiBusyProgressTimers[$key].Stop() } catch {}
        try { $script:UiBusyProgressTimers.Remove($key) } catch {}
    }

    Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyElapsed' -Text 'Laufzeit: 00:00'
    Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyDetail' -Text ''
    Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyHint' -Text ''
    Set-UiBusyProgressText -Root $rootLocal -Context $Context -Name 'TxtBusyDismLastLine' -Text ''
}

function Start-UiTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [Parameter(Mandatory)][scriptblock]$OnCompleted,
        [Parameter(Mandatory)][scriptblock]$OnError,

        [string]$Label = "UiTask",
        [int]$TimeoutSec = 0
    )

    # ---- Capture function refs for event/dispatcher scope safety ----
    $fnLog       = (Get-Item function:Write-UiAsyncLog     -ErrorAction Stop).ScriptBlock
    $fnInvokeUi  = (Get-Item function:Invoke-Ui            -ErrorAction Stop).ScriptBlock
    $fnHistory   = (Get-Item function:Write-UiTaskHistory  -ErrorAction Stop).ScriptBlock

    $ps = [PowerShell]::Create()
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "MTA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    $ps.Runspace = $rs

    $start = Get-Date

    try {
        $workText = $Work.ToString()
        $null = $ps.AddScript($workText)
        $handle = $ps.BeginInvoke()
        & $fnLog -Level INFO -Message ("UiAsync: Start-UiTask '{0}' started." -f $Label) -ToConsole
        & $fnHistory -Label $Label -Status Started -StartedAt $start -Message ("Gestartet: {0}" -f $Label)
    } catch {
        try { $ps.Dispose() } catch {}
        try { $rs.Dispose() } catch {}
        $ex = $_.Exception
        & $fnInvokeUi { & $OnError $ex }
        return
    }

    $dispatcher = $script:UiDispatcher
    if ($null -eq $dispatcher) {
        $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    }

    $psLocal     = $ps
    $rsLocal     = $rs
    $handleLocal = $handle
    $doneLocal   = $OnCompleted
    $errLocal    = $OnError
    $labelLocal  = $Label
    $timeout     = [int]$TimeoutSec
    $startLocal  = $start

    $timer = New-Object System.Windows.Threading.DispatcherTimer(
        [System.Windows.Threading.DispatcherPriority]::Background,
        $dispatcher
    )
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)

    $tick = {
        # Timeout prüfen
        if ($timeout -gt 0) {
            try {
                $elapsed = (Get-Date) - $startLocal
                if ($elapsed.TotalSeconds -ge $timeout) {
                    $timer.Stop()
                    try { $psLocal.Stop() } catch {}
                    try { $psLocal.Dispose() } catch {}
                    try { $rsLocal.Dispose() } catch {}

                    $msg = "UI Task timeout: '$labelLocal' after {0:N0}s" -f $elapsed.TotalSeconds
                    & $fnLog -Level ERROR -Message $msg -ToConsole
                    & $fnHistory -Label $labelLocal -Status Failed -StartedAt $startLocal -EndedAt (Get-Date) -DurationMs ([int64]$elapsed.TotalMilliseconds) -Message ("Timeout: {0}" -f $labelLocal) -ErrorText $msg
                    $tex = New-Object System.TimeoutException($msg)
                    & $fnInvokeUi { & $errLocal $tex }
                    return
                }
            } catch {}
        }

        if (-not $handleLocal.IsCompleted) { return }
        $timer.Stop()

        try {
            $tmp = $psLocal.EndInvoke($handleLocal)

            # flatten to array
            $resArr = @()
            if ($null -ne $tmp) { foreach ($x in $tmp) { $resArr += $x } }

            try { $psLocal.Dispose() } catch {}
            try { $rsLocal.Dispose() } catch {}

            $elapsed2 = (Get-Date) - $startLocal
            & $fnLog -Level INFO -Message ("UiAsync: '{0}' completed in {1:N0}ms (items={2})." -f $labelLocal, $elapsed2.TotalMilliseconds, @($resArr).Count) -ToConsole
            & $fnHistory -Label $labelLocal -Status Completed -StartedAt $startLocal -EndedAt (Get-Date) -DurationMs ([int64]$elapsed2.TotalMilliseconds) -Message ("Fertig: {0}" -f $labelLocal) -Detail ("items={0}" -f @($resArr).Count)

            & $fnInvokeUi { & $doneLocal $resArr }
        } catch {
            $err = $_
            $ex  = $_.Exception

            $stack = $null
            try { $stack = $err.ScriptStackTrace } catch { $stack = $null }

            $msg = "UiTask '{0}' failed: {1}" -f $labelLocal, $ex.Message
            if ($stack) { $msg = $msg + "`nSTACK:`n" + $stack }

            & $fnLog -Level ERROR -Message $msg -ToConsole
            $elapsedErr = (Get-Date) - $startLocal
            & $fnHistory -Label $labelLocal -Status Failed -StartedAt $startLocal -EndedAt (Get-Date) -DurationMs ([int64]$elapsedErr.TotalMilliseconds) -Message ("Fehler: {0}" -f $labelLocal) -ErrorText $msg

            try { $psLocal.Dispose() } catch {}
            try { $rsLocal.Dispose() } catch {}

            $ex2 = New-Object System.Exception($msg, $ex)
            & $fnInvokeUi { & $errLocal $ex2 }
        }
    }.GetNewClosure()

    $timer.Add_Tick($tick)
    $timer.Start()
}

Export-ModuleMember -Function Write-UiAsyncLog, Initialize-UiAsync, Invoke-Ui, Start-UiTask, Start-UiBusyProgress, Stop-UiBusyProgress, Update-UiBusyProgress
