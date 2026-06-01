Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:configModule = Get-Module -Name 'Config' | Select-Object -First 1
if (-not $script:configModule) {
    $script:configModule = Import-Module (Resolve-ProjectPath "Core\Config.psm1" -MustExist) -DisableNameChecking -Global -PassThru
}

$script:getConfigValueCommand = $null
$script:setConfigValueCommand = $null

try { $script:getConfigValueCommand = $script:configModule.ExportedCommands['Get-ConfigValue'] } catch {}
try { $script:setConfigValueCommand = $script:configModule.ExportedCommands['Set-ConfigValue'] } catch {}

$script:UiTranslations = @{
    de = @{
        WindowTitle = "Windows Image Servicing Tool"
        HeaderSubtitle = "Deployment, Images, Driver und Updates in einer Oberfläche"
        NavDashboard = "Dashboard"
        NavImages = "Images"
        NavMedia = "Media Builder"
        NavDriver = "Driver"
        NavUpdates = "Updates"
        NavSettings = "Settings"
        ShellState = "Status"
        ShellReady = "Bereit"
        SettingsPageTitle = "Settings"
        SettingsBehavior = "Standardverhalten"
        SettingsStartPage = "Startseite:"
        SettingsLanguage = "Sprache:"
        SettingsDriverView = "Driver-Ansicht:"
        SettingsDriverLoadAll = "Treiber standardmäßig vollständig inkl. Inbox laden"
        SettingsUpdates = "Updates:"
        SettingsAutoCatalog = "Catalog bei Mount-Wechsel automatisch laden"
        SettingsNewMounts = "Neue Mounts:"
        SettingsMountReadOnly = "Neue Mounts standardmäßig als ReadOnly anlegen"
        SettingsNotifications = "Benachrichtigungen:"
        SettingsNotificationsEnabled = "Windows-Benachrichtigungen bei abgeschlossenen Jobs anzeigen"
        SettingsTestNotification = "Test-Benachrichtigung"
        SettingsDebug = "Debug:"
        SettingsDebugEnabled = "Erweitertes Debug-Verhalten aktivieren"
        SettingsLangGerman = "Deutsch"
        SettingsLangEnglish = "Englisch"
        StartPageMedia = "Media Builder"
        GroupAdk = "ADK & WinPE"
        BtnDetectAdk = "ADK erkennen"
        BtnPickAdk = "ADK-Ordner wählen"
        BtnPickWinPe = "WinPE-Ordner wählen"
        BtnPickOscdimg = "oscdimg.exe wählen"
        AdkStatusUnchecked = "ADK-Status: noch nicht geprüft."
        Reset = "Reset"
        GroupHealth = "Wartung & Health"
        BtnHealthRefresh = "Status aktualisieren"
        BtnUnmountAll = "Alle Mounts unmounten (Discard)"
        BtnCleanupMountDirs = "Leere Mount-Ordner bereinigen"
        HealthNotLoaded = "Status: noch nicht geladen."
        HealthFreeSpace = "Freier Platz:"
        HealthActiveMounts = "Aktive Mounts:"
        MountedImages = "Gemountete Images"
        HealthHint = "Wartungsaktionen bleiben bewusst vorsichtig: Unmount nutzt immer Discard, und die Bereinigung entfernt nur leere Unterordner unterhalb des aktiven MountRoot."
        GroupLogs = "Logs"
        BtnLogsRefresh = "Logs aktualisieren"
        BtnOpenLogFolder = "Log-Ordner öffnen"
        BtnOpenCurrentLog = "Aktuelles App-Log öffnen"
        BtnOpenDismLog = "DISM-Log öffnen"
        BtnCleanupOldLogs = "Alte App-Logs bereinigen"
        LogsNotLoaded = "Logs: noch nicht geladen."
        LogsSummary = "App-Logs: {0} Datei(en), {1}. Neueste: {2}. DISM: {3}."
        LogsAppPath = "App-Log:"
        LogsDismPath = "DISM-Log:"
        LogsPreviewSource = "Vorschau:"
        LogsPreviewApp = "Aktuelles App-Log"
        LogsPreviewDism = "DISM-Log"
        LogsFilesTitle = "App-Logdateien"
        LogsPreviewTitle = "Log-Vorschau"
        LogsPreviewTitleWithSource = "Log-Vorschau: {0}"
        LogsHint = "Die Bereinigung löscht nur alte App-Logs im Projekt-Logordner. Das aktuelle App-Log und DISM-Logs bleiben erhalten."
        LogsMissing = "nicht gefunden"
        LogsNoAppLogs = "Keine App-Logs gefunden."
        LogsPreviewMissing = "Logdatei nicht gefunden."
        LogsPreviewEmpty = "Logdatei ist leer."
        LogsPreviewTrimmed = "[Vorschau gekürzt: angezeigt wird nur das Ende der Datei.]"
        LogsPreviewReadFailed = "Logdatei konnte nicht gelesen werden: {0}"
        LogsLoadFailed = "Logs konnten nicht geladen werden: {0}"
        LogsOpenMissing = "Pfad nicht gefunden: {0}"
        LogsRefreshed = "Settings: Logs aktualisiert"
        LogsTitle = "Logs"
        LogsCleanupTitle = "Logs bereinigen"
        LogsCleanupConfirm = "Alte App-Logs löschen, die älter als {0} Tage sind? Das aktuelle App-Log und DISM-Logs bleiben erhalten."
        LogsCleanupCompleted = "Settings: {0} alte App-Log(s) bereinigt ({1})"
        LogsCleanupCancelled = "Settings: Log-Bereinigung abgebrochen"
        GroupMountRoot = "MountRoot (Arbeitsordner für DISM-Mounts)"
        BtnPickFolder = "Ordner wählen"
        MountRootHint = "Hinweis: Lokaler NTFS-Pfad empfohlen. Diese Einstellung wird dauerhaft im ignorierten Work-Bereich gespeichert."
        GroupInfo = "Info"
        SettingsMountRootLabel = "MountRoot: {0}"
        AdkStatusLabel = "ADK-Status: gefunden -> {0}"
        AdkStatusMissing = "ADK-Status: nichts erkannt. ADK oder WinPE Add-on fehlt noch oder Pfade sind nicht gesetzt."
        CopypeLabel = "copype.cmd: {0}"
        MakeWinPeMediaLabel = "MakeWinPEMedia.cmd: {0}"
        HealthLoading = "Status wird aktualisiert..."
        HealthLoadFailed = "Status konnte nicht geladen werden."
        HealthLoaded = "Health: Status aktualisiert"
        HealthInitiallyLoaded = "Health: Initial geladen"
        HealthUnmountingAll = "Alle Mounts werden mit Discard unmountet..."
        HealthCleanupDirs = "Leere Mount-Ordner werden bereinigt..."
        SettingsMountRootSet = "Settings: MountRoot gesetzt"
        SettingsMountRootReset = "Settings: MountRoot reset"
        SettingsHealthAfterMountRootChange = "Settings: Health nach MountRoot-Änderung aktualisiert"
        SettingsHealthAfterMountRootReset = "Settings: Health nach MountRoot-Reset aktualisiert"
        SettingsStartPageStatus = "Settings: Startseite = {0}"
        SettingsLanguageStatus = "Settings: Sprache = {0}"
        SettingsAdkDetected = "Settings: ADK automatisch erkannt"
        SettingsAdkNotFound = "Settings: ADK nicht gefunden"
        SettingsAdkRootSet = "Settings: ADK-Ordner gesetzt"
        SettingsWinPeRootSet = "Settings: WinPE-Ordner gesetzt"
        SettingsOscdimgSet = "Settings: oscdimg.exe gesetzt"
        SettingsAdkRootReset = "Settings: ADK-Ordner zurückgesetzt"
        SettingsWinPeRootReset = "Settings: WinPE-Ordner zurückgesetzt"
        SettingsOscdimgReset = "Settings: oscdimg.exe zurückgesetzt"
        SettingsDriverDefaultsUpdated = "Settings: Driver-Standard aktualisiert"
        SettingsUpdatesDefaultsUpdated = "Settings: Updates-Standard aktualisiert"
        SettingsMountDefaultsUpdated = "Settings: Mount-Standard aktualisiert"
        SettingsNotificationsUpdated = "Settings: Benachrichtigungen aktualisiert"
        SettingsTestNotificationSent = "Settings: Test-Benachrichtigung gesendet"
        SettingsTestNotificationFailed = "Settings: Test-Benachrichtigung konnte nicht angezeigt werden"
        NotificationTestTitle = "Windows Image Servicing Tool"
        NotificationTestMessage = "Test-Benachrichtigung vom Windows Image Servicing Tool."
        SettingsDebugUpdated = "Settings: Debug-Standard aktualisiert"
        SettingsHealthAfterDebugChange = "Settings: Health nach Debug-Änderung aktualisiert"
        HealthAdminOk = "OK - App läuft mit Adminrechten"
        HealthAdminMissing = "Fehlt - Adminrechte werden für DISM benötigt"
        HealthDismOk = "OK - {0}"
        HealthDismMissing = "DISM nicht gefunden"
        HealthMountRootOk = "OK - {0}"
        HealthMountRootMissing = "Fehlt - {0}"
        HealthDriveUnknown = "Unbekannt"
        HealthDriveReadFailed = "Freier Platz konnte nicht gelesen werden."
        HealthMountEntry = "{0} | Index {1} | {2}"
        HealthSummaryWithMounts = "{0} aktive Mounts erkannt."
        HealthSummaryNoMounts = "Keine aktiven Mounts erkannt."
        HealthMountCount = "{0} aktive Mounts"
        SettingsUnmountCompleted = "Settings: {0} Mount(s) mit Discard unmounted"
        SettingsHealthAfterUnmount = "Settings: Health nach Unmount aktualisiert ({0} Mount(s))"
        SettingsUnmountCompletedWithCleanup = "Settings: {0} Mount(s) unmounted, Cleanup-Wim für {1} Registry-Rest(e) ausgeführt"
        SettingsUnmountCleanupFailed = "Settings: {0} Mount(s) unmounted, Cleanup-Wim für {1} Registry-Rest(e) fehlgeschlagen"
        SettingsHealthAfterUnmountWithCleanup = "Settings: Health nach Unmount/Cleanup aktualisiert ({0} Mount(s), {1} Registry-Rest(e))"
        SettingsCleanupCompleted = "Settings: {0} leere Mount-Ordner bereinigt"
        SettingsHealthAfterCleanup = "Settings: Health nach Bereinigung aktualisiert ({0} Ordner)"
        DialogMountRoot = "MountRoot wählen (lokal, NTFS empfohlen)"
        DialogAdkFolder = "ADK-Ordner wählen"
        DialogWinPeFolder = "WinPE-Ordner wählen"
        DialogOscdimg = "oscdimg.exe wählen"
        HealthTitle = "Health"
        UnmountAllTitle = "Alle unmounten"
        CleanupTitle = "Bereinigung"
    }
    en = @{
        WindowTitle = "Windows Image Servicing Tool"
        HeaderSubtitle = "Deployment, images, drivers and updates in one interface"
        NavDashboard = "Dashboard"
        NavImages = "Images"
        NavMedia = "Media Builder"
        NavDriver = "Drivers"
        NavUpdates = "Updates"
        NavSettings = "Settings"
        ShellState = "State"
        ShellReady = "Ready"
        SettingsPageTitle = "Settings"
        SettingsBehavior = "Defaults"
        SettingsStartPage = "Start page:"
        SettingsLanguage = "Language:"
        SettingsDriverView = "Driver view:"
        SettingsDriverLoadAll = "Load drivers fully including inbox drivers by default"
        SettingsUpdates = "Updates:"
        SettingsAutoCatalog = "Load Catalog automatically when mount changes"
        SettingsNewMounts = "New mounts:"
        SettingsMountReadOnly = "Create new mounts as read-only by default"
        SettingsNotifications = "Notifications:"
        SettingsNotificationsEnabled = "Show Windows notifications when jobs complete"
        SettingsTestNotification = "Test notification"
        SettingsDebug = "Debug:"
        SettingsDebugEnabled = "Enable extended debug behavior"
        SettingsLangGerman = "German"
        SettingsLangEnglish = "English"
        StartPageMedia = "Media Builder"
        GroupAdk = "ADK & WinPE"
        BtnDetectAdk = "Detect ADK"
        BtnPickAdk = "Choose ADK folder"
        BtnPickWinPe = "Choose WinPE folder"
        BtnPickOscdimg = "Choose oscdimg.exe"
        AdkStatusUnchecked = "ADK status: not checked yet."
        Reset = "Reset"
        GroupHealth = "Maintenance & Health"
        BtnHealthRefresh = "Refresh status"
        BtnUnmountAll = "Unmount all mounts (Discard)"
        BtnCleanupMountDirs = "Clean empty mount folders"
        HealthNotLoaded = "Status: not loaded yet."
        HealthFreeSpace = "Free space:"
        HealthActiveMounts = "Active mounts:"
        MountedImages = "Mounted images"
        HealthHint = "Maintenance actions intentionally stay cautious: unmount always uses Discard, and cleanup removes only empty subfolders below the active MountRoot."
        GroupLogs = "Logs"
        BtnLogsRefresh = "Refresh logs"
        BtnOpenLogFolder = "Open log folder"
        BtnOpenCurrentLog = "Open current app log"
        BtnOpenDismLog = "Open DISM log"
        BtnCleanupOldLogs = "Clean old app logs"
        LogsNotLoaded = "Logs: not loaded yet."
        LogsSummary = "App logs: {0} file(s), {1}. Latest: {2}. DISM: {3}."
        LogsAppPath = "App log:"
        LogsDismPath = "DISM log:"
        LogsPreviewSource = "Preview:"
        LogsPreviewApp = "Current app log"
        LogsPreviewDism = "DISM log"
        LogsFilesTitle = "App log files"
        LogsPreviewTitle = "Log preview"
        LogsPreviewTitleWithSource = "Log preview: {0}"
        LogsHint = "Cleanup deletes only old app logs in the project log folder. The current app log and DISM logs are kept."
        LogsMissing = "not found"
        LogsNoAppLogs = "No app logs found."
        LogsPreviewMissing = "Log file not found."
        LogsPreviewEmpty = "Log file is empty."
        LogsPreviewTrimmed = "[Preview trimmed: only the end of the file is shown.]"
        LogsPreviewReadFailed = "Could not read log file: {0}"
        LogsLoadFailed = "Could not load logs: {0}"
        LogsOpenMissing = "Path not found: {0}"
        LogsRefreshed = "Settings: logs refreshed"
        LogsTitle = "Logs"
        LogsCleanupTitle = "Clean logs"
        LogsCleanupConfirm = "Delete old app logs older than {0} days? The current app log and DISM logs are kept."
        LogsCleanupCompleted = "Settings: cleaned {0} old app log(s) ({1})"
        LogsCleanupCancelled = "Settings: log cleanup cancelled"
        GroupMountRoot = "MountRoot (working folder for DISM mounts)"
        BtnPickFolder = "Choose folder"
        MountRootHint = "Note: a local NTFS path is recommended. This setting is stored permanently in the ignored Work area."
        GroupInfo = "Info"
        SettingsMountRootLabel = "MountRoot: {0}"
        AdkStatusLabel = "ADK status: found -> {0}"
        AdkStatusMissing = "ADK status: nothing detected. The ADK or WinPE add-on is still missing, or the paths are not set."
        CopypeLabel = "copype.cmd: {0}"
        MakeWinPeMediaLabel = "MakeWinPEMedia.cmd: {0}"
        HealthLoading = "Refreshing status..."
        HealthLoadFailed = "Could not load status."
        HealthLoaded = "Health: status refreshed"
        HealthInitiallyLoaded = "Health: loaded initially"
        HealthUnmountingAll = "Unmounting all mounts with Discard..."
        HealthCleanupDirs = "Cleaning empty mount folders..."
        SettingsMountRootSet = "Settings: MountRoot saved"
        SettingsMountRootReset = "Settings: MountRoot reset"
        SettingsHealthAfterMountRootChange = "Settings: health refreshed after MountRoot change"
        SettingsHealthAfterMountRootReset = "Settings: health refreshed after MountRoot reset"
        SettingsStartPageStatus = "Settings: start page = {0}"
        SettingsLanguageStatus = "Settings: language = {0}"
        SettingsAdkDetected = "Settings: ADK detected automatically"
        SettingsAdkNotFound = "Settings: ADK not found"
        SettingsAdkRootSet = "Settings: ADK folder saved"
        SettingsWinPeRootSet = "Settings: WinPE folder saved"
        SettingsOscdimgSet = "Settings: oscdimg.exe saved"
        SettingsAdkRootReset = "Settings: ADK folder reset"
        SettingsWinPeRootReset = "Settings: WinPE folder reset"
        SettingsOscdimgReset = "Settings: oscdimg.exe reset"
        SettingsDriverDefaultsUpdated = "Settings: driver default updated"
        SettingsUpdatesDefaultsUpdated = "Settings: update default updated"
        SettingsMountDefaultsUpdated = "Settings: mount default updated"
        SettingsNotificationsUpdated = "Settings: notifications updated"
        SettingsTestNotificationSent = "Settings: test notification sent"
        SettingsTestNotificationFailed = "Settings: test notification could not be shown"
        NotificationTestTitle = "Windows Image Servicing Tool"
        NotificationTestMessage = "Test notification from Windows Image Servicing Tool."
        SettingsDebugUpdated = "Settings: debug default updated"
        SettingsHealthAfterDebugChange = "Settings: health refreshed after debug change"
        HealthAdminOk = "OK - app is running with admin rights"
        HealthAdminMissing = "Missing - admin rights are required for DISM"
        HealthDismOk = "OK - {0}"
        HealthDismMissing = "DISM not found"
        HealthMountRootOk = "OK - {0}"
        HealthMountRootMissing = "Missing - {0}"
        HealthDriveUnknown = "Unknown"
        HealthDriveReadFailed = "Could not read free space."
        HealthMountEntry = "{0} | Index {1} | {2}"
        HealthSummaryWithMounts = "{0} active mounts detected."
        HealthSummaryNoMounts = "No active mounts detected."
        HealthMountCount = "{0} active mounts"
        SettingsUnmountCompleted = "Settings: unmounted {0} mount(s) with Discard"
        SettingsHealthAfterUnmount = "Settings: health refreshed after unmount ({0} mount(s))"
        SettingsUnmountCompletedWithCleanup = "Settings: unmounted {0} mount(s), ran Cleanup-Wim for {1} registry remnant(s)"
        SettingsUnmountCleanupFailed = "Settings: unmounted {0} mount(s), Cleanup-Wim failed for {1} registry remnant(s)"
        SettingsHealthAfterUnmountWithCleanup = "Settings: health refreshed after unmount/cleanup ({0} mount(s), {1} registry remnant(s))"
        SettingsCleanupCompleted = "Settings: cleaned {0} empty mount folder(s)"
        SettingsHealthAfterCleanup = "Settings: health refreshed after cleanup ({0} folder(s))"
        DialogMountRoot = "Choose MountRoot (local, NTFS recommended)"
        DialogAdkFolder = "Choose ADK folder"
        DialogWinPeFolder = "Choose WinPE folder"
        DialogOscdimg = "Choose oscdimg.exe"
        HealthTitle = "Health"
        UnmountAllTitle = "Unmount all"
        CleanupTitle = "Cleanup"
    }
}

$script:UiStaticTextTranslations = @'
Key;de;en
StaticMountStep;1. Mount wählen;1. Select mount
UpdatesMountSelectionFormat;Mounts: {0} | Auswahl: {1};Mounts: {0} | selection: {1}
UpdatesBatchNoMount;Batch: Kein Mount geladen. Bitte zuerst Images mounten oder aktualisieren.;Batch: no mount loaded. Mount or refresh images first.
UpdatesBatchNoCatalog;kein Catalog-Treffer ausgewählt;no Catalog result selected
UpdatesBatchCatalogSelected;Catalog-Treffer ausgewählt;Catalog result selected
UpdatesBatchMoreTargets; + {0} weitere; + {0} more
UpdatesBatchPlanFormat;Batch: {0}/{1} Mounts sind Read/Write. Update: {2}. Ziele: {3}{4};Batch: {0}/{1} mounts are read/write. Update: {2}. Targets: {3}{4}
UpdatesCatalogResultFallback;Catalog-Treffer;Catalog result
UpdatesNoMountsLoaded;Keine Mounts geladen;No mounts loaded
UpdatesNoMountsDetail;Öffne Images, mounte ein Image oder klicke hier auf Refresh.;Open Images, mount an image, or click Refresh here.
UpdatesNoSelection;keine Auswahl;no selection
UpdatesMountStateFormat;{0} Mount(s), {1} Read/Write;{0} mount(s), {1} read/write
UpdatesSelectionFormat;Auswahl: {0};Selection: {0}
UpdatesMountNotSuitable;Dieser Mount ist nicht für Update-Integration geeignet.;This mount is not suitable for update integration.
UpdatesStatusLoaded;Status geladen;Status loaded
UpdatesCatalogOpen;Catalog noch offen;Catalog still open
UpdatesCatalogVisibleFormat;{0} Treffer sichtbar;{0} results visible
UpdatesCatalogSummaryFormat;Gesamt: {0} | empfohlen: {1};Total: {0} | recommended: {1}
UpdatesCatalogSelectedFormat;Ausgewählt: {0};Selected: {0}
UpdatesActionSelectUpdate;Update auswählen;Select update
UpdatesActionBusy;Aktion läuft;Action running
UpdatesActionBusyDetail;Bitte warten. Der Fortschritt steht im Busy-Bereich und im Log.;Please wait. Progress is shown in the busy area and in the log.
UpdatesActionReady;Bereit zum Anwenden;Ready to apply
UpdatesActionReadyDetail;{0} kann in {1} passende(n) Mount(s) integriert werden.;{0} can be integrated into {1} matching mount(s).
UpdatesActionNoTarget;Kein Read/Write-Ziel;No read/write target
UpdatesActionNoTargetDetail;Zum Integrieren brauchst du mindestens einen passenden Read/Write-Mount.;Integration needs at least one matching read/write mount.
UpdatesActionSelectResult;Treffer auswählen;Select result
UpdatesActionSelectResultDetail;Wähle einen Catalog-Treffer für Download, Preflight oder Integration.;Select a Catalog result for download, preflight, or integration.
UpdatesBusyDetail;Updates oder Paketlisten werden verarbeitet. DISM kann bei großen Paketen mehrere Minuten benötigen.;Updates or package lists are being processed. DISM can take several minutes for large packages.
UpdatesFooterLoadMountData;Mount-Daten laden. Danach kann die Catalog-Suche ausgefuehrt werden.;Loading mount data. Then the Catalog search can be run.
UpdatesServiceNoMountContext;Eignung: Kein Mount-Kontext geladen.;Suitability: no mount context loaded.
UpdatesMountReadyStatusFormat;Mount bereit | Produkt: {0} | Arch: {1} | Build: {2};Mount ready | product: {0} | arch: {1} | build: {2}
UpdatesServiceStatusDefault;Eignung;Suitability
UpdatesMountDataLoaded;Mount-Daten geladen.;Mount data loaded.
UpdatesFooterCatalogReady;Mount-Daten geladen. Catalog-Suche kann gestartet werden.;Mount data loaded. Catalog search can be started.
UpdatesBootWinPeReason;Boot-/WinPE-Image erkannt. Pakete werden angezeigt, aber die automatische Catalog-Suche ist deaktiviert.;Boot/WinPE image detected. Packages are shown, but automatic Catalog search is disabled.
UpdatesServiceHintFormat;Eignung: {0} | {1};Suitability: {0} | {1}
UpdatesBusyReadingMounts;Mounts werden gelesen...;Reading mounts...
UpdatesNoMountedImageFound;Kein gemountetes Image gefunden.;No mounted image found.
UpdatesFooterNoActiveMount;Aktuell ist kein Mount aktiv. Bitte zuerst ein Image mounten.;No mount is active. Mount an image first.
UpdatesMountSelectionFailed;Es konnte kein Mount ausgewaehlt werden.;No mount could be selected.
UpdatesFooterMountSelectionFailed;Mounts wurden gefunden, aber es konnte keine Auswahl bestimmt werden.;Mounts were found, but no selection could be determined.
UpdatesReadMountListFailed;Fehler beim Lesen der Mount-Liste.;Failed to read mount list.
UpdatesBusyLoadingMountContext;Mount-Kontext wird geladen...;Loading mount context...
UpdatesMountContextLoadFailed;Der Mount-Kontext konnte nicht geladen werden.;The mount context could not be loaded.
UpdatesReadMountContextFailed;Fehler beim Lesen des Mount-Kontexts.;Failed to read mount context.
UpdatesCatalogUnsupported;Dieses Image ist fuer die automatische Catalog-Suche nicht geeignet.;This image is not suitable for automatic Catalog search.
UpdatesCatalogNoQueries;Fuer das aktuelle Image konnten keine Catalog-Queries gebildet werden.;No Catalog queries could be built for the current image.
UpdatesBusyCatalogSearch;Microsoft Update Catalog wird durchsucht...;Searching Microsoft Update Catalog...
UpdatesCatalogSearchNoResultFooter;Catalog-Suche abgeschlossen, aber ohne Treffer. Bei Insider-/Release-Preview-Updates kannst du die .msu/.cab manuell laden und ueber MSU/CAB waehlen hinzufuegen.;Catalog search completed, but no results were found. For Insider/Release Preview updates, download the .msu/.cab manually and add it with Choose MSU/CAB.
UpdatesCatalogSearchCompleteFooter;Catalog-Suche abgeschlossen. Treffer koennen jetzt gefiltert und ausgewaehlt werden. Tipp: Alle Treffer zeigt auch Preview- und nicht empfohlene Pakete.;Catalog search completed. Results can now be filtered and selected. Tip: All results also shows preview and not recommended packages.
UpdatesCatalogSearchEmptyFooter;Catalog-Suche abgeschlossen, aber ohne passende Treffer. Nutze Alle Treffer fuer Diagnose oder fuege eine heruntergeladene .msu/.cab ueber MSU/CAB waehlen hinzu.;Catalog search completed, but no matching results were found. Use All results for diagnostics or add a downloaded .msu/.cab with Choose MSU/CAB.
UpdatesCatalogSearchTitle;Catalog-Suche;Catalog search
UpdatesBusyCatalogDownload;Catalog-Update wird heruntergeladen...;Downloading Catalog update...
UpdatesDownloadNoResult;Der Download lieferte kein Ergebnisobjekt zurueck.;The download did not return a result object.
UpdatesDownloadCompleteMessageFormat;Download abgeschlossen.`n`nDateien: {0}`nNeu: {1}`nBereits vorhanden: {2}`nOrdner: {3};Download complete.`n`nFiles: {0}`nNew: {1}`nAlready present: {2}`nFolder: {3}
UpdatesIntegrationNotAllowed;Dieser Mount ist für normale Update-Integration nicht freigegeben.;This mount is not approved for normal update integration.
UpdatesBusySingleIntegration;Update wird heruntergeladen und in den Mount integriert...;Downloading update and integrating it into the mount...
UpdatesIntegrationSkippedFormat;Integration uebersprungen: {0};Integration skipped: {0}
UpdatesIntegrationNoResult;Die Integration lieferte kein Ergebnisobjekt zurueck.;The integration did not return a result object.
UpdatesIntegrationCompleteMessageFormat;Integration abgeschlossen.`n`nMount: {0}`nIntegrierte Dateien: {1}`nDownload-Ordner: {2}`n`nDateien:`n{3};Integration complete.`n`nMount: {0}`nIntegrated files: {1}`nDownload folder: {2}`n`nFiles:`n{3}
UpdatesIntegrationReloadStatus;Integration abgeschlossen. Mount-Kontext wird neu geladen...;Integration complete. Reloading mount context...
UpdatesIntegrationReloadFooter;Integration abgeschlossen. Mount- und Catalog-Daten werden aktualisiert...;Integration complete. Mount and Catalog data are being refreshed...
UpdatesBatchLineIntegratedFormat;OK: {0} ({1} Datei(en));OK: {0} ({1} file(s))
UpdatesBatchLineSkippedFormat;Übersprungen: {0} ({1});Skipped: {0} ({1})
UpdatesBatchLineFailedFormat;Fehler: {0} ({1});Failed: {0} ({1})
UpdatesPreflightNoDism;Keine laufenden DISM-Prozesse gefunden.;No running DISM processes found.
UpdatesPreflightYes;Ja;Yes
UpdatesPreflightNo;Nein;No
UpdatesPreflightCompleteMessageFormat;Batch-Prüfung abgeschlossen.`n`nUpdate: {0}`nMounts: {1}`nBereit: {2}`nÜbersprungen: {3}`nDISM aktiv: {4}`n`nZiele:`n{5}`n`nDISM-Prozesse:`n{6};Batch check complete.`n`nUpdate: {0}`nMounts: {1}`nReady: {2}`nSkipped: {3}`nDISM active: {4}`n`nTargets:`n{5}`n`nDISM processes:`n{6}
UpdatesPreflightPlanFormat;Batch-Prüfung: {0}/{1} Mounts bereit, {2} übersprungen. Update: {3};Batch check: {0}/{1} mounts ready, {2} skipped. Update: {3}
UpdatesNoMountsInList;Es sind aktuell keine Mounts in der Updates-Liste vorhanden.;There are currently no mounts in the Updates list.
UpdatesBusyPreflight;Batch-Prüfung läuft...;Batch check running...
UpdatesPreflightNoResult;Die Batch-Prüfung lieferte kein Ergebnisobjekt zurück.;The batch check did not return a result object.
UpdatesBatchRunPlanFormat;Batch läuft: Update wird auf {0} Mount(s) nacheinander angewendet. Ungeeignete Mounts werden übersprungen.;Batch running: update is being applied to {0} mount(s) one after another. Unsuitable mounts are skipped.
UpdatesBusyBatchIntegrationFormat;Update wird in {0} Mount(s) integriert...;Integrating update into {0} mount(s)...
UpdatesBatchIntegrationNoResult;Die Batch-Integration lieferte kein Ergebnisobjekt zurück.;The batch integration did not return a result object.
UpdatesBatchIntegrationCompleteMessageFormat;Batch-Integration abgeschlossen.`n`nMounts: {0}`nOK: {1}`nÜbersprungen: {2}`nFehler: {3}`nDownload-Ordner: {4}`n`nDetails:`n{5};Batch integration complete.`n`nMounts: {0}`nOK: {1}`nSkipped: {2}`nFailed: {3}`nDownload folder: {4}`n`nDetails:`n{5}
UpdatesBatchIntegrationReloadStatus;Batch-Integration abgeschlossen. Mount-Kontext wird neu geladen...;Batch integration complete. Reloading mount context...
UpdatesBatchIntegrationReloadFooter;Batch-Integration abgeschlossen. Mount- und Catalog-Daten werden aktualisiert...;Batch integration complete. Mount and Catalog data are being refreshed...
UpdatesLastBatchFormat;Letzter Batch: {0} OK, {1} übersprungen, {2} Fehler.;Last batch: {0} OK, {1} skipped, {2} failed.
UpdatesCatalogNoSelection;Noch kein Catalog-Treffer ausgewaehlt.;No Catalog result selected yet.
UpdatesLocalFileProduct;Lokale Datei;Local file
UpdatesLocalManualClassification;Manuell hinzugefügt;Added manually
UpdatesLocalFileState;Lokale Datei;Local file
UpdatesLocalDialogTitle;Lokales Update auswählen;Select local update
UpdatesLocalDialogFilter;"Windows Update Pakete (*.msu;*.cab)|*.msu;*.cab|Alle Dateien (*.*)|*.*";"Windows update packages (*.msu;*.cab)|*.msu;*.cab|All files (*.*)|*.*"
UpdatesLocalInvalidPackage;Es wurde keine gültige .msu- oder .cab-Datei ausgewählt.;No valid .msu or .cab file was selected.
UpdatesLocalTitle;Lokales Update;Local update
UpdatesLocalAddedStatusFormat;Lokales Update hinzugefügt: {0};Local update added: {0}
UpdatesLocalReadyFooter;Lokale Update-Datei bereit. Du kannst sie jetzt in den ausgewählten Mount oder in alle Mounts integrieren.;Local update file ready. You can now integrate it into the selected mount or all mounts.
UpdatesRecommendationNoSearch;Noch keine Catalog-Suche ausgefuehrt.;No Catalog search has run yet.
UpdatesRecommendationSummaryFormat;Gesamt: {0} | LCU: {1} | SSU: {2} | .NET: {3} | Preview: {4};Total: {0} | LCU: {1} | SSU: {2} | .NET: {3} | preview: {4}
UpdatesCatalogModeRecommended;Empfohlen;Recommended
UpdatesCatalogModeAll;Alle Treffer;All results
UpdatesCatalogModePackages;Pakete;Packages
UpdatesCatalogResultsCountFormat;Treffer: {0} | Gesamt: {1} | Empfohlen: {2} | Lokal: {3};Results: {0} | total: {1} | recommended: {2} | local: {3}
UpdatesCatalogFilterHintFormat;Ansicht: {0} | Pakete: {1} | Sichtbar: {2} | Gesamt: {3};View: {0} | packages: {1} | visible: {2} | total: {3}
UpdatesCatalogExportEmpty;Aktuell sind keine sichtbaren Catalog-Treffer zum Exportieren vorhanden.;There are currently no visible Catalog results to export.
UpdatesCatalogExportTitle;Catalog Export;Catalog export
UpdatesCatalogCsvExportedFormat;Catalog CSV exportiert: {0};Catalog CSV exported: {0}
UpdatesPackagesModeKbOnly;Nur KB-Pakete;KB packages only
UpdatesPackagesModeAll;Alle;All
UpdatesPackagesModeImportant;Wichtige;Important
UpdatesPackagesCountFormat;Pakete: {0} / {1} | Modus: {2};Packages: {0} / {1} | mode: {2}
UpdatesPackagesExportEmpty;Aktuell sind keine sichtbaren Pakete zum Exportieren vorhanden.;There are currently no visible packages to export.
UpdatesPackagesExportTitle;Pakete Export;Packages export
UpdatesPackagesCsvFilter;CSV (*.csv)|*.csv|Alle Dateien (*.*)|*.*;CSV (*.csv)|*.csv|All files (*.*)|*.*
UpdatesPackagesCsvExportedFormat;Pakete CSV exportiert: {0};Packages CSV exported: {0}
NotificationJobCompletedTitle;Job abgeschlossen;Job complete
NotificationJobCompletedMessageFormat;{0} abgeschlossen. Laufzeit: {1};{0} completed. Duration: {1}
NotificationJobFailedTitle;Job fehlgeschlagen;Job failed
NotificationJobFailedMessageFormat;{0} fehlgeschlagen. Laufzeit: {1}`n{2};{0} failed. Duration: {1}`n{2}
StaticErrorTitle;Fehler;Error
StaticInfoTitle;Hinweis;Note
StaticNoValidMountDir;Kein gültiges MountDir ausgewählt.;No valid MountDir selected.
StaticNoValidMountDirAscii;Kein gueltiges MountDir ausgewaehlt.;No valid MountDir selected.
StaticSelectDriverFirst;Bitte zuerst einen oder mehrere Treiber auswählen.;Select one or more drivers first.
StaticSelectIndexFirst;Bitte zuerst mindestens einen Index auswählen.;Select at least one index first.
StaticNoMountedInstallMedia;Kein gemountetes Windows-Installmedium gefunden.;No mounted Windows installation media found.
StaticSelectMountedImage;Bitte ein Mounted Image auswählen.;Select a mounted image first.
StaticNoViewSelected;Keine Ansicht ausgewählt.;No view selected.
StaticCommitNotPossible;Commit ist für diesen Mount nicht möglich.;Commit is not possible for this mount.
StaticMountDirUnavailable;MountDir nicht ermittelbar.;Could not determine MountDir.
StaticNoMountedImageAvailable;Es ist aktuell kein gemountetes Image verfuegbar.;No mounted image is currently available.
StaticSelectCatalogFirstAscii;Bitte zuerst einen Catalog-Treffer auswaehlen.;Select a Catalog result first.
StaticSelectCatalogFirst;Bitte zuerst einen Catalog-Treffer auswählen.;Select a Catalog result first.
StaticNoUpdateIdDownloadAscii;Der ausgewaehlte Eintrag hat keine UpdateId und kann nicht direkt heruntergeladen werden.;The selected entry has no UpdateId and cannot be downloaded directly.
StaticNoUpdateIdIntegrateAscii;Der ausgewaehlte Eintrag hat keine UpdateId und kann nicht integriert werden.;The selected entry has no UpdateId and cannot be integrated.
StaticNoUpdateIdIntegrate;Der ausgewählte Eintrag hat keine UpdateId und kann nicht integriert werden.;The selected entry has no UpdateId and cannot be integrated.
StaticNoValidMountSelectedAscii;Es ist aktuell kein gueltiger Mount ausgewaehlt.;No valid mount is currently selected.
StaticMountReadOnlyAscii;Der ausgewaehlte Mount ist schreibgeschuetzt. Bitte ein Read/Write-Mount verwenden.;The selected mount is read-only. Use a read/write mount.
StaticBuildIsoStep;1. Neue ISO bauen;1. Build new ISO
StaticBuildInstallStep;2. Ein gemeinsames Install-Image bauen;2. Build one combined install image
StaticFindUpdateStep;2. Update finden;2. Find update
StaticApplyStep;3. Anwenden;3. Apply
StaticUsbStep;3. USB-Stick vorbereiten;3. Prepare USB stick
StaticAdkRoot;ADK Root:;ADK root:
StaticAdmin;Admin:;Admin:
StaticAction;Aktion;Action
StaticActions;Aktionen;Actions
StaticActiveMounts;Aktive Mounts;Active mounts
StaticCurrentSource;Aktuelle Quelle;Current source
StaticCurrentBuild;Aktueller Build;Current build
StaticDashboardSubtitle;Aktueller Stand, nächste sinnvolle Aktion und die wichtigsten Wege durchs Tool.;Current state, next useful action, and the most important paths through the tool.
StaticCurrentAppLog;Aktuelles App-Log;Current app log
StaticSelectAllIndexes;Alle Indexe auswählen;Select all indexes
StaticAllPackages;Alle Pakete;All packages
StaticAllResults;Alle Treffer;All results
StaticAllDrivers;Alle Treiber (inkl. Inbox);All drivers (including inbox)
StaticDismBatchChanged;Änderungen gelten für neue DISM-Aufgaben.;Changes apply to new DISM tasks.
StaticViewSearch;Ansicht & Suche;View & search
StaticView;Ansicht:;View:
StaticUsbCopy;Auf USB kopieren;Copy to USB
StaticRemoveSelectedDrivers;Ausgewählte Treiber entfernen;Remove selected drivers
StaticExportSelectedIndex;Ausgewählten Index exportieren;Export selected index
StaticCommitSelection;Auswahl committen;Commit selection
StaticRemoveSelection;Auswahl entfernen;Remove selection
StaticMountSelection;Auswahl mounten;Mount selection
StaticMountReadWriteSelection;Auswahl Read/Write mounten;Mount selection read/write
StaticMountReadOnlySelection;Auswahl ReadOnly mounten;Mount selection read-only
StaticDiscardSelection;Auswahl verwerfen / bereinigen;Discard / clean selection
StaticNoIndexSelected;Auswahl: Noch kein Index ausgewählt.;Selection: no index selected yet.
StaticBaseIso;Basis-ISO:;Base ISO:
StaticBatchCheck;Batch prüfen;Check batch
StaticBatchPreflight;Batch vorher prüfen;Preflight batch
StaticBatchMountsLoading;Batch: Mounts werden geladen.;Batch: loading mounts.
StaticBatchUnmountPause;Batch-Unmount-Pause:;Batch unmount pause:
StaticReady;Bereit;Ready
StaticPleaseWait;Bitte warten...;Please wait...
UiBusyDefaultMessage;Bitte warten...;Please wait...
UiBusyElapsedFormat;Laufzeit: {0};Elapsed: {0}
UiBusyDefaultDetail;Vorgang läuft. Bei großen Images kann DISM mehrere Minuten ohne sichtbare Dateigrößenänderung arbeiten.;Operation is running. With large images, DISM can work for several minutes without visible file size changes.
UiBusyDefaultHint;Bitte nicht abbrechen, solange DISM CPU/Datenträger nutzt. Beim Abbruch kann ein Mount bereinigt werden müssen.;Do not cancel while DISM is using CPU or disk. After cancellation, a mount may need cleanup.
UiBusyNoDismLog;Noch kein DISM-Logeintrag gelesen.;No DISM log entry read yet.
UiBusyDismLine;DISM: {0};DISM: {0}
StaticResetBoot;Boot zurücksetzen;Reset boot
StaticChooseBootWim;boot.wim wählen;Choose boot.wim
StaticBuildCancel;Build abbrechen;Cancel build
StaticBuildMode;Build-Modus;Build mode
StaticCatalogOpen;Catalog noch offen.;Catalog still open.
StaticCatalogSearch;Catalog suchen;Search Catalog
StaticCatalogResults;Catalog-Treffer;Catalog results
StaticClear;Clear;Clear
StaticCommitRetryCount;Commit-Retry-Anzahl:;Commit retry count:
StaticCommitRetryPause;Commit-Retry-Pause:;Commit retry pause:
StaticCommitTimeout;Commit-Timeout:;Commit timeout:
StaticConfigFile;ConfigFile:;Config file:
StaticCopy;Kopieren;Copy
StaticUsbCopyDescription;Kopiert eine vorbereitete Windows-Quelle auf einen USB-Zielordner. Sicherer erster Schritt: Es wird nichts formatiert und nichts gelöscht.;Copies a prepared Windows source to a USB target folder. Safe first step: nothing is formatted or deleted.
StaticChooseFiles;Dateien wählen;Choose files
StaticCommitRefreshPause;Kurze Pause nach Mount-Listen-Refresh vor Commit.;Short pause after refreshing the mount list before commit.
StaticElapsed;Laufzeit: 00:00;Elapsed: 00:00
StaticSize;Größe:;Size:
StaticCleanupEmptyMountFolders;Leere Mount-Ordner bereinigen;Clean empty mount folders
StaticLastError;Letzter Fehler;Last error
StaticLogFile;Logdatei:;Log file:
StaticLogFolderOpen;Log-Ordner öffnen;Open log folder
StaticLogsRefresh;Logs aktualisieren;Refresh logs
StaticLogsNotLoaded;Logs: noch nicht geladen.;Logs: not loaded yet.
StaticLogPreview;Log-Vorschau;Log preview
StaticAddLocalMsuCab;Lokale MSU/CAB hinzufügen;Add local MSU/CAB
StaticMaintenanceHealth;Maintenance & Health;Maintenance & health
StaticHealthHintShort;Maintenance-Aktionen bleiben bewusst vorsichtig: Unmount nutzt immer Discard, und die Bereinigung entfernt nur leere Unterordner unterhalb des aktiven MountRoot.;Maintenance actions intentionally stay cautious: unmount always uses Discard, and cleanup removes only empty subfolders below the active MountRoot.
StaticMount;Mount:;Mount:
StaticMountDash;Mount: -;Mount: -
StaticMountAssistant;Mount-Assistent: Wähle einen Index, um den Plan zu prüfen.;Mount assistant: select an index to check the plan.
StaticMountDirCopy;MountDir kopieren;Copy MountDir
StaticMountDir;MountDir:;MountDir:
StaticSelectMountedImage;Mounted Image auswählen;Select mounted image
StaticMountRefreshWait;Mount-Refresh-Wartezeit:;Mount refresh wait:
StaticMountsRefresh;Mounts aktualisieren;Refresh mounts
StaticMountsChecking;Mounts werden geprüft.;Checking mounts.
StaticMountsSelection;Mounts: 0 | Auswahl: -;Mounts: 0 | selection: -
StaticMountStatusNotLoaded;Mount-Status: noch nicht geladen.;Mount status: not loaded yet.
StaticRefreshMountListHint;Aktualisiere die Mount-Liste oder wähle einen Mount aus.;Refresh the mount list or select a mount.
StaticChooseMsuCab;MSU/CAB wählen;Choose MSU/CAB
StaticNextSteps;Nächste Schritte;Next steps
StaticBuildIso;Neue ISO bauen;Build new ISO
StaticReadonlyDefault;Neue Mounts standardmäßig als ReadOnly anlegen;Create new mounts as read-only by default
StaticNoBuildStarted;Noch kein Build gestartet.;No build started yet.
StaticNoCatalogSelected;Noch kein Catalog-Treffer ausgewählt.;No Catalog result selected yet.
StaticNoCatalogSearch;Noch keine Catalog-Suche ausgeführt.;No Catalog search run yet.
StaticNoSourceFiles;Noch keine Quell-Dateien ausgewählt.;No source files selected yet.
StaticNothingSelected;Noch nichts ausgewählt.;Nothing selected yet.
StaticOnlyRealUpdates;Nur echte Updates;Only real updates
StaticOnlyRecommended;Nur empfohlene Treffer;Only recommended results
StaticOnlyKbPackages;Nur Pakete mit KB;Only packages with KB
StaticOnlyImportantPackages;Nur wichtige Pakete;Only important packages
StaticLoadFolder;Ordner laden;Load folder
StaticChooseFolder;Ordner wählen;Choose folder
StaticOriginalFileNameCopy;OriginalFileName kopieren;Copy OriginalFileName
StaticPublishedNameCopy;PublishedName kopieren;Copy PublishedName
StaticPackages;Pakete:;Packages:
StaticPackagesZero;Pakete: 0;Packages: 0
StaticProjectRoot;ProjectRoot:;Project root:
StaticProjectStatusLoading;Projektstatus wird geladen...;Loading project status...
StaticCheck;Prüfen;Check
StaticSource;Quelle;Source
StaticChooseSource;Quelle wählen;Choose source
StaticSourceLabel;Quelle:;Source:
StaticReadOnly;ReadOnly:;Read-only:
StaticRecurse;Recurse (Unterordner);Recurse (subfolders)
StaticRepairCheck;Reparatur prüfen;Check repair
StaticSecondsDism;Sekunden für normale DISM-Befehle.;Seconds for normal DISM commands.
StaticSecondsCommit;Sekunden für Unmount mit Commit. Große WIMs brauchen lange.;Seconds for unmount with commit. Large WIMs take a long time.
StaticSecondsBatchPause;Sekunden Pause zwischen mehreren Commit-Unmounts.;Seconds to pause between multiple commit unmounts.
StaticSecondsRetry;Sekunden zwischen Commit-Retrys.;Seconds between commit retries.
StaticSelectedIndex;Selected Index:;Selected index:
StaticSelected;Selected: -;Selected: -
StaticStandaloneImages;Standalone Images;Standalone images
StaticDefaultDismTimeout;Standard-DISM-Timeout:;Default DISM timeout:
StaticDefaults;Standardwerte;Defaults
StaticStartCatalogHint;Starte die Catalog-Suche oder füge eine lokale MSU/CAB hinzu.;Start a Catalog search or add a local MSU/CAB.
StaticStatusUpper;STATUS;STATUS
StaticRefreshStatus;Status aktualisieren;Refresh status
StaticSearch;Suche:;Search:
StaticUnmountTip;Tipp: Auswahl anklicken, dann Unmount.;Tip: select an item, then unmount.
StaticDashboardTip;Tipp: Das Dashboard soll nur vorbereiten und orientieren. Die eigentliche Arbeit passiert danach in Images, Updates, Driver oder ISO bauen.;Tip: the dashboard is only for preparation and orientation. The actual work happens in Images, Updates, Drivers, or ISO build.
StaticTitle;Titel;Title
StaticCopyTitle;Titel kopieren;Copy title
StaticSelectJobDetails;Job auswählen, um Details zu sehen.;Select a job to see details.
StaticHits;Treffer:;Results:
StaticHitsLocal;Treffer: 0 | Lokal: 0;Results: 0 | local: 0
StaticResultDetails;Treffer-Details;Result details
StaticDrivers;Treiber;Drivers
StaticRemoveDriversSelected;Treiber entfernen (Selected);Remove drivers (selected)
StaticExportDriversCsv;Treiber exportieren (CSV);Export drivers (CSV)
StaticAddDriversFolder;Treiber hinzufügen (Ordner)...;Add drivers (folder)...
StaticAddDrivers;Treiber hinzufügen...;Add drivers...
StaticImageDrivers;Treiber im Image;Drivers in image
StaticDriverCountZero;Treiber: 0;Drivers: 0
StaticExportDriverListCsv;Treiberliste als CSV exportieren;Export driver list as CSV
StaticReloadDriverList;Treiberliste neu laden;Reload driver list
StaticType;Typ;Type
StaticTypeLabel;Typ:;Type:
StaticUpdatesLabel;Updates:;Updates:
StaticChooseUsb;USB wählen;Choose USB
StaticUsbTarget;USB-Ziel:;USB target:
StaticPreview;Vorschau:;Preview:
StaticIntegrateSelectionHint;Wähle einen Treffer und integriere ihn in einen passenden Read/Write-Mount.;Select a result and integrate it into a suitable read/write mount.
StaticIntegrateSelectedMount;In ausgewählten Mount integrieren;Integrate into selected mount
StaticIntegrateAllMounts;In alle passenden Mounts integrieren;Integrate into all matching mounts
StaticTools;Werkzeuge;Tools
StaticDismLockWait;Wie lange ein Befehl auf den DISM-Mutex wartet.;How long a command waits for the DISM mutex.
StaticRetryLockedWim;Wiederholungen bei gesperrter WIM oder Registry-Handles.;Retries for locked WIMs or registry handles.
StaticAddWimEsd;WIM/ESD hinzufügen;Add WIM/ESD
StaticWimEsdIndexes;WIM/ESD Indexe;WIM/ESD indexes
StaticSaveWimEsd;WIM/ESD speichern;Save WIM/ESD
StaticChooseWimEsd;WIM/ESD wählen;Choose WIM/ESD
StaticLoadIndexes;Indexe laden;Load indexes
StaticReloadIndexes;Indexe neu laden;Reload indexes
StaticCopyImagePath;Image-Pfad kopieren;Copy image path
StaticWinPeRoot;WinPE Root:;WinPE root:
StaticTime;Zeit;Time
StaticTimeLabel;Zeit:;Time:
StaticState;Zustand;State
StaticSourceIsoDescription;Die gemountete Windows-ISO ist die Grundlage. Du kannst bei Bedarf ein anderes Install-Image oder eine andere boot.wim einsetzen und daraus eine neue bootfähige ISO bauen.;The mounted Windows ISO is the base. If needed, you can use a different install image or another boot.wim to build a new bootable ISO.
StaticUsbHint;Hinweis: Für UEFI-Boot muss der Stick passend vorbereitet sein. Das Tool kopiert hier nur Dateien.;Note: for UEFI boot, the stick must be prepared appropriately. This tool only copies files here.
StaticSuitabilityLoading;Eignung: Mount-Kontext wird geladen.;Suitability: loading mount context.
StaticDismBatchGroup;DISM & Batch-Verhalten;DISM & batch behavior
StaticDismBatchSave;DISM/Batch speichern;Save DISM/batch settings
StaticDismLockTimeout;DISM-Lock-Timeout:;DISM lock timeout:
StaticBootImage;Boot-Image:;Boot image:
StaticInstallImage;Install-Image:;Install image:
StaticChooseInstallImage;Install-Image wählen;Choose install image
StaticBuildInstallImage;Install-Image bauen;Build install image
StaticInstalledPackages;Installierte Pakete;Installed packages
StaticResetInstall;Install zurücksetzen;Reset install
StaticResetBootImage;Boot zurücksetzen;Reset boot
StaticBuildInstallEsd;install.esd bauen (kleiner, kann bei großen Images sehr lange dauern);Build install.esd (smaller, can take a very long time with large images)
StaticBuildInstallWim;install.wim bauen (empfohlen, deutlich schneller, Datei größer);Build install.wim (recommended, much faster, larger file)
StaticMountedImagesGerman;Gemountete Images;Mounted images
StaticMountedImages;Mounted Images;Mounted images
StaticIsoSources;ISO Quellen;ISO sources
StaticIsoBuild;ISO bauen;Build ISO
StaticUnmountIso;ISO aushängen;Dismount ISO
StaticMountIso;ISO mounten;Mount ISO
StaticChooseIso;ISO wählen;Choose ISO
StaticMountedImageDrivers;Treiber im Image;Drivers in image
StaticLocalMsuCab;MSU/CAB;MSU/CAB
'@ | ConvertFrom-Csv -Delimiter ';'

foreach ($row in @($script:UiStaticTextTranslations)) {
    $key = [string]$row.Key
    if ([string]::IsNullOrWhiteSpace($key)) { continue }

    $script:UiTranslations['de'][$key] = [string]$row.de
    $script:UiTranslations['en'][$key] = [string]$row.en
}

function Get-LocalizationConfigValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter()]$Default = $null
    )

    if (-not $script:getConfigValueCommand) {
        throw "Get-ConfigValue ist nicht verfügbar."
    }

    return (& $script:getConfigValueCommand -Key $Key -Default $Default)
}

function Set-LocalizationConfigValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter()]$Value,
        [switch]$Persist
    )

    if (-not $script:setConfigValueCommand) {
        throw "Set-ConfigValue ist nicht verfügbar."
    }

    return (& $script:setConfigValueCommand -Key $Key -Value $Value -Persist:$Persist)
}

function Get-UiLanguage {
    [CmdletBinding()]
    param()

    $lang = [string](Get-LocalizationConfigValue -Key 'UiLanguage' -Default 'de')
    if ($lang -notin @('de', 'en')) {
        return 'de'
    }
    return $lang
}

function Set-UiLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('de', 'en')]
        [string]$Language
    )

    Set-LocalizationConfigValue -Key 'UiLanguage' -Value $Language -Persist | Out-Null
    return $Language
}

function Get-UiString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [string]$Language = $(Get-UiLanguage),
        [object[]]$Args = @()
    )

    if (-not $script:UiTranslations.ContainsKey($Language)) {
        $Language = 'de'
    }

    $table = $script:UiTranslations[$Language]
    $value = if ($table.ContainsKey($Key)) { [string]$table[$Key] } else { [string]$Key }
    if (@($Args).Count -gt 0) {
        return ($value -f $Args)
    }

    return $value
}

function Get-LocalizedText {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [string]$Language = $(Get-UiLanguage)
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    foreach ($langTable in $script:UiTranslations.Values) {
        foreach ($key in $langTable.Keys) {
            $deValue = $script:UiTranslations['de'][$key]
            $enValue = $script:UiTranslations['en'][$key]
            if (($Text -eq [string]$deValue) -or ($Text -eq [string]$enValue)) {
                return Get-UiString -Key $key -Language $Language
            }
        }
    }

    return $Text
}

function Set-UiElementText {
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)][string]$PropertyName,
        [Parameter(Mandatory)][string]$Text
    )

    if (-not $Element) { return }
    if ($Element.PSObject.Properties.Match($PropertyName).Count -gt 0) {
        try { $Element.$PropertyName = $Text } catch {}
    }
}

function Set-LocalizedElementProperty {
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)][string]$PropertyName,
        [Parameter(Mandatory)][string]$Language
    )

    if (-not $Element) { return }
    if ($Element.PSObject.Properties.Match($PropertyName).Count -lt 1) { return }

    $value = $null
    try { $value = $Element.$PropertyName } catch { return }
    if ($value -isnot [string]) { return }
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return }

    $localized = Get-LocalizedText -Text ([string]$value) -Language $Language
    if ($localized -ne [string]$value) {
        try { $Element.$PropertyName = $localized } catch {}
    }
}

function Add-LocalizationChild {
    param(
        [Parameter(Mandatory)][System.Collections.Queue]$Queue,
        [AllowNull()]$Child
    )

    if ($null -ne $Child -and ($Child -isnot [string])) {
        try { $Queue.Enqueue($Child) } catch {}
    }
}

function Add-LocalizationChildren {
    param(
        [Parameter(Mandatory)][System.Collections.Queue]$Queue,
        [Parameter(Mandatory)]$Element
    )

    try { Add-LocalizationChild -Queue $Queue -Child $Element.ContextMenu } catch {}
    try { Add-LocalizationChild -Queue $Queue -Child $Element.ToolTip } catch {}
    try { Add-LocalizationChild -Queue $Queue -Child $Element.Content } catch {}
    try { Add-LocalizationChild -Queue $Queue -Child $Element.Header } catch {}
    try { Add-LocalizationChild -Queue $Queue -Child $Element.View } catch {}

    try {
        foreach ($column in @($Element.Columns)) {
            Add-LocalizationChild -Queue $Queue -Child $column
        }
    } catch {}

    try {
        foreach ($column in @($Element.View.Columns)) {
            Add-LocalizationChild -Queue $Queue -Child $column
        }
    } catch {}

    try {
        foreach ($item in @($Element.Items)) {
            Add-LocalizationChild -Queue $Queue -Child $item
        }
    } catch {}

    try {
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Element)) {
            Add-LocalizationChild -Queue $Queue -Child $child
        }
    } catch {}

    try {
        if ($Element -is [System.Windows.DependencyObject]) {
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
            for ($i = 0; $i -lt $count; $i++) {
                Add-LocalizationChild -Queue $Queue -Child ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i))
            }
        }
    } catch {}
}

function Apply-LocalizationByCurrentText {
    param(
        [Parameter(Mandatory)]$Root,
        [Parameter(Mandatory)][string]$Language
    )

    $queue = New-Object System.Collections.Queue
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    Add-LocalizationChild -Queue $queue -Child $Root

    while ($queue.Count -gt 0) {
        $element = $queue.Dequeue()
        if ($null -eq $element) { continue }

        $hash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($element)
        if (-not $seen.Add($hash)) { continue }

        foreach ($propertyName in @('Title', 'Text', 'Content', 'Header', 'ToolTip')) {
            Set-LocalizedElementProperty -Element $element -PropertyName $propertyName -Language $Language
        }

        Add-LocalizationChildren -Queue $queue -Element $element
    }
}

function Apply-LocalizationToRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Root,
        [string]$Language = $(Get-UiLanguage)
    )

    if ($Root -and $Root.PSObject.Properties.Match('Title').Count -gt 0) {
        try { $Root.Title = (Get-UiString -Key 'WindowTitle' -Language $Language) } catch {}
    }

    $namedValues = @{
        TxtMainTitle = @{ Text = 'WindowTitle' }
        TxtMainSubtitle = @{ Text = 'HeaderSubtitle' }
        BtnDashboard = @{ Content = 'NavDashboard' }
        BtnImages = @{ Content = 'NavImages' }
        BtnMedia = @{ Content = 'NavMedia' }
        BtnDriver = @{ Content = 'NavDriver' }
        BtnUpdates = @{ Content = 'NavUpdates' }
        BtnSettings = @{ Content = 'NavSettings' }
        TxtShellState = @{ Text = 'ShellState' }
        TxtStatus = @{ Text = 'ShellReady' }
        TxtSettingsPageTitle = @{ Text = 'SettingsPageTitle' }
        GrpSettingsDefaults = @{ Header = 'SettingsBehavior' }
        TxtSettingsStartPageLabel = @{ Text = 'SettingsStartPage' }
        TxtSettingsLanguageLabel = @{ Text = 'SettingsLanguage' }
        TxtSettingsDriverViewLabel = @{ Text = 'SettingsDriverView' }
        ChkSettingsDriverLoadAllDefault = @{ Content = 'SettingsDriverLoadAll' }
        TxtSettingsUpdatesLabel = @{ Text = 'SettingsUpdates' }
        ChkSettingsUpdatesAutoCatalogDefault = @{ Content = 'SettingsAutoCatalog' }
        TxtSettingsNewMountsLabel = @{ Text = 'SettingsNewMounts' }
        ChkSettingsImageMountReadOnlyDefault = @{ Content = 'SettingsMountReadOnly' }
        TxtSettingsNotificationsLabel = @{ Text = 'SettingsNotifications' }
        ChkSettingsNotificationsEnabled = @{ Content = 'SettingsNotificationsEnabled' }
        BtnSettingsTestNotification = @{ Content = 'SettingsTestNotification' }
        TxtSettingsDebugLabel = @{ Text = 'SettingsDebug' }
        ChkSettingsAppDebug = @{ Content = 'SettingsDebugEnabled' }
        CmbItemStartPageDashboard = @{ Content = 'NavDashboard' }
        CmbItemStartPageImages = @{ Content = 'NavImages' }
        CmbItemStartPageMedia = @{ Content = 'StartPageMedia' }
        CmbItemStartPageDriver = @{ Content = 'NavDriver' }
        CmbItemStartPageUpdates = @{ Content = 'NavUpdates' }
        CmbItemStartPageSettings = @{ Content = 'NavSettings' }
        CmbItemLanguageDe = @{ Content = 'SettingsLangGerman' }
        CmbItemLanguageEn = @{ Content = 'SettingsLangEnglish' }
        GrpSettingsAdk = @{ Header = 'GroupAdk' }
        BtnSettingsDetectAdk = @{ Content = 'BtnDetectAdk' }
        BtnSettingsPickAdkRoot = @{ Content = 'BtnPickAdk' }
        BtnSettingsPickWinPeRoot = @{ Content = 'BtnPickWinPe' }
        BtnSettingsPickOscdimgPath = @{ Content = 'BtnPickOscdimg' }
        GrpSettingsHealth = @{ Header = 'GroupHealth' }
        BtnSettingsHealthRefresh = @{ Content = 'BtnHealthRefresh' }
        BtnSettingsUnmountAllDiscard = @{ Content = 'BtnUnmountAll' }
        BtnSettingsCleanupEmptyMountDirs = @{ Content = 'BtnCleanupMountDirs' }
        TxtSettingsHealthFreeSpaceLabel = @{ Text = 'HealthFreeSpace' }
        TxtSettingsHealthActiveMountsLabel = @{ Text = 'HealthActiveMounts' }
        TxtSettingsMountedImagesTitle = @{ Text = 'MountedImages' }
        TxtSettingsHealthHint = @{ Text = 'HealthHint' }
        GrpSettingsLogs = @{ Header = 'GroupLogs' }
        BtnSettingsLogsRefresh = @{ Content = 'BtnLogsRefresh' }
        BtnSettingsOpenLogFolder = @{ Content = 'BtnOpenLogFolder' }
        BtnSettingsOpenCurrentLog = @{ Content = 'BtnOpenCurrentLog' }
        BtnSettingsOpenDismLog = @{ Content = 'BtnOpenDismLog' }
        BtnSettingsCleanupOldLogs = @{ Content = 'BtnCleanupOldLogs' }
        TxtSettingsAppLogPathLabel = @{ Text = 'LogsAppPath' }
        TxtSettingsDismLogPathLabel = @{ Text = 'LogsDismPath' }
        TxtSettingsLogPreviewSourceLabel = @{ Text = 'LogsPreviewSource' }
        CmbItemLogPreviewApp = @{ Content = 'LogsPreviewApp' }
        CmbItemLogPreviewDism = @{ Content = 'LogsPreviewDism' }
        TxtSettingsLogFilesTitle = @{ Text = 'LogsFilesTitle' }
        TxtSettingsLogPreviewTitle = @{ Text = 'LogsPreviewTitle' }
        TxtSettingsLogsHint = @{ Text = 'LogsHint' }
        GrpSettingsMountRoot = @{ Header = 'GroupMountRoot' }
        BtnSettingsPickMountRoot = @{ Content = 'BtnPickFolder' }
        GrpSettingsInfo = @{ Header = 'GroupInfo' }
    }

    foreach ($elementName in $namedValues.Keys) {
        $element = $null
        try { $element = Find-Ui -Root $Root -Name $elementName } catch {}
        if (-not $element) { continue }

        foreach ($propertyName in $namedValues[$elementName].Keys) {
            $textKey = [string]$namedValues[$elementName][$propertyName]
            Set-UiElementText -Element $element -PropertyName $propertyName -Text (Get-UiString -Key $textKey -Language $Language)
        }
    }

    Apply-LocalizationByCurrentText -Root $Root -Language $Language
}

Export-ModuleMember -Function `
    Get-UiLanguage, `
    Set-UiLanguage, `
    Get-UiString, `
    Get-LocalizedText, `
    Apply-LocalizationToRoot
