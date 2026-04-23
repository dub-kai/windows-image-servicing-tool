Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath 'UI\UiHelpers.psm1' -MustExist) -Force
Import-Module (Resolve-ProjectPath 'UI\UiAsync.psm1' -MustExist) -Force

$script:ctx = $null
$script:composeItems = New-Object System.Collections.Generic.List[object]
$script:mediaBusy = $false

function Get-MediaAppStateValueSafe {
    param(
        [Parameter(Mandatory)][string]$Key,
        $Default = $null
    )

    try { return Get-AppStateValue -Key $Key -Default $Default } catch { return $Default }
}

function Set-MediaBusy {
    param(
        [Parameter(Mandatory)][bool]$Busy,
        [string]$Reason = $null
    )

    $script:mediaBusy = $Busy
    if (-not $script:ctx) { return }

    $targets = @(
        $script:ctx.BtnMediaPickInstallImage,
        $script:ctx.BtnMediaClearInstallImage,
        $script:ctx.BtnMediaPickBootImage,
        $script:ctx.BtnMediaClearBootImage,
        $script:ctx.BtnMediaBuildIso,
        $script:ctx.BtnMediaAddSourceImage,
        $script:ctx.BtnMediaRemoveSourceImage,
        $script:ctx.BtnMediaBuildInstallEsd,
        $script:ctx.LstMediaComposeItems
    ) | Where-Object { $_ -ne $null }

    foreach ($ctrl in $targets) {
        try { $ctrl.IsEnabled = (-not $Busy) } catch {}
    }

    if ($Busy -and $Reason -and $script:ctx.SetStatus) {
        try { & $script:ctx.SetStatus $Reason } catch {}
    }
}

function Get-MediaIsoRoot {
    $root = Get-MediaAppStateValueSafe -Key 'IsoRoot' -Default $null
    if ([string]::IsNullOrWhiteSpace([string]$root)) {
        $root = Get-MediaAppStateValueSafe -Key 'IsoRootPath' -Default $null
    }
    return $root
}

function Get-MediaIsoInstallDefault {
    return (Get-MediaAppStateValueSafe -Key 'IsoInstallImagePath' -Default $null)
}

function Get-MediaIsoBootDefault {
    $value = Get-MediaAppStateValueSafe -Key 'BootImagePath' -Default $null
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        $value = Get-MediaAppStateValueSafe -Key 'IsoBootPath' -Default $null
    }
    return $value
}

function Get-DisplayOrDash {
    param($Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '-' }
    return [string]$Value
}

function Refresh-MediaBuilderComposeList {
    if (-not $script:ctx) { return }

    $items = @($script:composeItems.ToArray())
    try {
        if ($script:ctx.LstMediaComposeItems) {
            $script:ctx.LstMediaComposeItems.ItemsSource = $null
            $script:ctx.LstMediaComposeItems.ItemsSource = $items
            $script:ctx.LstMediaComposeItems.Items.Refresh()
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaComposeSummary) {
            if ($items.Count -gt 0) {
                $script:ctx.TxtMediaComposeSummary.Text = ("{0} Image(s) vorgemerkt. Diese werden als gemeinsames install.esd exportiert." -f $items.Count)
            } else {
                $script:ctx.TxtMediaComposeSummary.Text = "Noch keine Quellimages vorgemerkt."
            }
        }
    } catch {}
}

function Refresh-MediaBuilderUI {
    if (-not $script:ctx) { return }

    $isoRoot = Get-MediaIsoRoot
    $installDefault = Get-MediaIsoInstallDefault
    $bootDefault = Get-MediaIsoBootDefault

    try { $script:ctx.TxtMediaSourceIso.Text = (Get-DisplayOrDash $isoRoot) } catch {}

    $effectiveInstall = $script:ctx.SelectedInstallImagePath
    if ([string]::IsNullOrWhiteSpace([string]$effectiveInstall)) { $effectiveInstall = $installDefault }
    $effectiveBoot = $script:ctx.SelectedBootImagePath
    if ([string]::IsNullOrWhiteSpace([string]$effectiveBoot)) { $effectiveBoot = $bootDefault }

    try { $script:ctx.TxtMediaInstallImage.Text = (Get-DisplayOrDash $effectiveInstall) } catch {}
    try { $script:ctx.TxtMediaBootImage.Text = (Get-DisplayOrDash $effectiveBoot) } catch {}

    try {
        if ($script:ctx.BtnMediaBuildIso) {
            $script:ctx.BtnMediaBuildIso.IsEnabled = ((-not $script:mediaBusy) -and (-not [string]::IsNullOrWhiteSpace([string]$isoRoot)))
        }
    } catch {}

    try {
        if ($script:ctx.BtnMediaBuildInstallEsd) {
            $script:ctx.BtnMediaBuildInstallEsd.IsEnabled = ((-not $script:mediaBusy) -and ($script:composeItems.Count -gt 0))
        }
    } catch {}

    try {
        if ($script:ctx.BtnMediaRemoveSourceImage -and $script:ctx.LstMediaComposeItems) {
            $script:ctx.BtnMediaRemoveSourceImage.IsEnabled = ((-not $script:mediaBusy) -and (@($script:ctx.LstMediaComposeItems.SelectedItems).Count -gt 0))
        }
    } catch {}

    Refresh-MediaBuilderComposeList
}

function Pick-MediaImageFile {
    param(
        [Parameter(Mandatory)][string]$Title
    )

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = $Title
    $dlg.Filter = 'Windows Images (*.wim;*.esd)|*.wim;*.esd|WIM (*.wim)|*.wim|ESD (*.esd)|*.esd|Alle Dateien (*.*)|*.*'
    $dlg.Multiselect = $false
    if ($dlg.ShowDialog() -ne $true) { return $null }
    return [string]$dlg.FileName
}

function Start-MediaBuildIsoAsync {
    if ($script:mediaBusy) { return }

    try {
        $sourceRoot = Get-MediaIsoRoot
        if ([string]::IsNullOrWhiteSpace([string]$sourceRoot)) {
            throw "Bitte zuerst eine Windows-ISO mounten. Der Media Builder nutzt diese als Basisquelle."
        }

        $installImagePath = $script:ctx.SelectedInstallImagePath
        if ([string]::IsNullOrWhiteSpace([string]$installImagePath)) {
            $installImagePath = Get-MediaIsoInstallDefault
        }

        $bootImagePath = $script:ctx.SelectedBootImagePath
        if ([string]::IsNullOrWhiteSpace([string]$bootImagePath)) {
            $bootImagePath = Get-MediaIsoBootDefault
        }

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'ISO speichern unter'
        $dlg.Filter = 'ISO (*.iso)|*.iso|Alle Dateien (*.*)|*.*'
        $dlg.DefaultExt = '.iso'
        $dlg.AddExtension = $true
        $dlg.OverwritePrompt = $true
        $dlg.FileName = ('windows-custom-{0}.iso' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        if ($dlg.ShowDialog() -ne $true) { return }

        $dest = [string]$dlg.FileName
        if ([string]::IsNullOrWhiteSpace($dest)) { return }

        Set-MediaBusy -Busy $true -Reason 'Media Builder: ISO wird gebaut...'

        $bootstrapPath = (Resolve-ProjectPath 'Core\Bootstrap.psm1' -MustExist).Replace("'", "''")
        $projectRoot = (Get-ProjectRoot).Replace("'", "''")
        $servicePath = (Resolve-ProjectPath 'Services\IsoBuildService.psm1' -MustExist).Replace("'", "''")
        $safeSource = $sourceRoot.Replace("'", "''")
        $safeDest = $dest.Replace("'", "''")
        $safeInstall = ([string]$installImagePath).Replace("'", "''")
        $safeBoot = ([string]$bootImagePath).Replace("'", "''")

        $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__BOOTSTRAP__' -Force
Set-ProjectRoot -Path '__PROJECTROOT__' | Out-Null
Import-Module '__SERVICE__' -Force

$params = @{
    SourceRoot = '__SOURCE__'
    OutputPath = '__DEST__'
}

$install = '__INSTALL__'
if (-not [string]::IsNullOrWhiteSpace($install)) { $params.InstallImagePath = $install }

$boot = '__BOOT__'
if (-not [string]::IsNullOrWhiteSpace($boot)) { $params.BootImagePath = $boot }

Build-WindowsIso @params
'@
        $code = $code.Replace('__BOOTSTRAP__', $bootstrapPath).
            Replace('__PROJECTROOT__', $projectRoot).
            Replace('__SERVICE__', $servicePath).
            Replace('__SOURCE__', $safeSource).
            Replace('__DEST__', $safeDest).
            Replace('__INSTALL__', $safeInstall).
            Replace('__BOOT__', $safeBoot)

        Start-UiTask -Label 'MediaBuilder:BuildIso' -Work ([scriptblock]::Create($code)) -OnCompleted {
            param($result)
            try {
                $item = @($result) | Select-Object -First 1
                if ($script:ctx.SetStatus -and $item) {
                    & $script:ctx.SetStatus ("Media Builder: ISO gebaut -> {0}" -f $item.OutputPath)
                }
            } finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
            }
        } -OnError {
            param($ex)
            try { Show-UiError -Message $ex.Message }
            finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
                if ($script:ctx.SetStatus) { & $script:ctx.SetStatus 'Ready' }
            }
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Add-MediaComposeSourceImage {
    try {
        $path = Pick-MediaImageFile -Title 'Quell-WIM/ESD für install.esd wählen'
        if ([string]::IsNullOrWhiteSpace([string]$path)) { return }

        $items = @(Get-WimImageList -ImagePath $path)
        if ($items.Count -lt 1) {
            throw "Im gewählten Image wurden keine exportierbaren Indexe gefunden."
        }

        foreach ($item in $items) {
            $script:composeItems.Add([pscustomobject]@{
                Path        = $path
                FileName    = [System.IO.Path]::GetFileName($path)
                Index       = [int]$item.Index
                Name        = [string]$item.Name
                Description = [string]$item.Description
            }) | Out-Null
        }

        if ($script:ctx.SetStatus) {
            & $script:ctx.SetStatus ("Media Builder: {0} Index(e) aus {1} vorgemerkt" -f $items.Count, $path)
        }
        Refresh-MediaBuilderUI
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Remove-MediaComposeSelectedItems {
    if (-not $script:ctx -or -not $script:ctx.LstMediaComposeItems) { return }

    $selected = @($script:ctx.LstMediaComposeItems.SelectedItems)
    if ($selected.Count -lt 1) { return }

    foreach ($item in $selected) {
        [void]$script:composeItems.Remove($item)
    }

    if ($script:ctx.SetStatus) {
        & $script:ctx.SetStatus ("Media Builder: {0} Eintrag/Einträge entfernt" -f $selected.Count)
    }
    Refresh-MediaBuilderUI
}

function Start-MediaBuildInstallEsdAsync {
    if ($script:mediaBusy) { return }
    if ($script:composeItems.Count -lt 1) { return }

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'install.esd speichern unter'
        $dlg.Filter = 'ESD (*.esd)|*.esd|WIM (*.wim)|*.wim|Alle Dateien (*.*)|*.*'
        $dlg.DefaultExt = '.esd'
        $dlg.AddExtension = $true
        $dlg.OverwritePrompt = $true
        $dlg.FileName = 'install.esd'
        if ($dlg.ShowDialog() -ne $true) { return }

        $dest = [string]$dlg.FileName
        if ([string]::IsNullOrWhiteSpace($dest)) { return }

        Set-MediaBusy -Busy $true -Reason 'Media Builder: install.esd wird gebaut...'

        $json = (@($script:composeItems.ToArray()) | ConvertTo-Json -Depth 5 -Compress).Replace("'", "''")
        $bootstrapPath = (Resolve-ProjectPath 'Core\Bootstrap.psm1' -MustExist).Replace("'", "''")
        $projectRoot = (Get-ProjectRoot).Replace("'", "''")
        $servicePath = (Resolve-ProjectPath 'Services\ImageCompositionService.psm1' -MustExist).Replace("'", "''")
        $safeDest = $dest.Replace("'", "''")

        $code = @'
$ErrorActionPreference = 'Stop'
Import-Module '__BOOTSTRAP__' -Force
Set-ProjectRoot -Path '__PROJECTROOT__' | Out-Null
Import-Module '__SERVICE__' -Force
$specs = ConvertFrom-Json '__JSON__'
Build-CombinedInstallImage -ImageSpecs @($specs) -OutputPath '__DEST__'
'@
        $code = $code.Replace('__BOOTSTRAP__', $bootstrapPath).
            Replace('__PROJECTROOT__', $projectRoot).
            Replace('__SERVICE__', $servicePath).
            Replace('__JSON__', $json).
            Replace('__DEST__', $safeDest)

        Start-UiTask -Label 'MediaBuilder:BuildInstallEsd' -TimeoutSec 14400 -Work ([scriptblock]::Create($code)) -OnCompleted {
            param($result)
            try {
                $item = @($result) | Select-Object -First 1
                if ($script:ctx.SetStatus -and $item) {
                    & $script:ctx.SetStatus ("Media Builder: install.esd gebaut -> {0}" -f $item.OutputPath)
                }
            } finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
            }
        } -OnError {
            param($ex)
            try { Show-UiError -Message $ex.Message }
            finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
                if ($script:ctx.SetStatus) { & $script:ctx.SetStatus 'Ready' }
            }
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Initialize-MediaBuilderController {
    param(
        [Parameter(Mandatory)]$MediaBuilderPage,
        [Parameter(Mandatory)][scriptblock]$SetStatus,
        [Parameter()][scriptblock]$OnStateChanged
    )

    $script:ctx = [ordered]@{
        Page                        = $MediaBuilderPage
        SetStatus                   = $SetStatus
        OnStateChanged              = $OnStateChanged
        SelectedInstallImagePath    = $null
        SelectedBootImagePath       = $null
        TxtMediaSourceIso           = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaSourceIso'
        TxtMediaInstallImage        = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaInstallImage'
        TxtMediaBootImage           = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaBootImage'
        BtnMediaPickInstallImage    = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaPickInstallImage'
        BtnMediaClearInstallImage   = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaClearInstallImage'
        BtnMediaPickBootImage       = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaPickBootImage'
        BtnMediaClearBootImage      = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaClearBootImage'
        BtnMediaBuildIso            = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaBuildIso'
        LstMediaComposeItems        = Find-Ui -Root $MediaBuilderPage -Name 'LstMediaComposeItems'
        TxtMediaComposeSummary      = Find-Ui -Root $MediaBuilderPage -Name 'TxtMediaComposeSummary'
        BtnMediaAddSourceImage      = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaAddSourceImage'
        BtnMediaRemoveSourceImage   = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaRemoveSourceImage'
        BtnMediaBuildInstallEsd     = Find-Ui -Root $MediaBuilderPage -Name 'BtnMediaBuildInstallEsd'
    }

    if ($script:ctx.BtnMediaPickInstallImage) {
        $script:ctx.BtnMediaPickInstallImage.Add_Click({
            $path = Pick-MediaImageFile -Title 'Install-Image auswählen'
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                $script:ctx.SelectedInstallImagePath = $path
                Refresh-MediaBuilderUI
            }
        })
    }

    if ($script:ctx.BtnMediaClearInstallImage) {
        $script:ctx.BtnMediaClearInstallImage.Add_Click({
            $script:ctx.SelectedInstallImagePath = $null
            Refresh-MediaBuilderUI
        })
    }

    if ($script:ctx.BtnMediaPickBootImage) {
        $script:ctx.BtnMediaPickBootImage.Add_Click({
            $path = Pick-MediaImageFile -Title 'boot.wim auswählen'
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                $script:ctx.SelectedBootImagePath = $path
                Refresh-MediaBuilderUI
            }
        })
    }

    if ($script:ctx.BtnMediaClearBootImage) {
        $script:ctx.BtnMediaClearBootImage.Add_Click({
            $script:ctx.SelectedBootImagePath = $null
            Refresh-MediaBuilderUI
        })
    }

    if ($script:ctx.BtnMediaBuildIso) {
        $script:ctx.BtnMediaBuildIso.Add_Click({ Start-MediaBuildIsoAsync })
    }

    if ($script:ctx.BtnMediaAddSourceImage) {
        $script:ctx.BtnMediaAddSourceImage.Add_Click({ Add-MediaComposeSourceImage })
    }

    if ($script:ctx.BtnMediaRemoveSourceImage) {
        $script:ctx.BtnMediaRemoveSourceImage.Add_Click({ Remove-MediaComposeSelectedItems })
    }

    if ($script:ctx.BtnMediaBuildInstallEsd) {
        $script:ctx.BtnMediaBuildInstallEsd.Add_Click({ Start-MediaBuildInstallEsdAsync })
    }

    if ($script:ctx.LstMediaComposeItems) {
        $script:ctx.LstMediaComposeItems.Add_SelectionChanged({ Refresh-MediaBuilderUI })
    }

    if ($MediaBuilderPage) {
        $MediaBuilderPage.Add_Loaded({ Refresh-MediaBuilderUI })
    }

    Refresh-MediaBuilderUI
}

Export-ModuleMember -Function Initialize-MediaBuilderController, Refresh-MediaBuilderUI
