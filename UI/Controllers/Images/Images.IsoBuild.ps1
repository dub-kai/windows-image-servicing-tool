Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ImagesIsoSourceRoot {
    $root = $null

    try { $root = Get-AppStateValue -Key 'IsoRoot' -Default $null } catch { $root = $null }
    if ([string]::IsNullOrWhiteSpace([string]$root)) {
        try { $root = Get-AppStateValue -Key 'IsoRootPath' -Default $null } catch { $root = $null }
    }
    if ([string]::IsNullOrWhiteSpace([string]$root) -and $script:ctx) {
        try { $root = $script:ctx.IsoRoot } catch { $root = $null }
    }

    if ([string]::IsNullOrWhiteSpace([string]$root)) {
        return $null
    }

    return (Normalize-PathText $root)
}

function Get-ImagesIsoBuildPlan {
    $sourceRoot = Get-ImagesIsoSourceRoot
    if ([string]::IsNullOrWhiteSpace([string]$sourceRoot)) {
        throw "Bitte zuerst eine Windows-ISO mounten, damit eine Quelle für den ISO-Build vorhanden ist."
    }

    $mode = $null
    try { $mode = Get-ImagesViewMode } catch { $mode = $null }

    $installPath = $null
    if ($mode -eq 'Standalone') {
        try { $installPath = Get-ImagesPathForMode -Mode 'Standalone' } catch { $installPath = $null }
    } else {
        try { $installPath = Get-AppStateValue -Key 'IsoInstallImagePath' -Default $null } catch { $installPath = $null }
        if ([string]::IsNullOrWhiteSpace([string]$installPath) -and $script:ctx) {
            try { $installPath = $script:ctx.IsoInstallPath } catch { $installPath = $null }
        }
    }

    $bootPath = $null
    try { $bootPath = Get-AppStateValue -Key 'BootImagePath' -Default $null } catch { $bootPath = $null }
    if ([string]::IsNullOrWhiteSpace([string]$bootPath)) {
        try { $bootPath = Get-AppStateValue -Key 'IsoBootPath' -Default $null } catch { $bootPath = $null }
    }
    if ([string]::IsNullOrWhiteSpace([string]$bootPath) -and $script:ctx) {
        try { $bootPath = $script:ctx.IsoBootPath } catch { $bootPath = $null }
    }

    return [pscustomobject]@{
        SourceRoot       = $sourceRoot
        InstallImagePath = $installPath
        BootImagePath    = $bootPath
        Mode             = $mode
    }
}

function Update-IsoBuildUi {
    if (-not $script:ctx -or -not $script:ctx.BtnBuildIso) { return }

    $enabled = $false
    try {
        $sourceRoot = Get-ImagesIsoSourceRoot
        $enabled = (-not [string]::IsNullOrWhiteSpace([string]$sourceRoot)) -and (-not $script:isBusy)
    } catch {
        $enabled = $false
    }

    try { $script:ctx.BtnBuildIso.IsEnabled = $enabled } catch {}
}

function Start-BuildIsoAsync {
    if ($script:isBusy) { return }

    try {
        $plan = Get-ImagesIsoBuildPlan

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'ISO speichern unter'
        $dlg.Filter = 'ISO (*.iso)|*.iso|Alle Dateien (*.*)|*.*'
        $dlg.DefaultExt = '.iso'
        $dlg.AddExtension = $true
        $dlg.OverwritePrompt = $true
        $dlg.FileName = ('windows-custom-{0}.iso' -f (Get-Date -Format 'yyyyMMdd-HHmm'))

        $ok = $dlg.ShowDialog()
        if ($ok -ne $true) { return }

        $dest = [string]$dlg.FileName
        if ([string]::IsNullOrWhiteSpace($dest)) { return }

        $ctxLocal  = $script:ctx
        $setStatus = $script:ctx.SetStatus
        $fnSetBusy = ${function:Set-ImagesBusy}

        & $fnSetBusy -Busy $true -Reason 'ISO wird mit ADK/oscdimg gebaut...' -Context $ctxLocal

        $projectRoot = Resolve-ProjectPath '.'
        $bootstrapPath = (Resolve-ProjectPath 'Core\Bootstrap.psm1' -MustExist).Replace("'", "''")
        $isoBuildServicePath = (Resolve-ProjectPath 'Services\IsoBuildService.psm1' -MustExist).Replace("'", "''")
        $safeProjectRoot = $projectRoot.Replace("'", "''")
        $safeSourceRoot = $plan.SourceRoot.Replace("'", "''")
        $safeDest = $dest.Replace("'", "''")
        $safeInstall = ([string]$plan.InstallImagePath).Replace("'", "''")
        $safeBoot = ([string]$plan.BootImagePath).Replace("'", "''")

        $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__BOOTSTRAP__' -Force
Set-ProjectRoot -Path '__PROJECTROOT__' | Out-Null
Import-Module '__SERVICE__' -Force

$install = '__INSTALL__'
if ([string]::IsNullOrWhiteSpace($install)) { $install = $null }

$boot = '__BOOT__'
if ([string]::IsNullOrWhiteSpace($boot)) { $boot = $null }

Build-WindowsIso -SourceRoot '__SOURCE__' -OutputPath '__DEST__' -InstallImagePath $install -BootImagePath $boot
'@
        $code = $code.Replace('__BOOTSTRAP__', $bootstrapPath).
            Replace('__PROJECTROOT__', $safeProjectRoot).
            Replace('__SERVICE__', $isoBuildServicePath).
            Replace('__SOURCE__', $safeSourceRoot).
            Replace('__DEST__', $safeDest).
            Replace('__INSTALL__', $safeInstall).
            Replace('__BOOT__', $safeBoot)

        $onCompleted = {
            param($result)
            try {
                $info = @($result) | Select-Object -First 1
                if ($setStatus -and $info) {
                    & $setStatus ("ISO gebaut: {0}" -f $info.OutputPath)
                }
            } finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
                Update-IsoBuildUi
            }
        }.GetNewClosure()

        $onError = {
            param($ex)
            try { Show-UiError -Message $ex.Message }
            finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
                Update-IsoBuildUi
                if ($setStatus) { & $setStatus 'Ready' }
            }
        }.GetNewClosure()

        Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label 'BuildIso'
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}
