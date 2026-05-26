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
}

Export-ModuleMember -Function `
    Get-UiLanguage, `
    Set-UiLanguage, `
    Get-UiString, `
    Get-LocalizedText, `
    Apply-LocalizationToRoot
