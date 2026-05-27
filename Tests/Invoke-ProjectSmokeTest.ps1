[CmdletBinding()]
param(
    [string]$ProjectRoot = '',

    [ValidateSet('Basic', 'Full')]
    [string]$Scope = 'Full',

    [string]$SourceWim = 'D:\25H2\Iso\boot.wim',
    [int]$ImageIndex = 1,
    [string]$InstallImage = 'D:\25H2\Iso\install.wim',
    [string]$IsoPath = 'D:\25H2\Win11_24H2_German_x64.iso',
    [string]$LocalUpdatePackage = 'D:\25H2\Updates\Windows11.0-KB5077241-x64.msu',

    [string]$OutputDir,

    [switch]$AllowExistingMounts,
    [switch]$SkipMountLifecycle,
    [switch]$SkipFeatureMount,
    [switch]$SkipGuiStartup,
    [switch]$SkipLiveCatalog,
    [switch]$KeepArtifacts,

    [int]$GuiStartupSeconds = 12
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        try { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $scriptRoot = '' }
    }

    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        throw 'ProjectRoot could not be resolved automatically. Pass -ProjectRoot.'
    }

    $ProjectRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\ProjectSmokeTests'
}

$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("project_smoke_{0}" -f $runStamp)
$progressPath = Join-Path $runDir 'project_smoke_progress.log'
$resultPath = Join-Path $runDir 'project_smoke_result.json'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$script:Results = New-Object System.Collections.Generic.List[object]
$script:MountedFeatureTestDir = $null
$script:StartedAt = Get-Date

function Write-SmokeLine {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $progressPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-SmokeIsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function ConvertTo-SmokeDetail {
    param($Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }

    try {
        $json = $Value | ConvertTo-Json -Depth 8 -Compress
        if ($json.Length -gt 1600) {
            return ($json.Substring(0, 1600) + '...')
        }
        return $json
    } catch {
        return [string]$Value
    }
}

function Add-SmokeResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('OK', 'FAIL', 'SKIP')][string]$Status,
        [int]$DurationMs = 0,
        [string]$Detail = '',
        $Data = $null
    )

    $script:Results.Add([pscustomobject]@{
        Name       = $Name
        Status     = $Status
        DurationMs = $DurationMs
        Detail     = $Detail
        Data       = $Data
    }) | Out-Null
}

function Invoke-SmokeStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Script
    )

    Write-SmokeLine ("START {0}" -f $Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $data = & $Script
        $sw.Stop()
        $detail = ConvertTo-SmokeDetail -Value $data
        Add-SmokeResult -Name $Name -Status OK -DurationMs ([int]$sw.ElapsedMilliseconds) -Detail $detail -Data $data
        Write-SmokeLine ("OK    {0} ({1:n1}s)" -f $Name, $sw.Elapsed.TotalSeconds)
    } catch {
        $sw.Stop()
        Add-SmokeResult -Name $Name -Status FAIL -DurationMs ([int]$sw.ElapsedMilliseconds) -Detail $_.Exception.Message
        Write-SmokeLine ("FAIL  {0} ({1:n1}s) {2}" -f $Name, $sw.Elapsed.TotalSeconds, $_.Exception.Message)
    }
}

function Skip-SmokeStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Reason
    )

    Add-SmokeResult -Name $Name -Status SKIP -DurationMs 0 -Detail $Reason
    Write-SmokeLine ("SKIP  {0} {1}" -f $Name, $Reason)
}

function Save-SmokeResult {
    $okCount = @($script:Results.ToArray() | Where-Object { $_.Status -eq 'OK' }).Count
    $failCount = @($script:Results.ToArray() | Where-Object { $_.Status -eq 'FAIL' }).Count
    $skipCount = @($script:Results.ToArray() | Where-Object { $_.Status -eq 'SKIP' }).Count

    [pscustomobject]@{
        Ok           = ($failCount -eq 0)
        StartedAt    = $script:StartedAt.ToString('o')
        FinishedAt   = (Get-Date).ToString('o')
        ProjectRoot  = $ProjectRoot
        Scope        = $Scope
        OutputDir    = $runDir
        ProgressPath = $progressPath
        ResultPath   = $resultPath
        Counts       = [pscustomobject]@{
            OK   = $okCount
            FAIL = $failCount
            SKIP = $skipCount
        }
        Parameters   = [pscustomobject]@{
            SourceWim           = $SourceWim
            ImageIndex          = $ImageIndex
            InstallImage        = $InstallImage
            IsoPath             = $IsoPath
            LocalUpdatePackage  = $LocalUpdatePackage
            AllowExistingMounts = [bool]$AllowExistingMounts
            SkipMountLifecycle  = [bool]$SkipMountLifecycle
            SkipFeatureMount    = [bool]$SkipFeatureMount
            SkipGuiStartup      = [bool]$SkipGuiStartup
            SkipLiveCatalog     = [bool]$SkipLiveCatalog
            KeepArtifacts       = [bool]$KeepArtifacts
        }
        Results      = @($script:Results.ToArray())
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

function Import-SmokeProjectModules {
    Import-Module (Join-Path $ProjectRoot 'Core\Bootstrap.psm1') -Global -Force -DisableNameChecking
    Set-ProjectRoot -Path $ProjectRoot | Out-Null

    $modules = @(
        'Core\Config.psm1',
        'Core\Logger.psm1',
        'Core\AppState.psm1',
        'Core\JobHistory.psm1',
        'Services\DismService.psm1',
        'Services\MountService.psm1',
        'Services\MountedWimService.psm1',
        'Services\WimInfoService.psm1',
        'Services\IsoService.psm1',
        'Services\IsoDetectService.psm1',
        'Services\ImageService.psm1',
        'Services\UpdateService.psm1',
        'Services\WindowsUpdateCatalogService.psm1',
        'Services\AdkService.psm1',
        'Services\IsoBuildService.psm1',
        'Services\ImageCompositionService.psm1',
        'Services\DismDriversParser.psm1',
        'UI\UiHelpers.psm1',
        'UI\UiAsync.psm1',
        'UI\Localization.psm1',
        'UI\Xaml.psm1',
        'UI\MainWindow.psm1'
    )

    foreach ($module in $modules) {
        Import-Module (Resolve-ProjectPath $module -MustExist) -Global -Force -DisableNameChecking
    }

    return $modules
}

function Invoke-SmokeMountLifecycle {
    $testScript = Join-Path $ProjectRoot 'Tests\Invoke-MountLifecycleTest.ps1'
    if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) {
        throw "Mount lifecycle test script not found: $testScript"
    }

    $mountOutputDir = Join-Path $runDir 'MountLifecycle'
    New-Item -ItemType Directory -Path $mountOutputDir -Force | Out-Null

    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe -PathType Leaf)) { $psExe = 'powershell.exe' }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $testScript,
        '-ProjectRoot', $ProjectRoot,
        '-SourceWim', $SourceWim,
        '-Index', ([string]$ImageIndex),
        '-OutputDir', $mountOutputDir
    )

    if ($AllowExistingMounts) { $args += '-AllowExistingMounts' }
    if ($KeepArtifacts) { $args += '-KeepArtifacts' }

    $output = & $psExe @args 2>&1
    $exitCode = $LASTEXITCODE
    $resultFile = Join-Path $mountOutputDir 'mount_lifecycle_result.json'
    $result = $null
    if (Test-Path -LiteralPath $resultFile -PathType Leaf) {
        try { $result = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }

    if ($exitCode -ne 0) {
        $message = "Mount lifecycle failed with exit code $exitCode."
        if ($result -and -not [string]::IsNullOrWhiteSpace([string]$result.Error)) {
            $message = [string]$result.Error
        }
        throw $message
    }

    return [pscustomobject]@{
        ExitCode   = $exitCode
        OutputDir  = $mountOutputDir
        ResultFile = $resultFile
        Summary    = $result
        Console    = @($output | Select-Object -Last 20)
    }
}

function Invoke-SmokeGuiStartup {
    if ($GuiStartupSeconds -lt 3) { $GuiStartupSeconds = 3 }

    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe -PathType Leaf)) { $psExe = 'powershell.exe' }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $psExe
    $pinfo.Arguments = ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" -StartPage Dashboard -SkipAdminCheck -SkipStaCheck' -f (Join-Path $ProjectRoot 'WinImageAdmin.ps1').Replace('"', '""'))
    $pinfo.WorkingDirectory = $ProjectRoot
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $pinfo

    $started = $false
    $alive = $false
    $title = ''
    $closeSent = $false
    $killed = $false
    $exitCode = $null

    try {
        $started = $proc.Start()
        Start-Sleep -Seconds $GuiStartupSeconds
        try { $proc.Refresh() } catch {}
        $alive = (-not $proc.HasExited)
        try { $title = [string]$proc.MainWindowTitle } catch {}

        if ($alive) {
            try { $closeSent = $proc.CloseMainWindow() } catch {}
            Start-Sleep -Seconds 4
            try { $proc.Refresh() } catch {}

            if (-not $proc.HasExited) {
                try {
                    $proc.Kill()
                    $killed = $true
                } catch {}
            }
        }

        try {
            if ($proc.HasExited) { $exitCode = $proc.ExitCode }
        } catch {}
    } finally {
        try { $proc.Dispose() } catch {}
    }

    if (-not $started) {
        throw 'GUI process did not start.'
    }
    if (-not $alive) {
        throw "GUI process exited before startup window was observed. ExitCode=$exitCode"
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
        throw 'GUI process started, but no main window title was observed.'
    }

    return [pscustomobject]@{
        Started         = $started
        AliveAfterWait  = $alive
        MainWindowTitle = $title
        CloseSent       = $closeSent
        Killed          = $killed
        ExitCode        = $exitCode
        Arguments       = $pinfo.Arguments
    }
}

function Invoke-SmokeIsoCycle {
    Import-Module (Resolve-ProjectPath 'Services\IsoService.psm1' -MustExist) -Force -DisableNameChecking
    Import-Module (Resolve-ProjectPath 'Services\IsoDetectService.psm1' -MustExist) -Force -DisableNameChecking

    if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
        throw "ISO not found: $IsoPath"
    }

    $before = @(Get-MountedIsoRoots)
    $mount = Mount-IsoFile -IsoPath $IsoPath
    Start-Sleep -Seconds 2
    $duringRoots = @(Get-MountedIsoRoots)
    $media = @(Find-MountedWindowsInstallMedia)

    try {
        Dismount-IsoFile -IsoPath $IsoPath | Out-Null
    } finally {
        Start-Sleep -Seconds 1
    }

    $after = @(Get-MountedIsoRoots)

    return [pscustomobject]@{
        Before      = $before
        Mount       = $mount
        DuringRoots = $duringRoots
        Media       = $media
        After       = $after
    }
}

function Invoke-SmokeIsoBuildFakeOscdimg {
    Import-Module (Resolve-ProjectPath 'Services\IsoBuildService.psm1' -MustExist) -Force -DisableNameChecking

    $fakeRoot = Join-Path $runDir 'IsoBuildFakeOscdimg'
    $sourceRoot = Join-Path $fakeRoot 'source'
    $workRoot = Join-Path $fakeRoot 'work'
    $outDir = Join-Path $fakeRoot 'out'
    $outputPath = Join-Path $outDir 'fake.iso'
    $fakeExe = Join-Path $fakeRoot 'fake-oscdimg.exe'
    $fakeFailExe = Join-Path $fakeRoot 'fake-oscdimg-fail.exe'

    New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'boot') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'sources') -Force | Out-Null
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $sourceRoot 'boot\etfsboot.com') -Value 'fake boot sector' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $sourceRoot 'sources\placeholder.txt') -Value 'fake Windows source' -Encoding ASCII

    $fakeSource = @'
using System;
using System.IO;

public class FakeOscdimg {
    public static int Main(string[] args) {
        for (int i = 0; i < 300; i++) {
            Console.Out.WriteLine("stdout line " + i);
            if ((i % 3) == 0) {
                Console.Error.WriteLine("stderr line " + i);
            }
        }

        if (args.Length > 0) {
            string output = args[args.Length - 1].Trim('"');
            string dir = Path.GetDirectoryName(output);
            if (!String.IsNullOrEmpty(dir)) {
                Directory.CreateDirectory(dir);
            }
            File.WriteAllText(output, "fake iso");
        }

        return 0;
    }
}
'@

    Add-Type -TypeDefinition $fakeSource -OutputType ConsoleApplication -OutputAssembly $fakeExe

    $result = Build-WindowsIso `
        -SourceRoot $sourceRoot `
        -OutputPath $outputPath `
        -OscdimgPath $fakeExe `
        -WorkingRoot $workRoot `
        -VolumeLabel 'SMOKE_FAKE'

    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Fake ISO was not created: $outputPath"
    }

    $fakeFailSource = @'
using System;

public class FakeOscdimgFail {
    public static int Main(string[] args) {
        Console.Out.WriteLine("fake stdout before failure");
        Console.Error.WriteLine("fake stderr before failure");
        return 7;
    }
}
'@

    Add-Type -TypeDefinition $fakeFailSource -OutputType ConsoleApplication -OutputAssembly $fakeFailExe

    $failureMessage = $null
    try {
        Build-WindowsIso `
            -SourceRoot $sourceRoot `
            -OutputPath (Join-Path $outDir 'fake-fail.iso') `
            -OscdimgPath $fakeFailExe `
            -WorkingRoot (Join-Path $fakeRoot 'work-fail') `
            -VolumeLabel 'SMOKE_FAIL' | Out-Null
    } catch {
        $failureMessage = $_.Exception.Message
    }

    if ([string]::IsNullOrWhiteSpace($failureMessage)) {
        throw 'Fake oscdimg failure path did not fail.'
    }

    foreach ($expected in @('ExitCode=7', 'fake stdout before failure', 'fake stderr before failure')) {
        if ($failureMessage -notmatch ([regex]::Escape($expected))) {
            throw "Fake oscdimg failure output did not include: $expected"
        }
    }

    return [pscustomobject]@{
        OutputPath          = $result.OutputPath
        StageRoot           = $result.StageRoot
        Command             = $result.OscdimgCommand
        SizeBytes           = (Get-Item -LiteralPath $outputPath).Length
        FailurePathVerified = $true
    }
}

function Invoke-SmokeImageCompositionPreflight {
    Import-Module (Resolve-ProjectPath 'Services\ImageCompositionService.psm1' -MustExist) -Force -DisableNameChecking

    $testRoot = Join-Path $runDir 'ImageCompositionPreflight'
    $outputPath = Join-Path $testRoot 'existing-install.wim'
    $missingSource = Join-Path $testRoot 'missing-source.wim'
    $sentinel = 'existing image should survive preflight failure'

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Set-Content -LiteralPath $outputPath -Value $sentinel -Encoding ASCII

    $failureMessage = $null
    try {
        Build-CombinedInstallImage `
            -ImageSpecs @([pscustomobject]@{
                Path  = $missingSource
                Index = 1
                Name  = 'Missing Source'
            }) `
            -OutputPath $outputPath `
            -Compression max | Out-Null
    } catch {
        $failureMessage = $_.Exception.Message
    }

    if ([string]::IsNullOrWhiteSpace($failureMessage)) {
        throw 'Image composition preflight did not fail for a missing source image.'
    }

    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Existing output was removed during preflight failure: $outputPath"
    }

    $actual = (Get-Content -LiteralPath $outputPath -Raw -Encoding ASCII).Trim()
    if ($actual -ne $sentinel) {
        throw "Existing output changed during preflight failure: $outputPath"
    }

    return [pscustomobject]@{
        OutputPath      = $outputPath
        MissingSource   = $missingSource
        FailureObserved = $true
        OutputPreserved = $true
        Message         = $failureMessage
    }
}

function Invoke-SmokeFeatureMount {
    Import-Module (Resolve-ProjectPath 'Services\DismService.psm1' -MustExist) -Force -DisableNameChecking
    Import-Module (Resolve-ProjectPath 'Services\MountService.psm1' -MustExist) -Force -DisableNameChecking
    Import-Module (Resolve-ProjectPath 'Services\MountedWimService.psm1' -MustExist) -Force -DisableNameChecking
    Import-Module (Resolve-ProjectPath 'Services\DismDriversParser.psm1' -MustExist) -Force -DisableNameChecking
    Import-Module (Resolve-ProjectPath 'Services\UpdateService.psm1' -MustExist) -Force -DisableNameChecking

    if (-not (Test-Path -LiteralPath $SourceWim -PathType Leaf)) {
        throw "Source WIM not found: $SourceWim"
    }

    $mount = Mount-WimImage -ImagePath $SourceWim -Index $ImageIndex -Mode Standalone -ReadOnly
    $script:MountedFeatureTestDir = [string]$mount.MountDir

    $mounted = @(Get-MountedWimList | Where-Object { [string]$_.MountDir -eq $script:MountedFeatureTestDir })

    $driverResult = Invoke-Dism -Arguments @(
        '/Get-Drivers',
        ('/Image:"{0}"' -f $script:MountedFeatureTestDir),
        '/All'
    ) -EnsureEnglish -TimeoutSec 600

    $drivers = @()
    if ($driverResult.ExitCode -eq 0) {
        $drivers = @(ConvertFrom-DismDriversOutput -Text $driverResult.StdOut)
    }

    if ($driverResult.ExitCode -ne 0) {
        $msg = $driverResult.StdErr
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $driverResult.StdOut }
        throw "DISM /Get-Drivers failed: $msg"
    }

    $updateContext = Get-MountedImageUpdateContext -MountDir $script:MountedFeatureTestDir
    $preflight = Test-CatalogUpdateIntegrationTargets `
        -MountDirs @($script:MountedFeatureTestDir) `
        -UpdateId 'LOCAL' `
        -Title 'Project smoke read-only preflight' `
        -KB 'KB0000000'

    return [pscustomobject]@{
        Mount        = $mount
        MountedList  = @($mounted | Select-Object MountDir, ImageFile, ImageIndex, ReadWrite, Health, CanCommit, CanIntegrateUpdates)
        DriverCount  = @($drivers).Count
        FirstDrivers = @($drivers | Select-Object -First 8)
        UpdateContext = [pscustomobject]@{
            ReadWrite              = $updateContext.ReadWrite
            PackageCount           = @($updateContext.Packages).Count
            InstalledKBCount       = $updateContext.InstalledKBCount
            IsWinPeLike            = $updateContext.IsWinPeLike
            CanIntegrateUpdates    = $updateContext.CanIntegrateUpdates
            UpdateServiceStatus    = $updateContext.UpdateServiceStatus
            CatalogSearchSupported = $updateContext.CatalogSearchSupported
        }
        IntegrationPreflight = [pscustomobject]@{
            MountCount   = $preflight.MountCount
            ReadyCount   = $preflight.ReadyCount
            SkippedCount = $preflight.SkippedCount
            Targets      = @($preflight.Targets | Select-Object MountDir, CanProcess, SkipReason, ReadWrite, CanIntegrateUpdates)
        }
    }
}

try {
    Write-SmokeLine 'Project smoke test started.'
    Write-SmokeLine ("ProjectRoot={0}" -f $ProjectRoot)
    Write-SmokeLine ("Scope={0}" -f $Scope)

    Invoke-SmokeStep 'PowerShell/admin context' {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        [pscustomobject]@{
            User      = $identity.Name
            IsAdmin   = Test-SmokeIsAdministrator
            PSVersion = $PSVersionTable.PSVersion.ToString()
            Apartment = [System.Threading.Thread]::CurrentThread.ApartmentState.ToString()
            Host      = $Host.Name
        }
    }

    Invoke-SmokeStep 'Git status' {
        $git = Get-Command git.exe -ErrorAction SilentlyContinue
        if (-not $git) { return 'git.exe not available' }
        $status = git -C $ProjectRoot status --short --branch
        [pscustomobject]@{ Status = @($status) }
    }

    Invoke-SmokeStep 'Import project modules' {
        $modules = Import-SmokeProjectModules
        [pscustomobject]@{ Count = @($modules).Count; Modules = $modules }
    }

    Invoke-SmokeStep 'Config, logger, app state, job history' {
        Initialize-Config -Overrides @{ StartPage = 'Dashboard'; AppDebug = $true } | Out-Null
        Initialize-Logger | Out-Null
        Initialize-AppState -Initial @{ StartPage = 'Dashboard'; SmokeTest = $runStamp } | Out-Null
        Set-AppStateValue -Key 'ProjectSmokeTest' -Value $runStamp | Out-Null
        Add-JobHistoryEntry -Operation 'ProjectSmokeTest' -Status 'Info' -Message 'Project smoke test touched job history.' -MaxEntries 250 | Out-Null

        [pscustomobject]@{
            StartPage = Get-ConfigValue -Key 'StartPage'
            AppDebug  = Get-ConfigValue -Key 'AppDebug'
            State     = Get-AppStateValue -Key 'ProjectSmokeTest'
            LogFile   = Get-LogFilePath
            History   = Get-JobHistorySummary
        }
    }

    Invoke-SmokeStep 'Load WPF XAML pages' {
        $xamlFiles = @(
            'UI\MainWindow.xaml',
            'UI\Pages\Dashboard.xaml',
            'UI\Pages\Images.xaml',
            'UI\Pages\MediaBuilder.xaml',
            'UI\Pages\Driver.xaml',
            'UI\Pages\Updates.xaml',
            'UI\Pages\Settings.xaml'
        )

        foreach ($xaml in $xamlFiles) {
            $obj = Import-XamlFile -RelativePath $xaml
            [pscustomobject]@{ Xaml = $xaml; Type = $obj.GetType().FullName }
        }
    }

    Invoke-SmokeStep 'DISM mounted image inventory command' {
        $res = Invoke-Dism -Arguments @('/English', '/Get-MountedWimInfo') -TimeoutSec 300
        [pscustomobject]@{
            ExitCode   = $res.ExitCode
            DurationMs = $res.DurationMs
            OutputTail = if ([string]::IsNullOrWhiteSpace([string]$res.StdOut)) { '' } else { ([string]$res.StdOut).Trim() }
        }
    }

    Invoke-SmokeStep 'Mounted WIM public inventory' {
        Import-Module (Resolve-ProjectPath 'Services\MountedWimService.psm1' -MustExist) -Force -DisableNameChecking
        @(Get-MountedWimList) | Select-Object MountDir, ImageFile, ImageIndex, ReadWrite, Health, RecommendedAction, RegistryOnly, CanCommit, CanIntegrateUpdates
    }

    if (Test-Path -LiteralPath $SourceWim -PathType Leaf) {
        Invoke-SmokeStep 'Read source WIM indexes' {
            @(Get-WimImageList -ImagePath $SourceWim)
        }
    } else {
        Skip-SmokeStep 'Read source WIM indexes' "Source WIM not found: $SourceWim"
    }

    if (Test-Path -LiteralPath $InstallImage -PathType Leaf) {
        Invoke-SmokeStep 'Read install image indexes' {
            @(Get-WimImageList -ImagePath $InstallImage) | Select-Object -First 20
        }
    } else {
        Skip-SmokeStep 'Read install image indexes' "Install image not found: $InstallImage"
    }

    Invoke-SmokeStep 'ADK status detection' {
        Get-AdkStatus
    }

    Invoke-SmokeStep 'ISO build fake oscdimg' {
        Invoke-SmokeIsoBuildFakeOscdimg
    }

    Invoke-SmokeStep 'Image composition preflight preserves output' {
        Invoke-SmokeImageCompositionPreflight
    }

    Invoke-SmokeStep 'Mounted ISO detection' {
        [pscustomobject]@{
            Roots = @(Get-MountedIsoRoots)
            Media = @(Find-MountedWindowsInstallMedia)
        }
    }

    if (Test-Path -LiteralPath $LocalUpdatePackage -PathType Leaf) {
        Invoke-SmokeStep 'Catalog LOCAL update download result' {
            Import-Module (Resolve-ProjectPath 'Services\WindowsUpdateCatalogService.psm1' -MustExist) -Force -DisableNameChecking
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($LocalUpdatePackage)).TrimEnd('=').Replace('+','-').Replace('/','_')
            $result = Download-CatalogUpdate -UpdateId ('LOCAL:' + $encoded) -Title 'Project smoke local package' -KB 'KB0000000'
            [pscustomobject]@{
                FileCount         = $result.FileCount
                SelectionStrategy = $result.SelectionStrategy
                LocalPath         = $result.Files[0].LocalPath
                Exists            = Test-Path -LiteralPath $result.Files[0].LocalPath -PathType Leaf
            }
        }
    } else {
        Skip-SmokeStep 'Catalog LOCAL update download result' "Local update package not found: $LocalUpdatePackage"
    }

    if ($Scope -eq 'Full' -and -not $SkipLiveCatalog) {
        Invoke-SmokeStep 'Catalog live search' {
            Import-Module (Resolve-ProjectPath 'Services\WindowsUpdateCatalogService.psm1' -MustExist) -Force -DisableNameChecking
            $query = if (Test-Path -LiteralPath $LocalUpdatePackage -PathType Leaf) {
                [System.IO.Path]::GetFileNameWithoutExtension($LocalUpdatePackage) + ' Windows 11 x64'
            } else {
                'Windows 11 cumulative update x64'
            }

            $found = Search-WindowsUpdateCatalog `
                -Queries @($query) `
                -InstalledKBs @() `
                -ProductFamily 'Windows 11' `
                -Architecture 'x64' `
                -BuildBranch '26100' `
                -CurrentBuildVersion '10.0.26100.1'

            @($found | Select-Object -First 8 Query, Title, KB, Products, Classification, Version, Size, IsInstalled)
        }
    } else {
        Skip-SmokeStep 'Catalog live search' 'Skipped by scope or -SkipLiveCatalog.'
    }

    if ($Scope -eq 'Full' -and (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
        Invoke-SmokeStep 'ISO mount/detect/dismount cycle' {
            Invoke-SmokeIsoCycle
        }
    } elseif ($Scope -ne 'Full') {
        Skip-SmokeStep 'ISO mount/detect/dismount cycle' 'Skipped because Scope=Basic.'
    } else {
        Skip-SmokeStep 'ISO mount/detect/dismount cycle' "ISO not found: $IsoPath"
    }

    if ($Scope -eq 'Full' -and -not $SkipFeatureMount) {
        if (-not (Test-SmokeIsAdministrator)) {
            Skip-SmokeStep 'Read-only feature mount checks' 'Administrator rights are required.'
        } elseif (-not (Test-Path -LiteralPath $SourceWim -PathType Leaf)) {
            Skip-SmokeStep 'Read-only feature mount checks' "Source WIM not found: $SourceWim"
        } else {
            Invoke-SmokeStep 'Read-only feature mount checks' {
                Invoke-SmokeFeatureMount
            }
        }
    } else {
        Skip-SmokeStep 'Read-only feature mount checks' 'Skipped by scope or -SkipFeatureMount.'
    }

    if (-not [string]::IsNullOrWhiteSpace($script:MountedFeatureTestDir)) {
        Invoke-SmokeStep 'Cleanup read-only feature mount' {
            $dir = $script:MountedFeatureTestDir
            Unmount-WimImage -MountDir $dir -Discard | Out-Null
            $script:MountedFeatureTestDir = $null
            [pscustomobject]@{ MountDir = $dir; Action = 'Discard' }
        }
    }

    if ($Scope -eq 'Full' -and -not $SkipMountLifecycle) {
        if (-not (Test-SmokeIsAdministrator)) {
            Skip-SmokeStep 'Mount lifecycle test' 'Administrator rights are required.'
        } elseif (-not (Test-Path -LiteralPath $SourceWim -PathType Leaf)) {
            Skip-SmokeStep 'Mount lifecycle test' "Source WIM not found: $SourceWim"
        } else {
            Invoke-SmokeStep 'Mount lifecycle test' {
                Invoke-SmokeMountLifecycle
            }
        }
    } else {
        Skip-SmokeStep 'Mount lifecycle test' 'Skipped by scope or -SkipMountLifecycle.'
    }

    if ($Scope -eq 'Full' -and -not $SkipGuiStartup) {
        Invoke-SmokeStep 'GUI startup and close' {
            Invoke-SmokeGuiStartup
        }
    } else {
        Skip-SmokeStep 'GUI startup and close' 'Skipped by scope or -SkipGuiStartup.'
    }
} finally {
    if (-not [string]::IsNullOrWhiteSpace($script:MountedFeatureTestDir)) {
        try {
            Write-SmokeLine ("CLEANUP feature mount discard {0}" -f $script:MountedFeatureTestDir)
            Unmount-WimImage -MountDir $script:MountedFeatureTestDir -Discard | Out-Null
            Add-SmokeResult -Name 'Cleanup feature mount discard' -Status OK -Detail $script:MountedFeatureTestDir
        } catch {
            Add-SmokeResult -Name 'Cleanup feature mount discard' -Status FAIL -Detail $_.Exception.Message
            Write-SmokeLine ("CLEANUP FAIL feature mount discard {0}" -f $_.Exception.Message)
        }
    }

    Save-SmokeResult
    Write-SmokeLine ("RESULT {0}" -f $resultPath)
}

$failed = @($script:Results.ToArray() | Where-Object { $_.Status -eq 'FAIL' })
if ($failed.Count -gt 0) {
    exit 1
}

exit 0
