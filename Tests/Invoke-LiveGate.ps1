[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [switch]$RunCatalogLive,
    [switch]$RunMountLifecycle,
    [string]$SourceWim = 'D:\25H2\Iso\boot.wim',
    [int]$ImageIndex = 1,
    [string]$LocalUpdatePackage = 'D:\25H2\Updates\Windows11.0-KB5077241-x64.msu',
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
    if ([string]::IsNullOrWhiteSpace($scriptRoot)) { throw 'ProjectRoot could not be resolved automatically. Pass -ProjectRoot.' }
    $ProjectRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\LiveGate'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("live_gate_{0}" -f $stamp)
$resultPath = Join-Path $runDir 'live_gate_result.json'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Invoke-LiveGateStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $true
    $skipped = $false
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

    [pscustomobject]@{
        Name       = $Name
        Ok         = $ok
        Skipped    = $skipped
        DurationMs = [int]$sw.ElapsedMilliseconds
        Error      = $errorText
        Detail     = $detail
    }
}

$steps = New-Object System.Collections.Generic.List[object]
$startedAt = Get-Date

if (-not $RunCatalogLive -and -not $RunMountLifecycle) {
    throw 'No live gate selected. Pass -RunCatalogLive and/or -RunMountLifecycle explicitly.'
}

if ($RunCatalogLive) {
    $steps.Add((Invoke-LiveGateStep -Name 'Catalog live smoke' -Action {
        & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'Tests\Invoke-ProjectSmokeTest.ps1') `
            -ProjectRoot $ProjectRoot `
            -Scope Full `
            -SkipMountLifecycle `
            -SkipFeatureMount `
            -GuiStartupSeconds 0 `
            -SourceWim $SourceWim `
            -LocalUpdatePackage $LocalUpdatePackage `
            -OutputDir (Join-Path $runDir 'CatalogLive') | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Catalog live smoke failed with exit code $LASTEXITCODE." }
        [pscustomobject]@{ OutputDir = (Join-Path $runDir 'CatalogLive') }
    })) | Out-Null
}

if ($RunMountLifecycle) {
    $steps.Add((Invoke-LiveGateStep -Name 'Mount lifecycle' -Action {
        if (-not (Test-Path -LiteralPath $SourceWim -PathType Leaf)) {
            throw "Source WIM not found: $SourceWim"
        }

        & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'Tests\Invoke-MountLifecycleTest.ps1') `
            -ProjectRoot $ProjectRoot `
            -SourceWim $SourceWim `
            -ImageIndex $ImageIndex `
            -OutputDir (Join-Path $runDir 'MountLifecycle') | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Mount lifecycle failed with exit code $LASTEXITCODE." }
        [pscustomobject]@{ OutputDir = (Join-Path $runDir 'MountLifecycle') }
    })) | Out-Null
}

$allSteps = @($steps.ToArray())
$ok = (@($allSteps | Where-Object { -not $_.Ok }).Count -eq 0)
$result = [pscustomobject]@{
    Ok                = $ok
    StartedAt         = $startedAt.ToString('o')
    FinishedAt        = (Get-Date).ToString('o')
    ProjectRoot       = $ProjectRoot
    OutputDir         = $runDir
    ResultPath        = $resultPath
    RunCatalogLive    = [bool]$RunCatalogLive
    RunMountLifecycle = [bool]$RunMountLifecycle
    Steps             = $allSteps
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("RESULT {0}" -f $resultPath)
if (-not $ok) { exit 1 }
exit 0
