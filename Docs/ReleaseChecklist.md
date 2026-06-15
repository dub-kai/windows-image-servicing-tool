# Release Checklist

Arbeitsstand fuer den Weg Richtung V1.0.

## Vor jedem Release

- Branch pruefen: `git status --short --branch`
- Schnellen Testlauf starten: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-QuickVerification.ps1 -ProjectRoot D:\Win_update2`
- Vor Release-Kandidaten mit Smoke laufen lassen: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-QuickVerification.ps1 -ProjectRoot D:\Win_update2 -IncludeSmoke -SmokeScope Basic`
- Full-Smoke ohne Admin/GUI-Gate fuer Codex-Laeufe: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-ProjectSmokeTest.ps1 -ProjectRoot D:\Win_update2 -Scope Full -SkipMountLifecycle -SkipFeatureMount -SkipLiveCatalog -SkipGuiStartup`
- Release-Status erzeugen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\New-ReleaseReport.ps1 -ProjectRoot D:\Win_update2`
- Performance-Baseline anzeigen: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Compare-ReleaseBaseline.ps1 -ProjectRoot D:\Win_update2`
- Live-Gates nur bewusst starten: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-LiveGate.ps1 -ProjectRoot D:\Win_update2 -RunCatalogLive`
- Dark Mode pruefen: ThemeScan muss `0 issue(s)` melden.
- V1.0 Scope pruefen: `Docs\V1Scope.md`
- Known Issues aktualisieren: `Docs\KnownIssues.md`
- Manuelle UI-Abnahme dokumentieren: `Docs\ManualUiAcceptance.md`
- Release-Paket pruefen: `Docs\ReleasePackage.md`
- Navigation pruefen: warme Seitenwechsel sollten im NavigationStress sichtbar unter einer Sekunde bleiben.
- USB Builder pruefen: Laufwerksliste, Preflight, Warnungen und Kopierbutton muessen plausibel reagieren.
- Settings pruefen: Sprache und Dark Mode umschalten, danach Settings/Media Builder/Updates erneut ansehen.
- Job-Ende pruefen: Windows-Benachrichtigung bei abgeschlossenem Testjob ausloesen.
- Git abschliessen: committen, pushen, Commit-Hash notieren.

## Bekannte Grenzen

- Das Tool formatiert USB-Sticks weiterhin nicht. Es kopiert nur Dateien in den gewaehlten Zielordner.
- Live Catalog und echte Mount-Lifecycle-Tests sind bewusst separate, langsamere Pruefungen.
- DISM-Operationen koennen trotz UI-Busy lange dauern, weil Windows selbst blockierende Arbeit ausfuehrt.

## Naechste harte V1.0-Kriterien

- Keine hellen Flaechen im Dark Mode.
- Keine blockierende Navigation nach dem ersten Warmup.
- Alle sichtbaren Texte wechseln zwischen Deutsch und Englisch.
- USB-Preflight erklaert Platz, Dateisystem, Bootfaehigkeit und vorhandene Dateien.
- Fehlerdialoge nennen eine konkrete naechste Aktion.
