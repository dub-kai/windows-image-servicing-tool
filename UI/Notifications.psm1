Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ToastAppId = 'DubKai.WindowsImageServicingTool'
$script:ToastShortcutName = 'Windows Image Servicing Tool.lnk'
$script:NotificationsInitialized = $false
$script:NotificationsInitFailed = $false
$script:NotificationFailureLogged = $false

function Get-AppNotificationString {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Default,
        [object[]]$Args = @()
    )

    try {
        if (Get-Command Get-UiString -ErrorAction SilentlyContinue) {
            return (Convert-AppNotificationEscapedText -Text (Get-UiString -Key $Key -Args $Args))
        }
    } catch {}

    if (@($Args).Count -gt 0) {
        try { return (Convert-AppNotificationEscapedText -Text ($Default -f $Args)) } catch {}
    }

    return (Convert-AppNotificationEscapedText -Text $Default)
}

function Convert-AppNotificationEscapedText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $Text }
    return ([string]$Text).Replace('`r', "`r").Replace('`n', "`n")
}

function Get-AppNotificationConfigBool {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][bool]$Default
    )

    try {
        if (Get-Command Get-ConfigValue -ErrorAction SilentlyContinue) {
            return [bool](Get-ConfigValue -Key $Key -Default $Default)
        }
    } catch {}

    return $Default
}

function Get-AppNotificationConfigInt {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][int]$Default,
        [int]$Min = 0,
        [int]$Max = 86400
    )

    $value = $Default
    try {
        if (Get-Command Get-ConfigValue -ErrorAction SilentlyContinue) {
            $value = [int](Get-ConfigValue -Key $Key -Default $Default)
        }
    } catch {
        $value = $Default
    }

    if ($value -lt $Min) { return $Min }
    if ($value -gt $Max) { return $Max }
    return $value
}

function Test-AppNotificationsEnabled {
    [CmdletBinding()]
    param()

    return (Get-AppNotificationConfigBool -Key 'NotificationsEnabled' -Default $true)
}

function Add-AppNotificationDesktopInteropType {
    if ('WinImageAdmin.Notifications.DesktopShortcut' -as [type]) { return }

    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WinImageAdmin.Notifications
{
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    public class ShellLink { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    public interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0000010B-0000-0000-C000-000000000046")]
    public interface IPersistFile
    {
        void GetClassID(out Guid pClassID);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;

        public PROPERTYKEY(Guid fmtid, uint pid)
        {
            this.fmtid = fmtid;
            this.pid = pid;
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant : IDisposable
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pointerValue;

        public static PropVariant FromString(string value)
        {
            PropVariant result = new PropVariant();
            result.vt = 31;
            result.pointerValue = Marshal.StringToCoTaskMemUni(value);
            return result;
        }

        public void Dispose()
        {
            PropVariantClear(ref this);
        }

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PropVariant pvar);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    public interface IPropertyStore
    {
        void GetCount(out uint cProps);
        void GetAt(uint iProp, out PROPERTYKEY pkey);
        void GetValue(ref PROPERTYKEY key, out PropVariant pv);
        void SetValue(ref PROPERTYKEY key, ref PropVariant pv);
        void Commit();
    }

    public static class DesktopShortcut
    {
        private static readonly PROPERTYKEY AppUserModelIdKey =
            new PROPERTYKEY(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int SHGetPropertyStoreFromParsingName(
            string pszPath,
            IntPtr pbc,
            uint flags,
            ref Guid riid,
            out IntPtr propertyStore);

        public static void SetAppId(string shortcutPath, string appId)
        {
            Guid propertyStoreGuid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            IntPtr propertyStorePtr;
            int hr = SHGetPropertyStoreFromParsingName(shortcutPath, IntPtr.Zero, 0x00000002, ref propertyStoreGuid, out propertyStorePtr);
            if (hr != 0)
            {
                Marshal.ThrowExceptionForHR(hr);
            }

            IPropertyStore propertyStore = (IPropertyStore)Marshal.GetTypedObjectForIUnknown(propertyStorePtr, typeof(IPropertyStore));
            try
            {
                PROPERTYKEY key = AppUserModelIdKey;
                PropVariant appIdValue = PropVariant.FromString(appId);
                try
                {
                    propertyStore.SetValue(ref key, ref appIdValue);
                    propertyStore.Commit();
                }
                finally
                {
                    appIdValue.Dispose();
                }
            }
            finally
            {
                if (propertyStorePtr != IntPtr.Zero) { Marshal.Release(propertyStorePtr); }
            }
        }

        public static void Create(string shortcutPath, string targetPath, string arguments, string workingDirectory, string iconPath, string appId)
        {
            IShellLinkW link = (IShellLinkW)new ShellLink();
            link.SetPath(targetPath);
            link.SetArguments(arguments);
            if (!String.IsNullOrWhiteSpace(workingDirectory)) { link.SetWorkingDirectory(workingDirectory); }
            if (!String.IsNullOrWhiteSpace(iconPath)) { link.SetIconLocation(iconPath, 0); }

            IPersistFile file = (IPersistFile)link;
            file.Save(shortcutPath, true);

            SetAppId(shortcutPath, appId);
        }
    }

    public static class AppUserModelId
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    }
}
"@
}

function Get-AppNotificationShortcutPath {
    [CmdletBinding()]
    param()

    $programs = [Environment]::GetFolderPath('Programs')
    if ([string]::IsNullOrWhiteSpace($programs)) {
        $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    }

    return (Join-Path $programs $script:ToastShortcutName)
}

function Register-AppNotificationShortcut {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = $(try { Get-ProjectRoot } catch { (Get-Location).Path })
    )

    Add-AppNotificationDesktopInteropType

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $ProjectRoot = try { Get-ProjectRoot } catch { (Get-Location).Path }
    }

    $shortcutPath = Get-AppNotificationShortcutPath
    $shortcutDir = [System.IO.Path]::GetDirectoryName($shortcutPath)
    if (-not (Test-Path -LiteralPath $shortcutDir)) {
        $null = New-Item -ItemType Directory -Path $shortcutDir -Force
    }

    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe -PathType Leaf)) { $psExe = 'powershell.exe' }

    $appScript = Join-Path $ProjectRoot 'WinImageAdmin.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $appScript.Replace('"', '""')
    $iconPath = $psExe

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $psExe
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $ProjectRoot
    $shortcut.IconLocation = $iconPath
    $shortcut.Description = 'Windows Image Servicing Tool'
    $shortcut.Save()

    [WinImageAdmin.Notifications.DesktopShortcut]::SetAppId($shortcutPath, $script:ToastAppId)

    return $shortcutPath
}

function Initialize-AppNotifications {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = $(try { Get-ProjectRoot } catch { (Get-Location).Path })
    )

    if ($script:NotificationsInitialized) { return $true }
    if ($script:NotificationsInitFailed) { return $false }
    if (-not (Test-AppNotificationsEnabled)) { return $false }

    try {
        Add-AppNotificationDesktopInteropType
        [void][WinImageAdmin.Notifications.AppUserModelId]::SetCurrentProcessExplicitAppUserModelID($script:ToastAppId)
        $shortcutPath = Register-AppNotificationShortcut -ProjectRoot $ProjectRoot
        $script:NotificationsInitialized = $true
        try { Write-Log -Level INFO -Message ("Notifications: Toast AppId registered. Shortcut={0}" -f $shortcutPath) } catch {}
        return $true
    } catch {
        $script:NotificationsInitFailed = $true
        try { Write-Log -Level WARN -Message ("Notifications: Initialisierung fehlgeschlagen: {0}" -f $_.Exception.Message) } catch {}
        return $false
    }
}

function ConvertTo-AppToastXmlText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return '' }
    return [System.Security.SecurityElement]::Escape([string]$Text)
}

function Show-AppToastNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Success','Warning','Error')][string]$Level = 'Info'
    )

    if (-not (Test-AppNotificationsEnabled)) { return $false }
    if (-not (Initialize-AppNotifications)) { return $false }

    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $scenario = if ($Level -eq 'Error') { 'scenario="reminder"' } else { '' }
        $duration = if ($Level -eq 'Error') { 'duration="long"' } else { '' }
        $safeTitle = ConvertTo-AppToastXmlText -Text $Title
        $safeMessage = ConvertTo-AppToastXmlText -Text $Message

        $toastXml = @"
<toast $duration $scenario launch="winimageadmin://open">
  <visual>
    <binding template="ToastGeneric">
      <text>$safeTitle</text>
      <text>$safeMessage</text>
    </binding>
  </visual>
</toast>
"@

        $xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $xml.LoadXml($toastXml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($script:ToastAppId)
        $notifier.Show($toast)
        return $true
    } catch {
        if (-not $script:NotificationFailureLogged) {
            $script:NotificationFailureLogged = $true
            try { Write-Log -Level WARN -Message ("Notifications: Toast konnte nicht angezeigt werden: {0}" -f $_.Exception.Message) } catch {}
        }
        return $false
    }
}

function Format-AppNotificationDuration {
    param([Nullable[int64]]$DurationMs = $null)

    if ($null -eq $DurationMs) { return '-' }

    $span = [TimeSpan]::FromMilliseconds([double]$DurationMs)
    if ($span.TotalHours -ge 1) { return ('{0:hh\:mm\:ss}' -f $span) }
    return ('{0:mm\:ss}' -f $span)
}

function Test-UiTaskNotificationEligible {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [ValidateSet('Completed','Failed','Timeout')][string]$Status = 'Completed',
        [Nullable[int64]]$DurationMs = $null
    )

    if (-not (Test-AppNotificationsEnabled)) { return $false }

    $quietPatterns = @(
        'RefreshMounts',
        'LoadSelectedMountContext',
        'MountedWimInfo',
        'Driver:MountedWims',
        '^WimInfo:',
        'Settings:HealthRefresh',
        'Updates:CatalogSearch'
    )

    foreach ($pattern in $quietPatterns) {
        if ($Label -match $pattern) { return $false }
    }

    $importantPatterns = @(
        '^Mount:',
        '^Unmount:',
        '^CopyWim:',
        '^ExportIndex:',
        '^MountRepair:',
        '^Driver:AddDriver',
        '^Driver:RemoveDriver',
        '^Updates:CatalogDownload',
        '^Updates:CatalogIntegrate',
        '^Updates:CatalogIntegrateAll',
        '^Updates:CatalogPreflight',
        '^MediaBuilder:UsbCopy',
        '^MediaBuilder:BuildIso',
        '^MediaBuilder:BuildInstallImage',
        '^Settings:UnmountAllDiscard',
        '^Settings:CleanupEmptyMountDirs'
    )

    foreach ($pattern in $importantPatterns) {
        if ($Label -match $pattern) { return $true }
    }

    if ($Status -ne 'Completed') { return $true }

    $minimumSec = Get-AppNotificationConfigInt -Key 'NotificationMinimumDurationSec' -Default 20 -Min 0 -Max 86400
    if ($null -ne $DurationMs) {
        return ([double]$DurationMs -ge ($minimumSec * 1000.0))
    }

    return $false
}

function Show-UiTaskNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][ValidateSet('Completed','Failed','Timeout')][string]$Status,
        [Nullable[int64]]$DurationMs = $null,
        [string]$Detail = $null,
        [string]$ErrorText = $null
    )

    if (-not (Test-UiTaskNotificationEligible -Label $Label -Status $Status -DurationMs $DurationMs)) {
        return $false
    }

    $durationText = Format-AppNotificationDuration -DurationMs $DurationMs

    if ($Status -eq 'Completed') {
        $title = Get-AppNotificationString -Key 'NotificationJobCompletedTitle' -Default 'Job abgeschlossen'
        $message = Get-AppNotificationString -Key 'NotificationJobCompletedMessageFormat' -Default '{0} abgeschlossen. Laufzeit: {1}' -Args @($Label, $durationText)
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $message = $message + "`n" + $Detail
        }
        return (Show-AppToastNotification -Title $title -Message $message -Level Success)
    }

    $title = Get-AppNotificationString -Key 'NotificationJobFailedTitle' -Default 'Job fehlgeschlagen'
    $body = if ([string]::IsNullOrWhiteSpace($ErrorText)) { $Label } else { $ErrorText }
    if ($body.Length -gt 220) { $body = $body.Substring(0, 217) + '...' }
    $message = Get-AppNotificationString -Key 'NotificationJobFailedMessageFormat' -Default '{0} fehlgeschlagen. Laufzeit: {1}`n{2}' -Args @($Label, $durationText, $body)
    return (Show-AppToastNotification -Title $title -Message $message -Level Error)
}

Export-ModuleMember -Function `
    Initialize-AppNotifications, `
    Register-AppNotificationShortcut, `
    Show-AppToastNotification, `
    Show-UiTaskNotification, `
    Test-AppNotificationsEnabled, `
    Test-UiTaskNotificationEligible
