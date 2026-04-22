Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SelectedWimItem {
    if (-not $script:ctx -or -not $script:ctx.LstWimImages) { return $null }
    try { return $script:ctx.LstWimImages.SelectedItem } catch { return $null }
}

function Start-SaveSourceWimAsync {
    if ($script:isBusy) { return }

    try {
        $mode = Get-ImagesViewMode
        if (-not $mode) { throw "Keine Ansicht ausgewählt." }

        $src = Get-ImagesPathForMode -Mode $mode
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Quelle nicht gefunden: $src" }

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = "WIM/ESD (*.wim;*.esd)|*.wim;*.esd|Alle Dateien (*.*)|*.*"
        $dlg.FileName = (Split-Path -Leaf $src)
        $dlg.OverwritePrompt = $true

        $ok = $dlg.ShowDialog()
        if ($ok -ne $true) { return }

        $dest = [string]$dlg.FileName
        if ([string]::IsNullOrWhiteSpace($dest)) { return }

        $ctxLocal  = $script:ctx
        $setStatus = $script:ctx.SetStatus
        $fnSetBusy = ${function:Set-ImagesBusy}

        & $fnSetBusy -Busy $true -Reason "WIM/ESD wird kopiert..." -Context $ctxLocal

        $safeSrc  = $src.Replace("'", "''")
        $safeDest = $dest.Replace("'", "''")

        $code = @'
$ErrorActionPreference = 'Stop'
$src  = '__SRC__'
$dest = '__DEST__'
Copy-Item -LiteralPath $src -Destination $dest -Force
[pscustomobject]@{ Destination = $dest }
'@
        $code = $code.Replace("__SRC__",  $safeSrc).Replace("__DEST__", $safeDest)

        $onCompleted = {
            param($result)
            try {
                if ($setStatus) { & $setStatus ("Gespeichert: {0}" -f $dest) }
            } finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
            }
        }.GetNewClosure()

        $onError = {
            param($ex)
            try { Show-UiError -Message $ex.Message }
            finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
                if ($setStatus) { & $setStatus "Ready" }
            }
        }.GetNewClosure()

        Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label ("CopyWim:{0}" -f $mode)
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Start-ExportSelectedIndexAsync {
    if ($script:isBusy) { return }

    try {
        $mode = Get-ImagesViewMode
        if (-not $mode) { throw "Keine Ansicht ausgewählt." }

        $src = Get-ImagesPathForMode -Mode $mode
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Quelle nicht gefunden: $src" }

        $item = Get-SelectedWimItem
        if (-not $item) { throw "Bitte zuerst einen Index auswählen." }
        if ($item.PSObject.Properties.Match("Index").Count -eq 0) { throw "SelectedItem hat keinen Index." }

        $idx = [int]$item.Index

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = "WIM (*.wim)|*.wim|Alle Dateien (*.*)|*.*"
        $dlg.FileName = ("{0}_Index_{1}.wim" -f $mode, $idx)
        $dlg.OverwritePrompt = $true

        $ok = $dlg.ShowDialog()
        if ($ok -ne $true) { return }

        $dest = [string]$dlg.FileName
        if ([string]::IsNullOrWhiteSpace($dest)) { return }

        $ctxLocal  = $script:ctx
        $setStatus = $script:ctx.SetStatus
        $fnSetBusy = ${function:Set-ImagesBusy}

        & $fnSetBusy -Busy $true -Reason ("Index exportieren (Index {0})..." -f $idx) -Context $ctxLocal

        $safeSrc  = $src.Replace("'", "''")
        $safeDest = $dest.Replace("'", "''")

        $code = @'
$ErrorActionPreference = 'Stop'

$dism = Join-Path $env:WINDIR 'System32\dism.exe'
if (-not (Test-Path -LiteralPath $dism)) { $dism = 'dism.exe' }

$src  = '__SRC__'
$dest = '__DEST__'
$idx  = __IDX__

$srcArg  = ('/SourceImageFile:"{0}"' -f $src)
$destArg = ('/DestinationImageFile:"{0}"' -f $dest)

$args = @(
  '/English',
  '/Export-Image',
  $srcArg,
  ('/SourceIndex:{0}' -f $idx),
  $destArg,
  '/Compress:max',
  '/CheckIntegrity'
)

$out = & $dism @args 2>&1 | Out-String
$code = $LASTEXITCODE
if ($code -ne 0) {
  throw ("DISM Export-Image failed (ExitCode={0}).`n`n{1}" -f $code, $out)
}

[pscustomobject]@{ Destination = $dest; Index = $idx }
'@
        $code = $code.Replace("__SRC__", $safeSrc).Replace("__DEST__", $safeDest).Replace("__IDX__", [string]$idx)

        $onCompleted = {
            param($result)
            try {
                if ($setStatus) { & $setStatus ("Index exportiert: {0}" -f $dest) }
            } finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
            }
        }.GetNewClosure()

        $onError = {
            param($ex)
            try { Show-UiError -Message $ex.Message }
            finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
                if ($setStatus) { & $setStatus "Ready" }
            }
        }.GetNewClosure()

        Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label ("ExportIndex:{0}:{1}" -f $mode, $idx)
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}