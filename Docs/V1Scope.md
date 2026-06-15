# V1.0 Scope

Ziel: WinImageAdmin soll fuer den lokalen Windows-Image-Service-Workflow stabil, testbar und verstaendlich sein. V1.0 bedeutet nicht, dass jede moegliche ADK/DISM-Sonderfunktion eingebaut ist.

## Must Have

- Dashboard startet schnell genug, ohne direkt schwere Erkennung auf der UI zu blockieren.
- Images: WIM/ESD/ISO-Quellen anzeigen, mounten, unmounten und Status sichtbar machen.
- Driver: Treiberlisten, Mount-Auswahl und Driver-Operationen ohne UI-Haenger bedienen.
- Updates: Mount-Kontext, lokale MSU/CAB-Pruefung, Catalog-Suche und Integrationspfad sind nachvollziehbar.
- Media Builder: ISO bauen, gemeinsames Install-Image bauen und USB-Dateikopie mit Preflight anbieten.
- Settings: Sprache, Dark Mode, ADK/WinPE, MountRoot, Health, Logs und DISM/Batch-Defaults verwalten.
- Benachrichtigungen fuer abgeschlossene Jobs funktionieren, wenn sie in Settings aktiv sind.
- Dark Mode hat keine bekannten hellen Restflaechen in ThemeScan.
- Deutsch/Englisch wechseln fuer alle relevanten statischen UI-Texte.
- QuickVerification, USB Acceptance, ThemeScan und Smoke laufen gruen.

## Should Have

- Fehlerdialoge nennen eine konkrete naechste Aktion.
- ReleaseStatus dokumentiert Performance-Baseline und letzten Testlauf.
- Live-Tests sind bewusst getrennt und werden nur mit expliziten Schaltern gestartet.
- Controller sind so weit gesplittet, dass die naechsten Aenderungen lokal bleiben.

## Nach V1.0

- USB-Sticks automatisch formatieren oder partitionieren.
- Robocopy-Fortschritt pro Datei/Prozent exakt visualisieren.
- Vollautomatische Reparatur aller DISM/Mount-Sonderfaelle.
- Mehrsprachigkeit ueber Deutsch/Englisch hinaus.
- Installer/MSIX/Setup-Paket.
- Remote-/Mehrbenutzerbetrieb.

## V1.0 Exit Criteria

- `Invoke-QuickVerification.ps1` ist gruen.
- `Invoke-ProjectSmokeTest.ps1 -Scope Full -SkipMountLifecycle -SkipFeatureMount -SkipLiveCatalog` ist gruen.
- Ein manueller UI-Pass wurde in `Docs\ManualUiAcceptance.md` abgehakt.
- Ein echter USB-Test mit entbehrlichem Stick wurde dokumentiert oder als bewusst offener Punkt markiert.
- Bekannte Grenzen stehen in `Docs\KnownIssues.md`.
