function Select-DriverSourceFolder {
    param(
        [string]$Description = "Treiber-Ordner auswählen (enthält .inf Dateien)"
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null

        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Description

        $ok = $dlg.ShowDialog()
        if ($ok -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

        $folder = [string]$dlg.SelectedPath
        if ([string]::IsNullOrWhiteSpace($folder)) { return $null }

        return $folder
    }
    catch {
        throw $_.Exception
    }
}

function Confirm-DriverRemoval {
    param(
        [Parameter(Mandatory)][string[]]$PublishedNames
    )

    if (-not $PublishedNames -or $PublishedNames.Count -lt 1) { return $false }

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null

        $preview = @($PublishedNames | Select-Object -First 12)
        $msg = "Treiber wirklich entfernen?`n`n" + ($preview -join "`n")

        if ($PublishedNames.Count -gt $preview.Count) {
            $rest = $PublishedNames.Count - $preview.Count
            $msg += "`n`n... und {0} weitere" -f $rest
        }

        $res = [System.Windows.MessageBox]::Show(
            $msg,
            "Confirm Remove-Driver",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )

        return ($res -eq [System.Windows.MessageBoxResult]::Yes)
    }
    catch {
        throw $_.Exception
    }
}