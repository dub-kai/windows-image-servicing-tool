Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Resolve-ProjectPath "UI\UiHelpers.psm1" -MustExist) -Force

$script:ctx = $null

function Refresh-SettingsUI {
    if (-not $script:ctx) { return }

    try {
        if ($script:ctx.TxtSettingsMountRoot) {
            try {
                $mr = Get-MountRoot
                $script:ctx.TxtSettingsMountRoot.Text = ("MountRoot: {0}" -f (Get-DisplayValue $mr))
            } catch {
                $script:ctx.TxtSettingsMountRoot.Text = "MountRoot: -"
            }
        }

        if ($script:ctx.TxtSettingsProjectRoot) {
            try { $script:ctx.TxtSettingsProjectRoot.Text = (Get-DisplayValue (Get-ProjectRoot)) } catch { $script:ctx.TxtSettingsProjectRoot.Text = "-" }
        }

        if ($script:ctx.TxtSettingsLogFile) {
            try {
                if (Get-Command Get-LogFilePath -ErrorAction SilentlyContinue) {
                    $script:ctx.TxtSettingsLogFile.Text = (Get-DisplayValue (Get-LogFilePath))
                } else {
                    $script:ctx.TxtSettingsLogFile.Text = "-"
                }
            } catch {
                $script:ctx.TxtSettingsLogFile.Text = "-"
            }
        }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Initialize-SettingsController {
    param(
        [Parameter(Mandatory)] $SettingsPage,
        [Parameter(Mandatory)] [scriptblock] $SetStatus,
        [Parameter()] [scriptblock] $OnStateChanged = $null
    )

    $script:ctx = @{
        SettingsPage = $SettingsPage
        SetStatus    = $SetStatus
        OnStateChanged = $OnStateChanged

        TxtSettingsMountRoot   = $null
        BtnSettingsPickMountRoot  = $null
        BtnSettingsResetMountRoot = $null

        TxtSettingsProjectRoot = $null
        TxtSettingsLogFile     = $null
    }

    $p = $SettingsPage

    $script:ctx.TxtSettingsMountRoot      = Find-Ui -Root $p -Name "TxtSettingsMountRoot"
    $script:ctx.BtnSettingsPickMountRoot  = Find-Ui -Root $p -Name "BtnSettingsPickMountRoot"
    $script:ctx.BtnSettingsResetMountRoot = Find-Ui -Root $p -Name "BtnSettingsResetMountRoot"

    $script:ctx.TxtSettingsProjectRoot = Find-Ui -Root $p -Name "TxtSettingsProjectRoot"
    $script:ctx.TxtSettingsLogFile     = Find-Ui -Root $p -Name "TxtSettingsLogFile"

    if ($script:ctx.BtnSettingsPickMountRoot) {
        $script:ctx.BtnSettingsPickMountRoot.Add_Click({
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = "MountRoot wählen (lokal, NTFS empfohlen)"

                $cur = $null
                try { $cur = Get-AppStateValue -Key "MountRoot" -Default $null } catch {}
                if ($cur) { $dlg.SelectedPath = $cur }

                $ok = $dlg.ShowDialog()
                if ($ok -ne [System.Windows.Forms.DialogResult]::OK) { return }

                Set-MountRoot -Path $dlg.SelectedPath -Persist | Out-Null

                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus "Settings: MountRoot gesetzt" } catch {} }
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    if ($script:ctx.BtnSettingsResetMountRoot) {
        $script:ctx.BtnSettingsResetMountRoot.Add_Click({
            try {
                try { Set-AppStateValue -Key "MountRoot" -Value $null } catch {}
                try { Set-ConfigValue -Key "MountRoot" -Value $null } catch {}
                Refresh-SettingsUI
                if ($script:ctx.OnStateChanged) { try { & $script:ctx.OnStateChanged } catch {} }
                if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus "Settings: MountRoot reset" } catch {} }
            } catch {
                Show-UiError -Message $_.Exception.Message
            }
        })
    }

    Refresh-SettingsUI
}

Export-ModuleMember -Function Initialize-SettingsController, Refresh-SettingsUI
