Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:UiDispatcher = $null
$script:UiThreadId   = $null

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
    $fnLog     = (Get-Item function:Write-UiAsyncLog -ErrorAction Stop).ScriptBlock
    $fnInvokeUi= (Get-Item function:Invoke-Ui        -ErrorAction Stop).ScriptBlock

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

            & $fnInvokeUi { & $doneLocal $resArr }
        } catch {
            $err = $_
            $ex  = $_.Exception

            $stack = $null
            try { $stack = $err.ScriptStackTrace } catch { $stack = $null }

            $msg = "UiTask '{0}' failed: {1}" -f $labelLocal, $ex.Message
            if ($stack) { $msg = $msg + "`nSTACK:`n" + $stack }

            & $fnLog -Level ERROR -Message $msg -ToConsole

            try { $psLocal.Dispose() } catch {}
            try { $rsLocal.Dispose() } catch {}

            $ex2 = New-Object System.Exception($msg, $ex)
            & $fnInvokeUi { & $errLocal $ex2 }
        }
    }.GetNewClosure()

    $timer.Add_Tick($tick)
    $timer.Start()
}

Export-ModuleMember -Function Write-UiAsyncLog, Initialize-UiAsync, Invoke-Ui, Start-UiTask