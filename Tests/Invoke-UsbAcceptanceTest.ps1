[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputDir
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
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\UsbAcceptance'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("usb_acceptance_{0}" -f $stamp)
$resultPath = Join-Path $runDir 'usb_acceptance_result.json'
$testRoot = Join-Path $runDir 'workspace'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

function New-UsbAcceptanceSource {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Partial
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Path 'sources') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Path 'sources\install.wim') -Value 'fake install image' -Encoding ASCII

    if (-not $Partial) {
        Set-Content -LiteralPath (Join-Path $Path 'bootmgr') -Value 'fake boot manager' -Encoding ASCII
        New-Item -ItemType Directory -Path (Join-Path $Path 'efi\boot') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'efi\boot\bootx64.efi') -Value 'fake efi boot' -Encoding ASCII
    }
}

function Add-UsbAcceptanceStep {
    param(
        [Parameter(Mandatory)]$List,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $true
    $errorText = ''
    $detail = $null
    try {
        $detail = & $Action
    } catch {
        $ok = $false
        $errorText = $_.Exception.Message
    } finally {
        $sw.Stop()
    }

    $List.Add([pscustomobject]@{
        Name       = $Name
        Ok         = $ok
        DurationMs = [int]$sw.ElapsedMilliseconds
        Error      = $errorText
        Detail     = $detail
    }) | Out-Null

    Write-Host ("{0}: {1}ms {2}" -f $Name, [int]$sw.ElapsedMilliseconds, $(if ($ok) { 'OK' } else { 'FAIL' }))

    if (-not $ok) {
        throw "USB acceptance failed: $Name - $errorText"
    }
}

Import-Module (Join-Path $ProjectRoot 'Core\Bootstrap.psm1') -Global -Force -DisableNameChecking
Set-ProjectRoot -Path $ProjectRoot | Out-Null
Import-Module (Resolve-ProjectPath 'Core\AppState.psm1' -MustExist) -Global -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath 'UI\Localization.psm1' -MustExist) -Global -Force -DisableNameChecking
$mediaModule = Import-Module (Resolve-ProjectPath 'UI\Controllers\MediaBuilderController.psm1' -MustExist) -Global -Force -DisableNameChecking -PassThru

$sourceRoot = Join-Path $testRoot 'bootable-source'
$partialRoot = Join-Path $testRoot 'partial-source'
$targetRoot = Join-Path $testRoot 'usb-target'
New-UsbAcceptanceSource -Path $sourceRoot
New-UsbAcceptanceSource -Path $partialRoot -Partial
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
Set-Content -LiteralPath (Join-Path $targetRoot 'existing-file.txt') -Value 'already here' -Encoding ASCII

$startedAt = Get-Date
$steps = New-Object System.Collections.Generic.List[object]
$ok = $true
$errorText = $null

try {
    Add-UsbAcceptanceStep -List $steps -Name 'Bootable source with existing target' -Action {
        $result = & $mediaModule {
            param([string]$SourcePath, [string]$TargetPath)
            Test-MediaUsbCopyPrerequisites -SourcePath $SourcePath -TargetPath $TargetPath
        } $sourceRoot $targetRoot
        if (-not $result) { throw 'No preflight result returned.' }
        if ([string]$result.BootReadiness -ne 'Ready') { throw "Expected Ready, got $($result.BootReadiness)." }
        if ([int]$result.TargetExistingItems -lt 1) { throw 'Existing target item was not counted.' }
        if (@($result.Warnings).Count -lt 1) { throw 'Expected at least one target warning.' }
        [pscustomobject]@{
            SourceText = [string]$result.SourceText
            FileCount = [int]$result.FileCount
            Warnings  = @($result.Warnings)
        }
    }

    Add-UsbAcceptanceStep -List $steps -Name 'Partial source warns about boot readiness' -Action {
        $result = & $mediaModule {
            param([string]$SourcePath, [string]$TargetPath)
            Test-MediaUsbCopyPrerequisites -SourcePath $SourcePath -TargetPath $TargetPath
        } $partialRoot $targetRoot
        if ([string]$result.BootReadiness -eq 'Ready') { throw 'Partial source was classified as Ready.' }
        if (@($result.Warnings | Where-Object { [string]$_ -match 'Boot|boot' }).Count -lt 1) {
            throw 'Missing boot warning was not returned.'
        }
        [pscustomobject]@{
            BootReadiness = [string]$result.BootReadiness
            Warnings      = @($result.Warnings)
        }
    }

    Add-UsbAcceptanceStep -List $steps -Name 'Reject target inside source' -Action {
        $nestedTarget = Join-Path $sourceRoot 'nested-target'
        New-Item -ItemType Directory -Path $nestedTarget -Force | Out-Null
        $blocked = $false
        try {
            & $mediaModule {
                param([string]$SourcePath, [string]$TargetPath)
                Test-MediaUsbCopyPrerequisites -SourcePath $SourcePath -TargetPath $TargetPath
            } $sourceRoot $nestedTarget | Out-Null
        } catch {
            $blocked = ([string]$_.Exception.Message -match 'innerhalb|inside')
        }
        if (-not $blocked) { throw 'Nested target was not rejected.' }
        [pscustomobject]@{ Blocked = $true }
    }

    Add-UsbAcceptanceStep -List $steps -Name 'Drive candidate inventory' -Action {
        $drives = @(& $mediaModule { Get-MediaUsbDriveCandidates })
        if ($drives.Count -lt 1) { throw 'No ready fixed/removable drive candidate found.' }
        [pscustomobject]@{
            Count = [int]$drives.Count
            First = [string]$drives[0].Display
        }
    }
} catch {
    $ok = $false
    $errorText = $_.Exception.Message
}

$allSteps = @($steps.ToArray())
$resultObject = [pscustomobject]@{
    Ok          = $ok
    Error       = $errorText
    StartedAt   = $startedAt.ToString('o')
    FinishedAt  = (Get-Date).ToString('o')
    ProjectRoot = $ProjectRoot
    OutputDir   = $runDir
    ResultPath  = $resultPath
    StepCount   = [int]$allSteps.Count
    FailedSteps = @($allSteps | Where-Object { -not $_.Ok } | Select-Object -ExpandProperty Name)
    Steps       = $allSteps
}

$resultObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("RESULT {0}" -f $resultPath)

if (-not $ok) { exit 1 }
exit 0
