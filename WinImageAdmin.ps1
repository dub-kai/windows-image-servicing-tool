[CmdletBinding()]
param(
    [ValidateSet("Dashboard", "Images", "Media", "Driver", "Updates", "Settings")]
    [string]$StartPage,

    [switch]$AppDebug,

    [string]$ProjectRoot,

    [switch]$SkipStaCheck,
    [switch]$SkipAdminCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Ensure-STA {
    param([hashtable]$RelaunchParams)

    if ($SkipStaCheck) { return }

    $state = $null
    try { $state = [System.Threading.Thread]::CurrentThread.ApartmentState } catch { $state = $null }

    if ($state -ne "STA") {
        Write-Host "Nicht-STA erkannt ($state). Relaunch in STA..." -ForegroundColor Yellow
        $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = "powershell.exe" }

        $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-STA","-File","`"$PSCommandPath`"")
        foreach ($k in $RelaunchParams.Keys) {
            $v = $RelaunchParams[$k]
            if ($v -is [bool]) {
                if ($v) { $argList += "-$k" }
            }
            elseif ($null -ne $v -and $v -ne "") {
                $argList += "-$k"
                $argList += "`"$v`""
            }
        }

        $argList += "-SkipStaCheck"
        Start-Process -FilePath $psExe -ArgumentList $argList | Out-Null
        exit 0
    }
}

function Ensure-Admin {
    param([hashtable]$RelaunchParams)

    if ($SkipAdminCheck) { return }

    if (-not (Test-IsAdministrator)) {
        Write-Host "Nicht als Admin gestartet. Relaunch mit Adminrechten..." -ForegroundColor Yellow
        $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = "powershell.exe" }

        $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-STA","-File","`"$PSCommandPath`"")
        foreach ($k in $RelaunchParams.Keys) {
            $v = $RelaunchParams[$k]
            if ($v -is [bool]) {
                if ($v) { $argList += "-$k" }
            }
            elseif ($null -ne $v -and $v -ne "") {
                $argList += "-$k"
                $argList += "`"$v`""
            }
        }

        $argList += "-SkipAdminCheck"
        $argList += "-SkipStaCheck"
        Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs | Out-Null
        exit 0
    }
}

function New-StartupSplash {
    param(
        [string]$ProjectRootPath,
        [string]$InitialStatus = "Programmstart wird vorbereitet..."
    )

    try {
        Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase | Out-Null
    } catch {
        return $null
    }

    try {
        $window = New-Object System.Windows.Window
        $window.Title = "Win Image Admin startet..."
        $window.Width = 560
        $window.Height = 250
        $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
        $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        $window.WindowStyle = [System.Windows.WindowStyle]::None
        $window.ShowInTaskbar = $false
        $window.Topmost = $true
        $window.Background = [System.Windows.Media.Brushes]::White

        $outerBorder = New-Object System.Windows.Controls.Border
        $outerBorder.BorderThickness = '1'
        $outerBorder.BorderBrush = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#D1D5DB'))
        $outerBorder.Background = [System.Windows.Media.Brushes]::White

        $root = New-Object System.Windows.Controls.Grid

        $row1 = New-Object System.Windows.Controls.RowDefinition
        $row1.Height = [System.Windows.GridLength]::Auto
        [void]$root.RowDefinitions.Add($row1)

        $row2 = New-Object System.Windows.Controls.RowDefinition
        $row2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        [void]$root.RowDefinitions.Add($row2)

        $row3 = New-Object System.Windows.Controls.RowDefinition
        $row3.Height = [System.Windows.GridLength]::Auto
        [void]$root.RowDefinitions.Add($row3)

        $header = New-Object System.Windows.Controls.Border
        $header.Background = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#1F2937'))
        $header.Padding = '18'
        [System.Windows.Controls.Grid]::SetRow($header, 0)

        $titleStack = New-Object System.Windows.Controls.StackPanel
        $titleStack.Orientation = [System.Windows.Controls.Orientation]::Vertical

        $txtTitle = New-Object System.Windows.Controls.TextBlock
        $txtTitle.Text = 'Win Image Admin (Next)'
        $txtTitle.FontSize = 22
        $txtTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
        $txtTitle.Foreground = [System.Windows.Media.Brushes]::White

        $txtSubtitle = New-Object System.Windows.Controls.TextBlock
        $txtSubtitle.Text = 'Programm wird geladen...'
        $txtSubtitle.FontSize = 12
        $txtSubtitle.Foreground = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#D1D5DB'))

        [void]$titleStack.Children.Add($txtTitle)
        [void]$titleStack.Children.Add($txtSubtitle)
        $header.Child = $titleStack

        $content = New-Object System.Windows.Controls.StackPanel
        $content.Margin = '22,18,22,18'
        [System.Windows.Controls.Grid]::SetRow($content, 1)

        $txtInfo = New-Object System.Windows.Controls.TextBlock
        $txtInfo.Text = 'Bitte kurz warten. Module, Services und Oberfläche werden vorbereitet.'
        $txtInfo.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $txtInfo.Margin = '0,0,0,12'
        $txtInfo.Foreground = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#111827'))
        $txtInfo.FontSize = 13

        $txtStatus = New-Object System.Windows.Controls.TextBlock
        $txtStatus.Text = $InitialStatus
        $txtStatus.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $txtStatus.Margin = '0,0,0,14'
        $txtStatus.Foreground = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#374151'))
        $txtStatus.FontSize = 14
        $txtStatus.FontWeight = [System.Windows.FontWeights]::SemiBold

        $progress = New-Object System.Windows.Controls.ProgressBar
        $progress.IsIndeterminate = $true
        $progress.Height = 14
        $progress.Minimum = 0
        $progress.Maximum = 100

        [void]$content.Children.Add($txtInfo)
        [void]$content.Children.Add($txtStatus)
        [void]$content.Children.Add($progress)

        $footer = New-Object System.Windows.Controls.Border
        $footer.Padding = '18,10,18,12'
        $footer.Background = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#F9FAFB'))
        [System.Windows.Controls.Grid]::SetRow($footer, 2)

        $txtFooter = New-Object System.Windows.Controls.TextBlock
        $txtFooter.Text = 'Fenster bleibt sichtbar, bis die Hauptoberfläche vollständig bereit ist.'
        $txtFooter.Foreground = ([System.Windows.Media.BrushConverter]::new().ConvertFromString('#6B7280'))
        $txtFooter.FontSize = 11
        $footer.Child = $txtFooter

        [void]$root.Children.Add($header)
        [void]$root.Children.Add($content)
        [void]$root.Children.Add($footer)

        $outerBorder.Child = $root
        $window.Content = $outerBorder
        $window.Tag = @{ StatusText = $txtStatus }

        $window.Show()
        [void]$window.Activate()
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [Action]{},
            [System.Windows.Threading.DispatcherPriority]::Background
        )

        return $window
    } catch {
        return $null
    }
}

function Update-StartupSplash {
    param(
        [object]$SplashWindow,
        [string]$Status
    )

    if (-not $SplashWindow) { return }

    try {
        $tag = $SplashWindow.Tag
        if ($tag -and $tag.ContainsKey('StatusText') -and $tag['StatusText']) {
            $tag['StatusText'].Text = $Status
        }

        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [Action]{},
            [System.Windows.Threading.DispatcherPriority]::Background
        )
    } catch {}
}

$relaunch = @{
    StartPage   = $StartPage
    AppDebug    = [bool]$AppDebug
    ProjectRoot = $ProjectRoot
}

Ensure-STA   -RelaunchParams $relaunch
Ensure-Admin -RelaunchParams $relaunch

$scriptDir = Split-Path -Parent $PSCommandPath
$bootstrapPath = Join-Path $scriptDir "Core\Bootstrap.psm1"
if (-not (Test-Path -LiteralPath $bootstrapPath)) {
    throw "Bootstrap nicht gefunden: $bootstrapPath"
}
Import-Module $bootstrapPath -Force

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $scriptDir }
Set-ProjectRoot -Path $ProjectRoot | Out-Null

$splash = New-StartupSplash -ProjectRootPath $ProjectRoot -InitialStatus 'Grundsystem wird initialisiert...'

$null = New-Item -ItemType Directory -Path (Resolve-ProjectPath "Work")        -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Path (Resolve-ProjectPath "Work\Mounts") -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Path (Resolve-ProjectPath "Work\Logs")   -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Path (Resolve-ProjectPath "Work\Temp")   -Force -ErrorAction SilentlyContinue

Update-StartupSplash -SplashWindow $splash -Status 'Core-Module werden geladen...'
Import-Module (Resolve-ProjectPath "Core\Config.psm1"   -MustExist) -Force
Import-Module (Resolve-ProjectPath "Core\AppState.psm1" -MustExist) -Force
Import-Module (Resolve-ProjectPath "Core\Logger.psm1"   -MustExist) -Force

$configOverrides = @{}
if ($PSBoundParameters.ContainsKey('StartPage')) {
    $configOverrides['StartPage'] = $StartPage
}
if ($PSBoundParameters.ContainsKey('AppDebug')) {
    $configOverrides['AppDebug'] = [bool]$AppDebug
}

Initialize-Config -Overrides $configOverrides | Out-Null

Initialize-Logger | Out-Null

Write-Log -Level INFO -Message "===== WinImageAdmin START =====" -ToConsole
Write-Log -Level INFO -Message ("ProjectRoot={0}" -f (Get-ProjectRoot)) -ToConsole
Write-Log -Level INFO -Message ("StartPage={0}" -f (Get-ConfigValue -Key "StartPage")) -ToConsole
Write-Log -Level INFO -Message ("AppDebug={0}" -f (Get-ConfigValue -Key "AppDebug")) -ToConsole
Write-Log -Level INFO -Message ("LogFile={0}" -f (Get-LogFilePath)) -ToConsole

Initialize-AppState -Initial @{ StartPage = (Get-ConfigValue -Key "StartPage") } | Out-Null

$legacy1 = Resolve-ProjectPath "UI\Mount"
$legacy2 = Resolve-ProjectPath "Mount"

try {
    if (Test-Path -LiteralPath $legacy1) {
        Write-Log -Level WARN -Message ("Legacy folder present (unused): {0}" -f $legacy1) -ToConsole
    }
    if (Test-Path -LiteralPath $legacy2) {
        Write-Log -Level WARN -Message ("Legacy folder present (unused): {0}" -f $legacy2) -ToConsole
    }
} catch {}

Update-StartupSplash -SplashWindow $splash -Status 'Services werden geladen...'

$isoServicePath        = Resolve-ProjectPath "Services\IsoService.psm1"
$isoDetectServicePath  = Resolve-ProjectPath "Services\IsoDetectService.psm1"
$imageServicePath      = Resolve-ProjectPath "Services\ImageService.psm1"
$dismServicePath       = Resolve-ProjectPath "Services\DismService.psm1"
$wimInfoServicePath    = Resolve-ProjectPath "Services\WimInfoService.psm1"
$mountServicePath      = Resolve-ProjectPath "Services\MountService.psm1"
$mountedWimServicePath = Resolve-ProjectPath "Services\MountedWimService.psm1"
$isoBuildServicePath   = Resolve-ProjectPath "Services\IsoBuildService.psm1"
$imageComposePath      = Resolve-ProjectPath "Services\ImageCompositionService.psm1"

foreach ($p in @(
    $isoServicePath,
    $isoDetectServicePath,
    $imageServicePath,
    $dismServicePath,
    $wimInfoServicePath,
    $mountServicePath,
    $mountedWimServicePath,
    $isoBuildServicePath,
    $imageComposePath
)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Fehlt: $p" }
}

Import-Module $isoServicePath        -Force
Import-Module $isoDetectServicePath  -Force
Import-Module $imageServicePath      -Force
Import-Module $dismServicePath       -Force
Import-Module $wimInfoServicePath    -Force
Import-Module $mountServicePath      -Force
Import-Module $mountedWimServicePath -Force
Import-Module $isoBuildServicePath   -Force
Import-Module $imageComposePath      -Force

Write-Log -Level INFO -Message "SERVICES_OK: Iso + IsoDetect + Image + DISM + WimInfo + Mount + MountedWim importiert" -ToConsole

foreach ($fn in @(
    "Select-IsoFile","Select-ImageFile",
    "Get-MountedIsoRoots","Find-MountedWindowsInstallMedia","Sync-IsoStateFromMountedMedia",
    "Invoke-Dism",
    "Get-WimImageList",
    "Mount-WimImage","Unmount-WimImage",
    "Get-MountedWimList"
)) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        throw "Service-Funktion fehlt nach Import: $fn"
    }
}

Update-StartupSplash -SplashWindow $splash -Status 'Benutzeroberfläche wird vorbereitet...'
Import-Module (Resolve-ProjectPath "UI\Xaml.psm1" -MustExist) -Force
Import-Module (Resolve-ProjectPath "UI\MainWindow.psm1" -MustExist) -Force

Write-Log -Level INFO -Message "UI initialisiert -> Start-MainWindow" -ToConsole
Update-StartupSplash -SplashWindow $splash -Status 'Hauptfenster wird geöffnet...'

try {
    Start-MainWindow -SplashWindow $splash
} finally {
    try {
        if ($splash -and $splash.IsVisible) {
            $splash.Close()
        }
    } catch {}
}

Write-Log -Level INFO -Message "===== WinImageAdmin EXIT =====" -ToConsole
