function Try-AutoDetectIso_Local {
    param([switch]$Quiet)

    try {
        # Nur fürs Logging
        $roots = @(Get-MountedIsoRoots)
        try { Write-Log -Level INFO -Message ("AutoDetect: CDRom Roots={0}" -f $roots.Count) -ToConsole } catch {}

        $hits = @(Find-MountedWindowsInstallMedia)
        try { Write-Log -Level INFO -Message ("AutoDetect: Kandidaten={0}" -f $hits.Count) -ToConsole } catch {}

        if ($hits.Count -lt 1) {
            if (-not $Quiet) { Show-UiInfo -Message "Kein gemountetes Windows-Installmedium gefunden." }
            return $false
        }

        $best = $hits | Sort-Object -Property Score -Descending | Select-Object -First 1

        try { Set-AppStateValue -Key "IsoRoot" -Value $best.Root } catch {}
        try { Set-AppStateValue -Key "IsoRootPath" -Value $best.Root } catch {}
        try { Set-AppStateValue -Key "IsoInstallImagePath" -Value $best.Install } catch {}
        try { Set-AppStateValue -Key "BootImagePath" -Value $best.Boot } catch {}

        try {
            Write-Log -Level INFO -Message ("AutoDetect gewählt: Root={0}; Boot={1}; Install={2}" -f $best.Root, $best.Boot, $best.Install) -ToConsole
        } catch {}

        return $true
    } catch {
        if (-not $Quiet) { Show-UiError -Message $_.Exception.Message }
        return $false
    }
}