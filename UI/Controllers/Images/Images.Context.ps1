Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:imagesInitialMountedRefreshDone = $false
$script:isSyncingImagesView = $false

function Get-ImagesAppStateValueSafe {
    param(
        [Parameter(Mandatory)][string]$Key,
        $Default = $null
    )

    $cmd = Get-Command Get-AppStateValue -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            return Get-AppStateValue -Key $Key -Default $Default
        } catch {}
    }

    return $Default
}

function Set-ImagesAppStateValueSafe {
    param(
        [Parameter(Mandatory)][string]$Key,
        $Value
    )

    $cmd = Get-Command Set-AppStateValue -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            Set-AppStateValue -Key $Key -Value $Value
            return
        } catch {}
    }
}

function Resolve-StandaloneImagePath {
    $p = $null

    try { $p = Get-ImagesAppStateValueSafe -Key 'StandaloneImagePath' -Default $null } catch { $p = $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$p)) { return $p }

    try { $p = Get-ImagesAppStateValueSafe -Key 'SelectedImagePath' -Default $null } catch { $p = $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$p)) { return $p }

    try { $p = Get-ImagesAppStateValueSafe -Key 'ImagePath' -Default $null } catch { $p = $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$p)) { return $p }

    return $null
}

function Get-ImagesAutoDetectedMedia {
    $root    = $null
    $boot    = $null
    $install = $null

    $cmd = Get-Command Get-AutoDetectedInstallMedia -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            $media = Get-AutoDetectedInstallMedia
            if ($media) {
                if ($media.PSObject.Properties.Match('Root').Count -gt 0)        { $root    = $media.Root }
                if ($media.PSObject.Properties.Match('BootPath').Count -gt 0)    { $boot    = $media.BootPath }
                if ($media.PSObject.Properties.Match('InstallPath').Count -gt 0) { $install = $media.InstallPath }
            }
        } catch {}
    }

    if (-not $root)    { $root    = Get-ImagesAppStateValueSafe -Key 'IsoRoot' -Default $null }
    if (-not $boot)    { $boot    = Get-ImagesAppStateValueSafe -Key 'IsoBootPath' -Default $null }
    if (-not $install) { $install = Get-ImagesAppStateValueSafe -Key 'IsoInstallPath' -Default $null }

    return [pscustomobject]@{
        Root        = $root
        BootPath    = $boot
        InstallPath = $install
    }
}

function Pick-StandaloneImage {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'WIM/ESD auswählen'
    $dlg.Filter = 'Windows Images (*.wim;*.esd)|*.wim;*.esd|WIM (*.wim)|*.wim|ESD (*.esd)|*.esd|Alle Dateien (*.*)|*.*'
    $dlg.Multiselect = $false
    $dlg.CheckFileExists = $true
    $dlg.CheckPathExists = $true
    $dlg.RestoreDirectory = $true

    $lastDir = Get-ImagesAppStateValueSafe -Key 'StandaloneLastDir' -Default $null
    if ($lastDir -and (Test-Path -LiteralPath $lastDir)) {
        try { $dlg.InitialDirectory = $lastDir } catch {}
    }

    $result = $dlg.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $path = $dlg.FileName
    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }

    $resolved = $path
    try {
        $resolved = (Resolve-Path -LiteralPath $path).Path
    } catch {}

    Set-ImagesAppStateValueSafe -Key 'StandaloneImagePath' -Value $resolved
    Set-ImagesAppStateValueSafe -Key 'SelectedImagePath'   -Value $resolved

    try {
        $parent = Split-Path -LiteralPath $resolved -Parent
        if ($parent) {
            Set-ImagesAppStateValueSafe -Key 'StandaloneLastDir' -Value $parent
        }
    } catch {}

    try {
        Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value 'Standalone'
    } catch {}

    if ($script:ctx) {
        try {
            $script:ctx.StandalonePath = $resolved
        } catch {}

        try {
            if ($script:ctx.TxtStandalone) {
                $script:ctx.TxtStandalone.Text = $resolved
            }
        } catch {}

        try {
            Set-ImagesComboByMode -Mode 'Standalone'
        } catch {}

        try {
            Refresh-ImagesUI
        } catch {}

        try {
            Show-ImagesIndexes -ForceReload
        } catch {}
    }

    try {
        if ($script:ctx -and $script:ctx.SetStatus) {
            & $script:ctx.SetStatus ("Image gewählt: {0}" -f $resolved)
        }
    } catch {}
}

function Clear-StandaloneImage {
    Set-ImagesAppStateValueSafe -Key 'StandaloneImagePath' -Value $null

    if ($script:ctx) {
        try {
            $script:ctx.StandalonePath = $null
        } catch {}

        try {
            if ($script:ctx.TxtStandalone) {
                $script:ctx.TxtStandalone.Text = '-'
            }
        } catch {}
    }

    try {
        if ($script:ctx -and $script:ctx.SetStatus) {
            & $script:ctx.SetStatus 'Standalone WIM/ESD entfernt.'
        }
    } catch {}
}

function Sync-ImagesSelectedIndexText {
    if (-not $script:ctx) { return }

    $txt = $script:ctx.TxtSelectedIndex
    if (-not $txt) { return }

    $value = '-'

    try {
        $item = $script:ctx.LstWimImages.SelectedItem
        if ($item) {
            if ($item.PSObject.Properties.Match('Index').Count -gt 0) {
                $idx = [string]$item.Index
                if (-not [string]::IsNullOrWhiteSpace($idx)) {
                    $value = $idx
                }
            }
        }
    } catch {}

    try { $txt.Text = $value } catch {}
}

function Get-ImagesModeFromComboSelection {
    if (-not $script:ctx -or -not $script:ctx.CmbView) { return $null }

    try {
        $sel = $script:ctx.CmbView.SelectedItem
        if (-not $sel) { return $null }

        if ($sel -is [System.Windows.Controls.ComboBoxItem]) {
            $name = [string]$sel.Name
            switch ($name) {
                'CmbItemIsoInstall' { return 'IsoInstall' }
                'CmbItemIsoBoot'    { return 'IsoBoot' }
                'CmbItemStandalone' { return 'Standalone' }
            }

            $content = [string]$sel.Content
            switch -Regex ($content) {
                '^ISO Install$' { return 'IsoInstall' }
                '^ISO Boot$'    { return 'IsoBoot' }
                '^Standalone$'  { return 'Standalone' }
            }
        }

        $text = [string]$sel.ToString()
        switch -Regex ($text) {
            'IsoInstall' { return 'IsoInstall' }
            'IsoBoot'    { return 'IsoBoot' }
            'Standalone' { return 'Standalone' }
        }
    } catch {}

    return $null
}

function Set-ImagesComboByMode {
    param(
        [Parameter(Mandatory)][string]$Mode
    )

    if (-not $script:ctx) { return }
    if (-not $script:ctx.CmbView) { return }

    $target = $null
    switch ($Mode) {
        'IsoInstall' { $target = $script:ctx.CmbItemIsoInstall }
        'IsoBoot'    { $target = $script:ctx.CmbItemIsoBoot }
        'Standalone' { $target = $script:ctx.CmbItemStandalone }
        default      { $target = $null }
    }

    $script:isSyncingImagesView = $true
    try {
        if ($target) {
            try {
                $script:ctx.CmbView.SelectedItem = $target
                return
            } catch {}
        }

        try {
            switch ($Mode) {
                'IsoInstall' { $script:ctx.CmbView.SelectedIndex = 0 }
                'IsoBoot'    { $script:ctx.CmbView.SelectedIndex = 1 }
                'Standalone' { $script:ctx.CmbView.SelectedIndex = 2 }
                default      { $script:ctx.CmbView.SelectedIndex = -1 }
            }
        } catch {}
    } finally {
        $script:isSyncingImagesView = $false
    }
}

function Initialize-ImagesController {
    param(
        [Parameter(Mandatory)] $Page,
        [Parameter(Mandatory)] [scriptblock] $SetStatus,
        [Parameter()] [scriptblock] $OnStateChanged
    )

    $script:imagesInitialMountedRefreshDone = $false
    $script:isSyncingImagesView = $false

    $media = Get-ImagesAutoDetectedMedia
    $standalonePath = Resolve-StandaloneImagePath

    $script:ctx = [ordered]@{
        Page                     = $Page
        ImagesPage               = $Page
        PageImages               = $Page
        Root                     = $Page

        SetStatus                = $SetStatus
        OnStateChanged           = $OnStateChanged

        TxtIsoInstall            = Find-Ui -Root $Page -Name 'TxtIsoInstall'
        TxtIsoBoot               = Find-Ui -Root $Page -Name 'TxtIsoBoot'
        TxtStandalone            = Find-Ui -Root $Page -Name 'TxtStandalone'

        BtnPickStandalone        = Find-Ui -Root $Page -Name 'BtnPickStandalone'
        BtnClearStandalone       = Find-Ui -Root $Page -Name 'BtnClearStandalone'

        CmbView                  = Find-Ui -Root $Page -Name 'CmbView'
        CmbItemIsoInstall        = Find-Ui -Root $Page -Name 'CmbItemIsoInstall'
        CmbItemIsoBoot           = Find-Ui -Root $Page -Name 'CmbItemIsoBoot'
        CmbItemStandalone        = Find-Ui -Root $Page -Name 'CmbItemStandalone'

        BtnLoadWimIndexes        = Find-Ui -Root $Page -Name 'BtnLoadWimIndexes'
        TxtWimSourceUsed         = Find-Ui -Root $Page -Name 'TxtWimSourceUsed'
        TxtSourceUsed            = Find-Ui -Root $Page -Name 'TxtWimSourceUsed'

        BtnMountSelected         = Find-Ui -Root $Page -Name 'BtnMountSelected'
        BtnSaveSourceWim         = Find-Ui -Root $Page -Name 'BtnSaveSourceWim'
        BtnExportSelectedIndex   = Find-Ui -Root $Page -Name 'BtnExportSelectedIndex'

        TxtSelectedIndex         = Find-Ui -Root $Page -Name 'TxtSelectedIndex'
        ChkMountReadOnly         = Find-Ui -Root $Page -Name 'ChkMountReadOnly'
        ChkReadOnly              = Find-Ui -Root $Page -Name 'ChkMountReadOnly'
        TxtMountDir              = Find-Ui -Root $Page -Name 'TxtMountDir'

        LstWimImages             = Find-Ui -Root $Page -Name 'LstWimImages'

        BtnRefreshMounted        = Find-Ui -Root $Page -Name 'BtnRefreshMounted'
        BtnUnmountMountedCommit  = Find-Ui -Root $Page -Name 'BtnUnmountMountedCommit'
        BtnUnmountMountedDiscard = Find-Ui -Root $Page -Name 'BtnUnmountMountedDiscard'
        BtnRepairMounts          = Find-Ui -Root $Page -Name 'BtnRepairMounts'
        TxtMountedHint           = Find-Ui -Root $Page -Name 'TxtMountedHint'
        LstMountedWims           = Find-Ui -Root $Page -Name 'LstMountedWims'

        BusyOverlay              = Find-Ui -Root $Page -Name 'BusyOverlay'
        TxtBusyMessage           = Find-Ui -Root $Page -Name 'TxtBusyMessage'

        IsoRoot                  = $media.Root
        IsoBootPath              = $media.BootPath
        IsoInstallPath           = $media.InstallPath
        StandalonePath           = $standalonePath
    }

    if (-not $script:ctx.CmbView)                  { throw "CmbView nicht gefunden." }
    if (-not $script:ctx.BtnLoadWimIndexes)        { throw "BtnLoadWimIndexes nicht gefunden." }
    if (-not $script:ctx.LstWimImages)             { throw "LstWimImages nicht gefunden." }
    if (-not $script:ctx.LstMountedWims)           { throw "LstMountedWims nicht gefunden." }
    if (-not $script:ctx.BtnMountSelected)         { throw "BtnMountSelected nicht gefunden." }
    if (-not $script:ctx.BtnRefreshMounted)        { throw "BtnRefreshMounted nicht gefunden." }

    Write-Log -Level INFO -Message ("Images UI wires: CmbView={0} BtnLoad={1} LstWimImages={2} LstMountedWims={3} BtnMountSelected={4} BtnRefreshMounted={5}" -f
        [bool]($script:ctx.CmbView),
        [bool]($script:ctx.BtnLoadWimIndexes),
        [bool]($script:ctx.LstWimImages),
        [bool]($script:ctx.LstMountedWims),
        [bool]($script:ctx.BtnMountSelected),
        [bool]($script:ctx.BtnRefreshMounted)
    )

    if ($script:ctx.ChkMountReadOnly) {
        try {
            $script:ctx.ChkMountReadOnly.IsChecked = [bool](Get-ConfigValue -Key 'ImageMountReadOnlyDefault' -Default $true)
        } catch {}
    }

    try {
        if ($script:ctx.TxtIsoInstall) {
            $script:ctx.TxtIsoInstall.Text = $(if ($script:ctx.IsoInstallPath) { [string]$script:ctx.IsoInstallPath } else { '-' })
        }
    } catch {}

    try {
        if ($script:ctx.TxtIsoBoot) {
            $script:ctx.TxtIsoBoot.Text = $(if ($script:ctx.IsoBootPath) { [string]$script:ctx.IsoBootPath } else { '-' })
        }
    } catch {}

    try {
        if ($script:ctx.TxtStandalone) {
            $script:ctx.TxtStandalone.Text = $(if ($script:ctx.StandalonePath) { [string]$script:ctx.StandalonePath } else { '-' })
        }
    } catch {}

    if ($script:ctx.BtnPickStandalone) {
        $script:ctx.BtnPickStandalone.Add_Click({
            try {
                Pick-StandaloneImage
                $script:ctx.StandalonePath = Resolve-StandaloneImagePath
                Refresh-ImagesUI
                Show-ImagesIndexes -ForceReload
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnClearStandalone) {
        $script:ctx.BtnClearStandalone.Add_Click({
            try {
                Clear-StandaloneImage
                $script:ctx.StandalonePath = $null
                Refresh-ImagesUI
                Show-ImagesIndexes
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.CmbView) {
        $script:ctx.CmbView.Add_SelectionChanged({
            try {
                if ($script:isSyncingImagesView) { return }

                $mode = Get-ImagesModeFromComboSelection
                try { Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value $mode } catch {}

                Show-ImagesIndexes
                Sync-ImagesSelectedIndexText
                Update-MountUiFromState
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnLoadWimIndexes) {
        $script:ctx.BtnLoadWimIndexes.Add_Click({
            try {
                Show-ImagesIndexes -ForceReload
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.LstWimImages) {
        $script:ctx.LstWimImages.Add_SelectionChanged({
            try {
                Sync-ImagesSelectedIndexText
                Update-MountUiFromState
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.ChkMountReadOnly) {
        $script:ctx.ChkMountReadOnly.Add_Checked({
            try {
                Set-ConfigValue -Key 'ImageMountReadOnlyDefault' -Value ([bool]$script:ctx.ChkMountReadOnly.IsChecked) -Persist | Out-Null
                Update-MountUiFromState
            } catch {}
        })
        $script:ctx.ChkMountReadOnly.Add_Unchecked({
            try {
                Set-ConfigValue -Key 'ImageMountReadOnlyDefault' -Value ([bool]$script:ctx.ChkMountReadOnly.IsChecked) -Persist | Out-Null
                Update-MountUiFromState
            } catch {}
        })
    }

    if ($script:ctx.BtnMountSelected) {
        $script:ctx.BtnMountSelected.Add_Click({
            try {
                Start-MountAsync
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSaveSourceWim) {
        $script:ctx.BtnSaveSourceWim.Add_Click({
            try {
                Save-SourceWimAsync
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnExportSelectedIndex) {
        $script:ctx.BtnExportSelectedIndex.Add_Click({
            try {
                Export-SelectedIndexAsync
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnRefreshMounted) {
        $script:ctx.BtnRefreshMounted.Add_Click({
            try {
                Refresh-MountedList
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.LstMountedWims) {
        $script:ctx.LstMountedWims.Add_SelectionChanged({
            try {
                Update-MountedButtons
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnUnmountMountedCommit) {
        $script:ctx.BtnUnmountMountedCommit.Add_Click({
            try {
                Unmount-MountedSelectedCommit
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnUnmountMountedDiscard) {
        $script:ctx.BtnUnmountMountedDiscard.Add_Click({
            try {
                Unmount-MountedSelectedDiscard
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnRepairMounts) {
        $script:ctx.BtnRepairMounts.Add_Click({
            try {
                Start-MountRepairAssistant
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

if ($Page) {
    $Page.Add_Loaded({
        try {
            $script:ctx.StandalonePath = Resolve-StandaloneImagePath

            try {
                if ($script:ctx.TxtStandalone) {
                    $script:ctx.TxtStandalone.Text = $(if ($script:ctx.StandalonePath) { [string]$script:ctx.StandalonePath } else { '-' })
                }
            } catch {}

            Refresh-ImagesUI

            $mode = $null
            try { $mode = Get-ImagesViewMode } catch { $mode = $null }

            if (-not $mode -and $script:ctx.StandalonePath) {
                try {
                    Set-ImagesComboByMode -Mode 'Standalone'
                    Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value 'Standalone'
                    $mode = 'Standalone'
                } catch {}
            }

            if ($mode) {
                Show-ImagesIndexes
            }

            if (-not $script:imagesInitialMountedRefreshDone) {
                $script:imagesInitialMountedRefreshDone = $true
                Refresh-MountedList
            }
        } catch {
            Show-UiError -Message $_.Exception.Message
        }
    })
}

    $savedMode = $null
    try {
        $savedMode = Get-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Default $null
    } catch {
        $savedMode = $null
    }

    $hasIsoInstall = [bool]$script:ctx.IsoInstallPath
    $hasIsoBoot    = [bool]$script:ctx.IsoBootPath
    $hasStandalone = [bool]$script:ctx.StandalonePath

    $effectiveMode = $null
    if ($savedMode -eq 'IsoInstall' -and $hasIsoInstall) { $effectiveMode = 'IsoInstall' }
    elseif ($savedMode -eq 'IsoBoot' -and $hasIsoBoot) { $effectiveMode = 'IsoBoot' }
    elseif ($savedMode -eq 'Standalone' -and $hasStandalone) { $effectiveMode = 'Standalone' }
    elseif ($hasIsoInstall) { $effectiveMode = 'IsoInstall' }
    elseif ($hasIsoBoot) { $effectiveMode = 'IsoBoot' }
    elseif ($hasStandalone) { $effectiveMode = 'Standalone' }

    try {
        if ($effectiveMode) {
            Set-ImagesComboByMode -Mode $effectiveMode
            try { Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value $effectiveMode } catch {}
        } else {
            $script:isSyncingImagesView = $true
            try {
                $script:ctx.CmbView.SelectedIndex = -1
            } finally {
                $script:isSyncingImagesView = $false
            }
            try { Set-ImagesAppStateValueSafe -Key 'ImagesViewMode' -Value $null } catch {}
        }
    } catch {
        try { $script:ctx.CmbView.SelectedIndex = -1 } catch {}
    }

    try {
        Sync-ImagesSelectedIndexText
    } catch {}

    try {
        Refresh-ImagesUI
    } catch {
        Show-UiError -Message $_.Exception.Message
    }

    try {
        $script:ctx.StandalonePath = Resolve-StandaloneImagePath
        $mode = $null
        try { $mode = Get-ImagesViewMode } catch { $mode = $null }
        if ($mode) {
            Show-ImagesIndexes
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }

    try {
        Refresh-MountedList
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}
