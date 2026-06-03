function Add-DriversFromFolderAsync {
    if ($script:isBusy) { return }
    if (Get-ImageServicingBusy) { return }

    $mountDir = Resolve-DriverMountDir
    if (-not (Test-DriverMountUsable -MountDir $mountDir)) {
        Show-UiError -Message (Get-UiString -Key 'DriverNoValidMountDir')
        return
    }

    Assert-DriverMountUsable -MountDir $mountDir
    Write-DriverMountLog -Operation 'AddDriver' -MountDir $mountDir

    $folder = $null
    try {
        $folder = Select-DriverSourceFolder
        if ([string]::IsNullOrWhiteSpace($folder)) { return }
    }
    catch {
        Show-UiError -Message $_.Exception.Message
        return
    }

    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        Show-UiError -Message (Get-UiString -Key 'DriverFolderMissingFormat' -Args @($folder))
        return
    }

    $recurse = $true
    $forceUnsigned = $false
    try { $recurse = [bool]$script:ctx["ChkDriverRecurse"].IsChecked } catch { $recurse = $true }
    try { $forceUnsigned = [bool]$script:ctx["ChkDriverForceUnsigned"].IsChecked } catch { $forceUnsigned = $false }

    $fnBusy = (Get-Item function:Set-DriverBusy -ErrorAction Stop).ScriptBlock
    $fnSet  = (Get-Item function:Set-DriversList -ErrorAction Stop).ScriptBlock
    $fnErr  = (Get-Item function:Show-UiError -ErrorAction Stop).ScriptBlock

    $ctxLocal  = $script:ctx
    $setStatus = $ctxLocal["SetStatus"]

    $all = $true
    try {
        $chk = $ctxLocal["ChkDriverAll"]
        if ($chk) { $all = [bool]$chk.IsChecked }
    } catch { $all = $true }

    & $fnBusy -Busy $true -Reason (Get-UiString -Key 'DriverBusyAdding') -Context $ctxLocal

    $dismModPath   = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist).Replace("'", "''")
    $parserModPath = (Resolve-ProjectPath "Services\DismDriversParser.psm1" -MustExist).Replace("'", "''")

    $safeMount   = $mountDir.Replace("'", "''")
    $safeFolder  = $folder.Replace("'", "''")
    $recurseFlag = if ($recurse) { "1" } else { "0" }
    $forceFlag   = if ($forceUnsigned) { "1" } else { "0" }
    $allFlag     = if ($all) { "1" } else { "0" }

    $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__DISM__' -Force
Import-Module '__PARSER__' -Force

$mount   = '__MOUNT__'
$folder  = '__FOLDER__'
$recurse = [int]'__RECURSE__'
$force   = [int]'__FORCE__'
$all     = [int]'__ALL__'

if (-not (Test-Path -LiteralPath $mount -PathType Container)) {
  throw ("MountDir nicht gefunden: {0}" -f $mount)
}

$windowsDir = Join-Path -Path $mount -ChildPath 'Windows'
if (-not (Test-Path -LiteralPath $windowsDir -PathType Container)) {
  throw ("Ungültiges MountDir, 'Windows' fehlt: {0}" -f $mount)
}

if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
  throw ("Treiberordner nicht gefunden: {0}" -f $folder)
}

$argsAdd = @('/English', "/Image:$mount", '/Add-Driver', "/Driver:$folder")
if ($recurse -eq 1) { $argsAdd += '/Recurse' }
if ($force -eq 1)   { $argsAdd += '/ForceUnsigned' }

$resAdd = Invoke-Dism -Arguments $argsAdd -EnsureEnglish
if ($resAdd.ExitCode -ne 0) {
  $msg = $resAdd.StdErr
  if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $resAdd.StdOut }
  throw ("DISM /Add-Driver fehlgeschlagen (ExitCode={0}).`n`n{1}" -f $resAdd.ExitCode, $msg)
}

$argsList = @('/English', "/Image:$mount", '/Get-Drivers', '/Format:Table')
if ($all -eq 1) { $argsList += '/All' }

$resList = Invoke-Dism -Arguments $argsList -EnsureEnglish
if ($resList.ExitCode -ne 0) {
  $msg = $resList.StdErr
  if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $resList.StdOut }
  throw ("DISM /Get-Drivers failed after Add (ExitCode={0}).`n`n{1}" -f $resList.ExitCode, $msg)
}

$drivers = ConvertFrom-DismDriversOutput -Text $resList.StdOut
,$drivers
'@

    $code = $code.Replace("__DISM__", $dismModPath).Replace("__PARSER__", $parserModPath).Replace("__MOUNT__", $safeMount).
        Replace("__FOLDER__", $safeFolder).Replace("__RECURSE__", $recurseFlag).Replace("__FORCE__", $forceFlag).Replace("__ALL__", $allFlag)

    $onCompleted = {
        param($resArr)
        try {
            $drivers = @($resArr)
            & $fnSet -Drivers $drivers -Context $ctxLocal -StatusText (Get-UiString -Key 'DriverAddOkFormat' -Args @($drivers.Count))
        } finally {
            & $fnBusy -Busy $false -Context $ctxLocal
        }
    }.GetNewClosure()

    $onError = {
        param($ex)
        try { & $fnErr -Message $ex.Message } catch {}
        finally {
            & $fnBusy -Busy $false -Context $ctxLocal
            if ($setStatus) { try { & $setStatus "Ready" } catch {} }
        }
    }.GetNewClosure()

    Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label "Driver:AddDriver"
}

function Remove-SelectedDriverAsync {
    if ($script:isBusy) { return }
    if (Get-ImageServicingBusy) { return }

    $mountDir = Resolve-DriverMountDir
    if (-not (Test-DriverMountUsable -MountDir $mountDir)) {
        Show-UiError -Message (Get-UiString -Key 'DriverNoValidMountDir')
        return
    }

    Assert-DriverMountUsable -MountDir $mountDir
    Write-DriverMountLog -Operation 'RemoveDriver' -MountDir $mountDir

    $selItems = @(Get-SelectedDriverItems)
    if ($selItems.Count -lt 1) {
        Show-UiError -Message (Get-UiString -Key 'StaticSelectDriverFirst')
        return
    }

    $toRemove = New-Object System.Collections.Generic.List[string]
    $skippedInbox = 0

    foreach ($it in $selItems) {
        $pn = $null
        $inboxTxt = $null
        try {
            if ($it.PSObject.Properties.Match("PublishedName").Count -gt 0) {
                $pn = [string]$it.PublishedName
            }
        } catch {}
        try {
            if ($it.PSObject.Properties.Match("Inbox").Count -gt 0) {
                $inboxTxt = [string]$it.Inbox
            }
        } catch {}

        if ([string]::IsNullOrWhiteSpace($pn)) { continue }

        $isInbox = ConvertTo-InboxBool -InboxText $inboxTxt
        if ($isInbox -eq $true) {
            $skippedInbox++
            continue
        }

        if (-not $toRemove.Contains($pn)) {
            $toRemove.Add($pn) | Out-Null
        }
    }

    if ($toRemove.Count -lt 1) {
        Show-UiError -Message (Get-UiString -Key 'DriverNoRemovableSelectionFormat' -Args @($skippedInbox))
        return
    }

    try {
        $confirmed = Confirm-DriverRemoval -PublishedNames $toRemove.ToArray()
        if (-not $confirmed) { return }
    }
    catch {
        Show-UiError -Message $_.Exception.Message
        return
    }

    $fnBusy = (Get-Item function:Set-DriverBusy -ErrorAction Stop).ScriptBlock
    $fnSet  = (Get-Item function:Set-DriversList -ErrorAction Stop).ScriptBlock
    $fnErr  = (Get-Item function:Show-UiError -ErrorAction Stop).ScriptBlock

    $ctxLocal  = $script:ctx
    $setStatus = $ctxLocal["SetStatus"]

    $all = $true
    try {
        $chk = $ctxLocal["ChkDriverAll"]
        if ($chk) { $all = [bool]$chk.IsChecked }
    } catch { $all = $true }

    & $fnBusy -Busy $true -Reason (Get-UiString -Key 'DriverBusyRemovingFormat' -Args @($toRemove.Count)) -Context $ctxLocal

    $dismModPath   = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist).Replace("'", "''")
    $parserModPath = (Resolve-ProjectPath "Services\DismDriversParser.psm1" -MustExist).Replace("'", "''")

    $safeMount = $mountDir.Replace("'", "''")
    $pubJoined = ($toRemove.ToArray() -join '|').Replace("'", "''")
    $allFlag   = if ($all) { "1" } else { "0" }

    $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__DISM__' -Force
Import-Module '__PARSER__' -Force

$mount = '__MOUNT__'
$pubs  = '__PUBS__' -split '\|'
$all   = [int]'__ALL__'

if (-not (Test-Path -LiteralPath $mount -PathType Container)) {
  throw ("MountDir nicht gefunden: {0}" -f $mount)
}

$windowsDir = Join-Path -Path $mount -ChildPath 'Windows'
if (-not (Test-Path -LiteralPath $windowsDir -PathType Container)) {
  throw ("Ungültiges MountDir, 'Windows' fehlt: {0}" -f $mount)
}

foreach ($pub in $pubs) {
  if ([string]::IsNullOrWhiteSpace($pub)) { continue }

  $argsRm = @('/English', "/Image:$mount", '/Remove-Driver', "/Driver:$pub")
  $resRm = Invoke-Dism -Arguments $argsRm -EnsureEnglish

  if ($resRm.ExitCode -ne 0) {
    $combined = ($resRm.StdErr + "`n" + $resRm.StdOut)
    if ($combined -match '0x80070002' -or
        $combined -match '(?i)No driver packages were found' -or
        $combined -match '(?i)problem opening the INF file') {
      continue
    }

    $msg = $resRm.StdErr
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $resRm.StdOut }
    throw ("DISM /Remove-Driver fehlgeschlagen (ExitCode={0}) für {1}.`n`n{2}" -f $resRm.ExitCode, $pub, $msg)
  }
}

$argsList = @('/English', "/Image:$mount", '/Get-Drivers', '/Format:Table')
if ($all -eq 1) { $argsList += '/All' }

$resList = Invoke-Dism -Arguments $argsList -EnsureEnglish
if ($resList.ExitCode -ne 0) {
  $msg = $resList.StdErr
  if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $resList.StdOut }
  throw ("DISM /Get-Drivers failed after Remove (ExitCode={0}).`n`n{1}" -f $resList.ExitCode, $msg)
}

$drivers = ConvertFrom-DismDriversOutput -Text $resList.StdOut
,$drivers
'@

    $code = $code.Replace("__DISM__", $dismModPath).Replace("__PARSER__", $parserModPath).Replace("__MOUNT__", $safeMount).
        Replace("__PUBS__", $pubJoined).Replace("__ALL__", $allFlag)

    $onCompleted = {
        param($resArr)
        try {
            $drivers = @($resArr)
            & $fnSet -Drivers $drivers -Context $ctxLocal -StatusText (Get-UiString -Key 'DriverRemoveOkFormat' -Args @($drivers.Count))
        } finally {
            & $fnBusy -Busy $false -Context $ctxLocal
        }
    }.GetNewClosure()

    $onError = {
        param($ex)
        try { & $fnErr -Message $ex.Message } catch {}
        finally {
            & $fnBusy -Busy $false -Context $ctxLocal
            if ($setStatus) { try { & $setStatus "Ready" } catch {} }
        }
    }.GetNewClosure()

    Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label "Driver:RemoveDriver"
}
