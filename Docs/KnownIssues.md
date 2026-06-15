# Known Issues

Diese Liste trennt bekannte Grenzen von echten Release-Blockern.

## USB

- Das Tool formatiert, partitioniert und boot-konfiguriert USB-Sticks nicht automatisch.
- USB-Kopie nutzt Robocopy. Ein exakter Prozentfortschritt ist noch nicht verfuegbar.
- FAT32 kann keine Einzeldateien ueber 4 GB speichern. Workaround: `install.wim` splitten oder anderes geeignetes Dateisystem verwenden.
- Der echte USB-Abnahmetest muss mit einem entbehrlichen Stick manuell bestaetigt werden.

## DISM und Mounts

- DISM kann lange blockieren, auch wenn die UI Busy/Status anzeigt.
- Mount-Lifecycle-Tests koennen echte Mounts beeinflussen und bleiben daher bewusst separate Live-Gates.
- ExitCode 32 weist meist auf offene Handles hin. Explorer, Virenscanner oder offene Konsolen koennen Mounts blockieren.
- `0xc142011d` deutet oft auf teilweise geloeste oder inkonsistente Mounts hin. Cleanup/Reparatur pruefen.
- ExitCode 87 bedeutet haeufig: Option/Argument passt nicht zu Image, DISM-Version oder Kontext.

## Catalog und Netzwerk

- Catalog-Live-Suche haengt von Microsoft Catalog, Netzwerk, Sprache und Verfuegbarkeit ab.
- Der normale Quick-Test nutzt keine Live-Catalog-Abhaengigkeit.

## UI/Performance

- Erste Navigation ist absichtlich teurer als warme Navigation, weil Seiten und Controller initialisiert werden.
- Warmup reduziert Folgewechsel, ersetzt aber keine echten DISM-Hintergrundzeiten.
- ThemeScan prueft helle Flaechen automatisiert, ersetzt aber keine manuelle Sichtpruefung.

## Packaging

- Es gibt noch kein Installer-Paket. Start erfolgt ueber `Start-WinImageAdmin.wsf`.
- Erststart auf einem komplett sauberen System muss vor V1.0 noch separat bestaetigt werden.
