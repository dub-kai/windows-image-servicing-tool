Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# File-Dialog (WPF)
try { Add-Type -AssemblyName PresentationFramework | Out-Null } catch {}

function Select-ImageFile {
    [CmdletBinding()]
    param()

    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "WIM/ESD auswählen"
    $dlg.Filter = "Windows Images (*.wim;*.esd)|*.wim;*.esd|WIM (*.wim)|*.wim|ESD (*.esd)|*.esd|Alle Dateien (*.*)|*.*"
    $dlg.Multiselect = $false

    $ok = $dlg.ShowDialog()
    if ($ok) {
        $path = $dlg.FileName
        try { Write-Log -Level INFO -Message ("Image gewählt: {0}" -f $path) } catch {}
        return $path
    }

    return $null
}

Export-ModuleMember -Function Select-ImageFile