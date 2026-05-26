[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$SourceWim = 'D:\25H2\Iso\boot.wim',
    [int]$Index = 1,
    [string]$OutputDir,
    [switch]$SkipCommitCycle,
    [switch]$AllowExistingMounts,
    [switch]$KeepArtifacts
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
        throw 'ProjectRoot konnte nicht automatisch ermittelt werden. Bitte -ProjectRoot angeben.'
    }

    $ProjectRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\MountTests'
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$progressPath = Join-Path $OutputDir 'mount_lifecycle_progress.log'
$resultPath = Join-Path $OutputDir 'mount_lifecycle_result.json'
$commitWim = Join-Path $OutputDir ('commit_test_{0}.wim' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

Remove-Item -LiteralPath $progressPath, $resultPath -Force -ErrorAction SilentlyContinue

function Write-TestLine {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $progressPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

$steps = New-Object System.Collections.Generic.List[object]

function Add-StepResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][int]$DurationMs,
        [string]$Detail = ''
    )

    $steps.Add([pscustomobject]@{
        Name       = $Name
        Ok         = $Ok
        DurationMs = $DurationMs
        Detail     = $Detail
    }) | Out-Null
}

function Invoke-TestStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Script
    )

    Write-TestLine ("START {0}" -f $Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $detail = & $Script
        $sw.Stop()
        Add-StepResult -Name $Name -Ok $true -DurationMs ([int]$sw.ElapsedMilliseconds) -Detail ([string]$detail)
        Write-TestLine ("OK    {0} ({1:n1}s) {2}" -f $Name, $sw.Elapsed.TotalSeconds, [string]$detail)
    } catch {
        $sw.Stop()
        Add-StepResult -Name $Name -Ok $false -DurationMs ([int]$sw.ElapsedMilliseconds) -Detail $_.Exception.Message
        Write-TestLine ("FAIL  {0} ({1:n1}s) {2}" -f $Name, $sw.Elapsed.TotalSeconds, $_.Exception.Message)
        throw
    }
}

$script:readOnlyMountDir = $null
$script:commitMountDir = $null
$script:verifyMountDir = $null
$startedAt = (Get-Date).ToString('o')
$overallOk = $false
$errorText = $null

try {
    Write-TestLine 'Mount lifecycle test started.'

    Invoke-TestStep 'Check admin rights' {
        if (-not (Test-IsAdministrator)) {
            throw 'Administrator rights are required for DISM mount tests.'
        }

        'Admin OK'
    }

    Invoke-TestStep 'Import project modules' {
        Set-Location -LiteralPath $ProjectRoot
        Import-Module (Join-Path $ProjectRoot 'Core\Bootstrap.psm1') -Global -Force -DisableNameChecking
        Set-ProjectRoot -Path $ProjectRoot | Out-Null
        Import-Module (Join-Path $ProjectRoot 'Core\Config.psm1') -Global -Force -DisableNameChecking
        Import-Module (Join-Path $ProjectRoot 'Core\Logger.psm1') -Global -Force -DisableNameChecking
        Import-Module (Join-Path $ProjectRoot 'Services\DismService.psm1') -Global -Force -DisableNameChecking
        Import-Module (Join-Path $ProjectRoot 'Services\MountService.psm1') -Global -Force -DisableNameChecking
        Import-Module (Join-Path $ProjectRoot 'Services\MountedWimService.psm1') -Global -Force -DisableNameChecking
        'Modules OK'
    }

    Invoke-TestStep 'Check DISM process state' {
        $running = @(Get-Process dism, dismhost -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) {
            throw ('DISM is already running: {0}' -f (($running | Select-Object -ExpandProperty Id) -join ', '))
        }

        'No DISM process active'
    }

    Invoke-TestStep 'Mounted list before test' {
        $mounts = @(Get-MountedWimList)
        if (-not $AllowExistingMounts -and $mounts.Count -gt 0) {
            throw ('There are already {0} mount/registry entries. Clean them first or pass -AllowExistingMounts.' -f $mounts.Count)
        }

        ('{0} entries' -f $mounts.Count)
    }

    Invoke-TestStep 'Check source WIM' {
        if (-not (Test-Path -LiteralPath $SourceWim -PathType Leaf)) {
            throw "Source WIM not found: $SourceWim"
        }

        $item = Get-Item -LiteralPath $SourceWim
        ('{0:n1} MB | Attributes={1}' -f ($item.Length / 1MB), $item.Attributes)
    }

    Invoke-TestStep 'Read WIM info' {
        $res = Invoke-Dism -Arguments @('/English', '/Get-WimInfo', "/WimFile:$SourceWim") -TimeoutSec 300
        if ($res.ExitCode -ne 0) {
            throw (($res.StdErr + "`n" + $res.StdOut).Trim())
        }

        if (($res.StdOut + $res.StdErr) -notmatch ('Index\s*:\s*{0}\b' -f $Index)) {
            throw ("Index {0} not found in source WIM." -f $Index)
        }

        ("Index {0} found" -f $Index)
    }

    Invoke-TestStep 'Mount ReadOnly' {
        $mount = Mount-WimImage -ImagePath $SourceWim -Index $Index -Mode Standalone -ReadOnly
        $script:readOnlyMountDir = [string]$mount.MountDir
        if (-not (Test-Path -LiteralPath $script:readOnlyMountDir -PathType Container)) {
            throw 'MountDir was not created.'
        }

        $mounts = @(Get-MountedWimList)
        $hit = $mounts | Where-Object { [string]$_.MountDir -eq $script:readOnlyMountDir } | Select-Object -First 1
        if (-not $hit) {
            throw 'ReadOnly mount is not visible in mounted list.'
        }

        ('{0} | {1} | {2}' -f $script:readOnlyMountDir, $hit.Health, $hit.ReadWrite)
    }

    Invoke-TestStep 'Unmount ReadOnly with Discard' {
        Unmount-WimImage -MountDir $script:readOnlyMountDir -Discard | Out-Null
        $mounts = @(Get-MountedWimList)
        $hit = $mounts | Where-Object { [string]$_.MountDir -eq $script:readOnlyMountDir } | Select-Object -First 1
        if ($hit) {
            throw 'ReadOnly mount is still visible after Discard.'
        }

        'Discard OK'
    }

    if (-not $SkipCommitCycle) {
        Invoke-TestStep 'Copy temporary Commit WIM' {
            Copy-Item -LiteralPath $SourceWim -Destination $commitWim -Force
            if (-not (Test-Path -LiteralPath $commitWim -PathType Leaf)) {
                throw 'Temporary WIM copy was not created.'
            }

            (Get-Item -LiteralPath $commitWim).IsReadOnly = $false
            $item = Get-Item -LiteralPath $commitWim
            ('{0:n1} MB | Attributes={1}' -f ($item.Length / 1MB), $item.Attributes)
        }

        Invoke-TestStep 'Mount ReadWrite' {
            $mount = Mount-WimImage -ImagePath $commitWim -Index $Index -Mode Standalone
            $script:commitMountDir = [string]$mount.MountDir
            $mounts = @(Get-MountedWimList)
            $hit = $mounts | Where-Object { [string]$_.MountDir -eq $script:commitMountDir } | Select-Object -First 1
            if (-not $hit) {
                throw 'ReadWrite mount is not visible in mounted list.'
            }

            if ($hit.PSObject.Properties.Match('CanCommit').Count -gt 0 -and -not [bool]$hit.CanCommit) {
                throw 'ReadWrite mount was marked as not committable.'
            }

            ('{0} | {1} | {2}' -f $script:commitMountDir, $hit.Health, $hit.ReadWrite)
        }

        Invoke-TestStep 'Write marker into mount' {
            $marker = Join-Path $script:commitMountDir 'CodexMountCommitTest.txt'
            Set-Content -LiteralPath $marker -Value ('Codex mount commit test {0}' -f (Get-Date -Format o)) -Encoding UTF8
            if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
                throw 'Marker was not written.'
            }

            'Marker written'
        }

        Invoke-TestStep 'Unmount ReadWrite with Commit' {
            Unmount-WimImage -MountDir $script:commitMountDir -Commit | Out-Null
            $mounts = @(Get-MountedWimList)
            $hit = $mounts | Where-Object { [string]$_.MountDir -eq $script:commitMountDir } | Select-Object -First 1
            if ($hit) {
                throw 'Commit mount is still visible after Commit.'
            }

            'Commit OK'
        }

        Invoke-TestStep 'Verify commit by remount' {
            $mount = Mount-WimImage -ImagePath $commitWim -Index $Index -Mode Standalone -ReadOnly
            $script:verifyMountDir = [string]$mount.MountDir
            $marker = Join-Path $script:verifyMountDir 'CodexMountCommitTest.txt'
            if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
                throw 'Commit marker was not found after remount.'
            }

            'Marker found'
        }

        Invoke-TestStep 'Unmount verify mount with Discard' {
            Unmount-WimImage -MountDir $script:verifyMountDir -Discard | Out-Null
            $mounts = @(Get-MountedWimList)
            $hit = $mounts | Where-Object { [string]$_.MountDir -eq $script:verifyMountDir } | Select-Object -First 1
            if ($hit) {
                throw 'Verify mount is still visible after Discard.'
            }

            'Verify Discard OK'
        }
    }

    Invoke-TestStep 'Run Cleanup-Wim and final mount check' {
        Repair-WimMountRegistry -TimeoutSec 300 | Out-Null
        $mounts = @(Get-MountedWimList)
        if (-not $AllowExistingMounts -and $mounts.Count -gt 0) {
            throw ('There are still {0} entries after cleanup.' -f $mounts.Count)
        }

        ('{0} entries after cleanup' -f $mounts.Count)
    }

    if (-not $KeepArtifacts) {
        Invoke-TestStep 'Remove temporary WIM' {
            Remove-Item -LiteralPath $commitWim -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $commitWim) {
                throw 'Temporary WIM could not be removed.'
            }

            'Temporary WIM removed'
        }
    }

    $overallOk = $true
    Write-TestLine 'Mount lifecycle test completed successfully.'
} catch {
    $errorText = $_.Exception.Message
    Write-TestLine ("ABORT {0}" -f $errorText)
} finally {
    foreach ($dir in @($script:verifyMountDir, $script:commitMountDir, $script:readOnlyMountDir)) {
        if ([string]::IsNullOrWhiteSpace([string]$dir)) {
            continue
        }

        try {
            $mountsNow = @(Get-MountedWimList)
            $hit = $mountsNow | Where-Object { [string]$_.MountDir -eq [string]$dir } | Select-Object -First 1
            if ($hit) {
                Write-TestLine ("CLEANUP Unmount Discard {0}" -f $dir)
                Unmount-WimImage -MountDir ([string]$dir) -Discard | Out-Null
            }
        } catch {
            Write-TestLine ("CLEANUP WARN {0}: {1}" -f $dir, $_.Exception.Message)
        }
    }

    try {
        if (Get-Command Repair-WimMountRegistry -ErrorAction SilentlyContinue) {
            Repair-WimMountRegistry -TimeoutSec 300 | Out-Null
        }
    } catch {
        Write-TestLine ("CLEANUP-WIM WARN {0}" -f $_.Exception.Message)
    }

    if (-not $KeepArtifacts) {
        try {
            Remove-Item -LiteralPath $commitWim -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    $finalMounts = @()
    try {
        $finalMounts = @(Get-MountedWimList)
    } catch {}

    [pscustomobject]@{
        Ok                   = $overallOk
        Error                = $errorText
        StartedAt            = $startedAt
        FinishedAt           = (Get-Date).ToString('o')
        SourceWim            = $SourceWim
        Index                = $Index
        OutputDir            = $OutputDir
        ProgressPath         = $progressPath
        TempCommitWim        = $commitWim
        TempCommitWimRemoved = -not (Test-Path -LiteralPath $commitWim)
        FinalMountCount      = $finalMounts.Count
        FinalMounts          = @($finalMounts | Select-Object MountDir, Health, RecommendedAction, RegistryOnly)
        Steps                = @($steps.ToArray())
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    Write-TestLine ("RESULT {0}" -f $resultPath)

    if (-not $overallOk) {
        exit 1
    }
}
