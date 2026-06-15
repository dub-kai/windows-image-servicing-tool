# Release Package Check

## Startdateien

- `Start-WinImageAdmin.wsf`
- `UI\MainWindow.xaml`
- `UI\Pages\*.xaml`
- `Core\*.psm1`
- `Services\*.psm1`
- `UI\Controllers\*.psm1`
- `UI\Controllers\**\*.ps1`

## Arbeitsordner

- `Work\Temp`
- `Work\Mounts`
- `Work\Logs`
- `Config`

## Vor Paketierung pruefen

- Keine Testartefakte ins Release-Paket kopieren, ausser `Tests` wird bewusst als Diagnosepaket mitgegeben.
- `Docs\ReleaseStatus.md` aktualisieren.
- `Docs\KnownIssues.md` aktuell halten.
- Sichtbare Build-Anzeige pruefen: `v1.0 RC (Workflow Polish)`.
- Erststart ohne vorhandene AppState/Config-Dateien pruefen.

## Noch offen nach V1.0

- Installer oder MSIX.
- Signierte Skripte.
- Optionaler Desktop-Shortcut.
