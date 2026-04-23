function Clear-DriversList {
    param(
        $Context = $null,
        [string]$StatusText = "Driver: Treiber=0"
    )

    $ctxLocal = if ($null -ne $Context) { $Context } else { $script:ctx }
    if (-not $ctxLocal) { return }

    Set-DriversList -Drivers @() -Context $ctxLocal -StatusText $StatusText
}

function Export-DriversCsv {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    $lst = $script:ctx["LstDrivers"]
    $mountDir = Resolve-DriverMountDir
    $items = @()

    try {
        if ($lst -and $lst.ItemsSource) {
            $items = @($lst.ItemsSource)
        }
    } catch {
        $items = @()
    }

    if (@($items).Count -le 0) {
        Show-UiInfo -Message 'Aktuell sind keine Treiber zum Exportieren geladen.' -Title 'Driver Export'
        return
    }

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'CSV (*.csv)|*.csv|Alle Dateien (*.*)|*.*'
    $dlg.FileName = ('drivers_{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    $dlg.OverwritePrompt = $true

    $ok = $dlg.ShowDialog()
    if ($ok -ne $true) { return }

    $dest = [string]$dlg.FileName
    if ([string]::IsNullOrWhiteSpace($dest)) { return }

    $rows = @(
        foreach ($driver in $items) {
            [pscustomobject]@{
                MountDir         = $mountDir
                PublishedName    = [string]$driver.PublishedName
                OriginalFileName = [string]$driver.OriginalFileName
                ProviderName     = [string]$driver.ProviderName
                ClassName        = [string]$driver.ClassName
                Date             = [string]$driver.Date
                Version          = [string]$driver.Version
                Inbox            = [string]$driver.Inbox
            }
        }
    )

    try {
        $dir = Split-Path -LiteralPath $dest -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }

        $rows | Export-Csv -LiteralPath $dest -Delimiter ';' -NoTypeInformation -Encoding UTF8

        $setStatus = $script:ctx["SetStatus"]
        if ($setStatus) {
            try { & $setStatus ("Driver CSV exportiert: {0}" -f $dest) } catch {}
        }
    } catch {
        Show-UiError -Message $_.Exception.Message -Title 'Driver Export'
    }
}

function Set-DriversList {
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Drivers = @(),
        $Context = $null,
        [string]$StatusText = $null
    )

    $ctxLocal = if ($null -ne $Context) { $Context } else { $script:ctx }
    if (-not $ctxLocal) { return }

    $lst = $ctxLocal["LstDrivers"]
    if ($lst) {
        try {
            $items = @($Drivers)
            $lst.ItemsSource = $null
            $lst.ItemsSource = $items
            $lst.SelectedIndex = -1
            $lst.Items.Refresh()
        } catch {}

        try {
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($lst.ItemsSource)
            if ($view) { $view.Refresh() }
        } catch {}
    }

    if ($StatusText) {
        $setStatus = $ctxLocal["SetStatus"]
        if ($setStatus) {
            try { & $setStatus $StatusText } catch {}
        }
    }

    try { Refresh-DriverUI } catch {}
}

function Request-DriversReload {
    param(
        [string]$Reason = $null
    )

    if (-not $script:ctx) { return }

    $mountDir = Resolve-DriverMountDir
    if (-not (Test-DriverMountUsable -MountDir $mountDir)) {
        try { Set-AppStateValue -Key "DriverMountDir" -Value $null } catch {}
        try { Clear-DriversList -Context $script:ctx -StatusText "Driver: Treiber=0" } catch {}
        return
    }

    $script:reloadPending = $true

    if ($script:isBusy) { return }
    if (Get-ImageServicingBusy) { return }

    $script:reloadPending = $false

    try {
        if ($Reason) {
            Write-Log -Level INFO -Message ("Driver: Reload requested ({0})" -f $Reason)
        }
    } catch {}

    try { Load-DriversAsync } catch {}
}

function Load-DriversAsync {
    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    if (Get-ImageServicingBusy) {
        $script:reloadPending = $true
        return
    }

    $mountDir = Resolve-DriverMountDir
    if (-not (Test-DriverMountUsable -MountDir $mountDir)) {
        try { Set-AppStateValue -Key "DriverMountDir" -Value $null } catch {}
        Clear-DriversList -Context $script:ctx -StatusText "Driver: Treiber=0"
        return
    }

    Assert-DriverMountUsable -MountDir $mountDir
    Write-DriverMountLog -Operation 'GetDrivers' -MountDir $mountDir

    $fnBusy    = (Get-Item function:Set-DriverBusy                -ErrorAction Stop).ScriptBlock
    $fnSet     = (Get-Item function:Set-DriversList               -ErrorAction Stop).ScriptBlock
    $fnErr     = (Get-Item function:Show-UiError                  -ErrorAction Stop).ScriptBlock
    $fnClear   = (Get-Item function:Clear-DriversList             -ErrorAction Stop).ScriptBlock
    $fnTrans   = (Get-Item function:Test-DriverTransientDismError -ErrorAction Stop).ScriptBlock
    $fnMountOk = (Get-Item function:Test-DriverMountUsable        -ErrorAction Stop).ScriptBlock

    $ctxLocal  = $script:ctx
    $setStatus = $ctxLocal["SetStatus"]

    $all = $true
    try {
        $chk = $ctxLocal["ChkDriverAll"]
        if ($chk) { $all = [bool]$chk.IsChecked }
    } catch { $all = $true }

    & $fnBusy -Busy $true -Reason "Treiber werden gelesen..." -Context $ctxLocal

    $dismModPath   = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist)
    $parserModPath = (Resolve-ProjectPath "Services\DismDriversParser.psm1" -MustExist)

    $safeDism   = $dismModPath.Replace("'", "''")
    $safeParser = $parserModPath.Replace("'", "''")
    $safeMount  = $mountDir.Replace("'", "''")
    $allFlag    = if ($all) { "1" } else { "0" }

    $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__DISM__' -Force
Import-Module '__PARSER__' -Force

$mount = '__MOUNT__'
$all   = [int]'__ALL__'

$args = @('/English', "/Image:$mount", '/Get-Drivers', '/Format:Table')
if ($all -eq 1) { $args += '/All' }

$res = Invoke-Dism -Arguments $args -EnsureEnglish
if ($res.ExitCode -ne 0) {
  $msg = $res.StdErr
  if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $res.StdOut }
  throw ("DISM /Get-Drivers failed (ExitCode={0}).`n`n{1}" -f $res.ExitCode, $msg)
}

$drivers = ConvertFrom-DismDriversOutput -Text $res.StdOut
,$drivers
'@

    $code = $code.Replace("__DISM__", $safeDism).Replace("__PARSER__", $safeParser).Replace("__MOUNT__", $safeMount).Replace("__ALL__", $allFlag)

    $onCompleted = {
        param($resArr)
        try {
            $drivers = @($resArr)
            & $fnSet -Drivers $drivers -Context $ctxLocal -StatusText ("Driver: Treiber={0}" -f $drivers.Count)
        } finally {
            & $fnBusy -Busy $false -Context $ctxLocal
        }
    }.GetNewClosure()

    $onError = {
        param($ex)
        try {
            $msg = [string]$ex.Message
            $mountStillThere = (& $fnMountOk $mountDir)
            $isTransient = (& $fnTrans $msg)

            if ((-not $mountStillThere) -or $isTransient) {
                try { Set-AppStateValue -Key "DriverMountDir" -Value $null } catch {}
                try { & $fnClear -Context $ctxLocal -StatusText "Driver: Treiber=0" } catch {}
            } else {
                try { & $fnErr -Message $msg } catch {}
            }
        } finally {
            & $fnBusy -Busy $false -Context $ctxLocal
            if ($setStatus) { try { & $setStatus "Ready" } catch {} }
        }
    }.GetNewClosure()

    Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label "Driver:GetDrivers"
}
