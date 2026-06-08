Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MediaUsbSource {
    $selected = $script:ctx.SelectedUsbSourcePath
    if (-not [string]::IsNullOrWhiteSpace([string]$selected)) { return [string]$selected }
    return [string](Get-MediaIsoRoot)
}

function Format-MediaUsbTargetDisplay {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '-' }

    try {
        $drive = Get-MediaDriveInfo -Path $Path
        if ($drive -and $drive.IsReady) {
            $fileSystem = [string]$drive.DriveFormat
            if ([string]::IsNullOrWhiteSpace($fileSystem)) { $fileSystem = '-' }
            return (Get-UiString -Key 'MediaUsbTargetDisplayFormat' -Args @(
                [string]$Path,
                $fileSystem,
                (Format-MediaBytes ([int64]$drive.AvailableFreeSpace))
            ))
        }
    } catch {}

    return [string]$Path
}

function Get-MediaDirectorySizeInfo {
    param([Parameter(Mandatory)][string]$Path)

    $totalBytes = [int64]0
    $largestFile = $null
    $fileCount = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue)) {
        $fileCount++
        $length = [int64]$file.Length
        $totalBytes += $length
        if (-not $largestFile -or $length -gt [int64]$largestFile.Length) {
            $largestFile = $file
        }
    }

    return [pscustomobject]@{
        TotalBytes  = $totalBytes
        FileCount   = $fileCount
        LargestFile = $largestFile
    }
}

function Get-MediaUsbSourceSignals {
    param([AllowNull()][string]$SourcePath)

    $hasSources = $false
    $hasBootFiles = $false

    if (-not [string]::IsNullOrWhiteSpace([string]$SourcePath) -and (Test-Path -LiteralPath ([string]$SourcePath) -PathType Container)) {
        $sourceFull = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\')
        $bootFile = Join-Path $sourceFull 'bootmgr'
        $efiBoot = Join-Path $sourceFull 'efi\boot\bootx64.efi'
        $sourcesDir = Join-Path $sourceFull 'sources'
        $hasSources = Test-Path -LiteralPath $sourcesDir -PathType Container
        $hasBootFiles = (Test-Path -LiteralPath $bootFile -PathType Leaf) -or (Test-Path -LiteralPath $efiBoot -PathType Leaf)
    }

    return [pscustomobject]@{
        HasSources   = $hasSources
        HasBootFiles = $hasBootFiles
        BootReady    = ($hasSources -and $hasBootFiles)
    }
}

function Get-MediaUsbFileSystemHint {
    param([AllowNull()][string]$FileSystem)

    if ([string]::IsNullOrWhiteSpace([string]$FileSystem)) { return '' }

    switch -Regex ([string]$FileSystem) {
        '^FAT32$' { return (Get-UiString -Key 'MediaUsbFat32Hint') }
        '^NTFS$'  { return (Get-UiString -Key 'MediaUsbNtfsHint') }
        '^exFAT$' { return (Get-UiString -Key 'MediaUsbExfatHint') }
        default   { return '' }
    }
}

function Set-MediaUsbStatus {
    param(
        [AllowNull()][string]$Source,
        [AllowNull()][string]$Target,
        [AllowNull()]$Drive,
        [AllowNull()]$Signals
    )

    if (-not $script:ctx -or -not $script:ctx.TxtMediaUsbStatus) { return }

    $sourceState = Get-UiString -Key 'MediaUsbStatusOpen'
    if (-not [string]::IsNullOrWhiteSpace([string]$Source)) {
        if ($Signals -and $Signals.BootReady) {
            $sourceState = Get-UiString -Key 'MediaUsbStatusOk'
        } elseif ($Signals -and ($Signals.HasSources -or $Signals.HasBootFiles)) {
            $sourceState = Get-UiString -Key 'MediaUsbStatusWarn'
        } else {
            $sourceState = Get-UiString -Key 'MediaUsbStatusCheck'
        }
    }

    $targetState = Get-UiString -Key 'MediaUsbStatusOpen'
    if (-not [string]::IsNullOrWhiteSpace([string]$Target)) {
        if ((Test-Path -LiteralPath ([string]$Target) -PathType Container)) {
            $targetState = Get-UiString -Key 'MediaUsbStatusOk'
        } else {
            $targetState = Get-UiString -Key 'MediaUsbStatusWarn'
        }
    }

    $fileSystemState = Get-UiString -Key 'MediaUsbStatusOpen'
    $fileSystem = ''
    try { if ($Drive -and $Drive.IsReady) { $fileSystem = [string]$Drive.DriveFormat } } catch {}
    if (-not [string]::IsNullOrWhiteSpace($fileSystem)) {
        $fileSystemState = $fileSystem
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$Target)) {
        $fileSystemState = Get-UiString -Key 'MediaUsbStatusCheck'
    }

    $copyState = Get-UiString -Key 'MediaUsbStatusOpen'
    if (
        (-not [string]::IsNullOrWhiteSpace([string]$Source)) -and
        (-not [string]::IsNullOrWhiteSpace([string]$Target)) -and
        (Test-Path -LiteralPath ([string]$Source) -PathType Container) -and
        (Test-Path -LiteralPath ([string]$Target) -PathType Container)
    ) {
        $copyState = Get-UiString -Key 'MediaUsbStatusReady'
    } elseif ((-not [string]::IsNullOrWhiteSpace([string]$Source)) -or (-not [string]::IsNullOrWhiteSpace([string]$Target))) {
        $copyState = Get-UiString -Key 'MediaUsbStatusBlocked'
    }

    $script:ctx.TxtMediaUsbStatus.Text = Get-UiString -Key 'MediaUsbStatusLineFormat' -Args @(
        $sourceState,
        $targetState,
        $fileSystemState,
        $copyState
    )
}

function Refresh-MediaUsbUI {
    if (-not $script:ctx) { return }

    $source = Get-MediaUsbSource
    $target = $script:ctx.SelectedUsbTargetPath
    $targetDrive = $null
    $sourceSignals = $null

    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$target) -and (Test-Path -LiteralPath ([string]$target) -PathType Container)) {
            $targetDrive = Get-MediaDriveInfo -Path ([string]$target)
        }
    } catch {}

    try {
        $sourceSignals = Get-MediaUsbSourceSignals -SourcePath $source
    } catch {}

    try { if ($script:ctx.TxtMediaUsbSource) { $script:ctx.TxtMediaUsbSource.Text = (Get-DisplayOrDash $source) } } catch {}
    try { if ($script:ctx.TxtMediaUsbTarget) { $script:ctx.TxtMediaUsbTarget.Text = (Format-MediaUsbTargetDisplay -Path $target) } } catch {}
    try { Set-MediaUsbStatus -Source $source -Target $target -Drive $targetDrive -Signals $sourceSignals } catch {}

    try {
        if ($script:ctx.BtnMediaCopyToUsb) {
            $script:ctx.BtnMediaCopyToUsb.IsEnabled = (
                (-not $script:mediaBusy) -and
                (-not [string]::IsNullOrWhiteSpace([string]$source)) -and
                (-not [string]::IsNullOrWhiteSpace([string]$target))
            )
        }
        if ($script:ctx.BtnMediaCheckUsb) {
            $script:ctx.BtnMediaCheckUsb.IsEnabled = (
                (-not $script:mediaBusy) -and
                (-not [string]::IsNullOrWhiteSpace([string]$source)) -and
                (-not [string]::IsNullOrWhiteSpace([string]$target))
            )
        }
        if ($script:ctx.BtnMediaOpenUsbTarget) {
            $script:ctx.BtnMediaOpenUsbTarget.IsEnabled = (
                (-not $script:mediaBusy) -and
                (-not [string]::IsNullOrWhiteSpace([string]$target)) -and
                (Test-Path -LiteralPath ([string]$target) -PathType Container)
            )
        }
        if ($script:ctx.BtnMediaResetUsb) {
            $script:ctx.BtnMediaResetUsb.IsEnabled = (
                (-not $script:mediaBusy) -and
                (
                    (-not [string]::IsNullOrWhiteSpace([string]$script:ctx.SelectedUsbSourcePath)) -or
                    (-not [string]::IsNullOrWhiteSpace([string]$script:ctx.SelectedUsbTargetPath))
                )
            )
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaUsbSummary) {
            if ([string]::IsNullOrWhiteSpace([string]$source)) {
                $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbSourceMissing'
            } elseif ([string]::IsNullOrWhiteSpace([string]$target)) {
                $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbTargetMissing'
            } else {
                $drive = $targetDrive
                if ($drive -and $drive.IsReady) {
                    $fileSystem = [string]$drive.DriveFormat
                    if ([string]::IsNullOrWhiteSpace($fileSystem)) { $fileSystem = '-' }
                    $driveType = '-'
                    $existingItems = 0
                    try { $driveType = [string]$drive.DriveType } catch {}
                    try { $existingItems = @((Get-ChildItem -LiteralPath ([string]$target) -Force -ErrorAction SilentlyContinue)).Count } catch {}
                    $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbReadyWithTargetDetailsFormat' -Args @(
                        [string]$target,
                        (Format-MediaBytes ([int64]$drive.AvailableFreeSpace)),
                        $fileSystem,
                        $driveType,
                        [int]$existingItems
                    )
                } else {
                    $script:ctx.TxtMediaUsbSummary.Text = Get-UiString -Key 'MediaUsbReady'
                }
            }
        }
    } catch {}

    try {
        if ($script:ctx.TxtMediaUsbWarnings) {
            $warningText = ''
            if (-not [string]::IsNullOrWhiteSpace([string]$target) -and (Test-Path -LiteralPath ([string]$target) -PathType Container)) {
                $drive = $targetDrive
                $warnings = New-Object System.Collections.Generic.List[string]
                if ($drive -and $drive.IsReady) {
                    $driveType = '-'
                    $fileSystem = ''
                    try { $driveType = [string]$drive.DriveType } catch {}
                    try { $fileSystem = [string]$drive.DriveFormat } catch {}
                    try {
                        if ($drive.DriveType -ne [System.IO.DriveType]::Removable) {
                            [void]$warnings.Add((Get-UiString -Key 'MediaUsbNonRemovableWarning' -Args @($driveType)))
                        }
                    } catch {}

                    $fileSystemHint = Get-MediaUsbFileSystemHint -FileSystem $fileSystem
                    if (-not [string]::IsNullOrWhiteSpace($fileSystemHint)) {
                        [void]$warnings.Add($fileSystemHint)
                    }
                }

                $existingItems = 0
                try { $existingItems = @((Get-ChildItem -LiteralPath ([string]$target) -Force -ErrorAction SilentlyContinue)).Count } catch {}
                if ($existingItems -gt 0) {
                    [void]$warnings.Add((Get-UiString -Key 'MediaUsbExistingItemsWarningFormat' -Args @([int]$existingItems)))
                }

                $signals = $sourceSignals
                if ($signals -and $signals.BootReady) {
                    [void]$warnings.Add((Get-UiString -Key 'MediaUsbBootReadyHint'))
                } else {
                    if ((-not $signals) -or (-not $signals.HasSources)) { [void]$warnings.Add((Get-UiString -Key 'MediaUsbMissingSourcesWarning')) }
                    if ((-not $signals) -or (-not $signals.HasBootFiles)) { [void]$warnings.Add((Get-UiString -Key 'MediaUsbMissingBootWarning')) }
                }

                $warningText = (@($warnings.ToArray()) -join "`n")
            }

            $script:ctx.TxtMediaUsbWarnings.Text = $warningText
            $script:ctx.TxtMediaUsbWarnings.Visibility = if ([string]::IsNullOrWhiteSpace($warningText)) {
                [System.Windows.Visibility]::Collapsed
            } else {
                [System.Windows.Visibility]::Visible
            }
        }
    } catch {}
}

function Open-MediaUsbTarget {
    if ($script:mediaBusy -or -not $script:ctx) { return }

    try {
        $target = [string]$script:ctx.SelectedUsbTargetPath
        if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-Path -LiteralPath $target -PathType Container)) {
            throw (Get-UiString -Key 'MediaUsbTargetOpenMissing')
        }

        Start-Process -FilePath $target | Out-Null
        $message = Get-UiString -Key 'MediaUsbTargetOpenedFormat' -Args @($target)
        Add-MediaBuildLog $message
        if ($script:ctx.SetStatus) { & $script:ctx.SetStatus $message }
    } catch {
        Show-UiError -Message $_.Exception.Message
    }
}

function Reset-MediaUsbSelection {
    if ($script:mediaBusy -or -not $script:ctx) { return }

    $script:ctx.SelectedUsbSourcePath = $null
    $script:ctx.SelectedUsbTargetPath = $null
    Remove-MediaAppStateValueSafe -Key 'MediaUsbSourcePath'
    Remove-MediaAppStateValueSafe -Key 'MediaUsbTargetPath'
    Refresh-MediaBuilderUI

    $message = Get-UiString -Key 'MediaUsbResetStatus'
    Add-MediaBuildLog $message
    if ($script:ctx.SetStatus) { & $script:ctx.SetStatus $message }
}

function Test-MediaUsbCopyPrerequisites {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw (Get-UiString -Key 'MediaUsbSourceMissingPathFormat' -Args @($SourcePath))
    }
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        throw (Get-UiString -Key 'MediaUsbTargetMissingPathFormat' -Args @($TargetPath))
    }

    $sourceFull = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\')
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
    if ($sourceFull.Equals($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (Get-UiString -Key 'MediaUsbSamePath')
    }
    if ($targetFull.StartsWith($sourceFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (Get-UiString -Key 'MediaUsbTargetInsideSource')
    }

    $bootFile = Join-Path $sourceFull 'bootmgr'
    $efiBoot = Join-Path $sourceFull 'efi\boot\bootx64.efi'
    $sourcesDir = Join-Path $sourceFull 'sources'
    $hasSources = Test-Path -LiteralPath $sourcesDir -PathType Container
    $hasBootFiles = (Test-Path -LiteralPath $bootFile -PathType Leaf) -or (Test-Path -LiteralPath $efiBoot -PathType Leaf)
    $bootReadiness = if ($hasSources -and $hasBootFiles) { 'Ready' } elseif ($hasSources -or $hasBootFiles) { 'Partial' } else { 'Missing' }

    if (-not $hasSources) {
        $warning = Get-UiString -Key 'MediaUsbMissingSourcesWarning'
        Add-MediaBuildLog $warning
    }
    if (-not $hasBootFiles) {
        $warning = Get-UiString -Key 'MediaUsbMissingBootWarning'
        Add-MediaBuildLog $warning
    }

    $sizeInfo = Get-MediaDirectorySizeInfo -Path $sourceFull
    $drive = Get-MediaDriveInfo -Path $targetFull
    $fileSystem = ''
    $availableFreeSpace = [int64]0
    $targetDriveType = '-'
    $targetIsRemovable = $false
    $targetExistingItems = 0
    $warnings = New-Object System.Collections.Generic.List[string]

    try { $targetExistingItems = @((Get-ChildItem -LiteralPath $targetFull -Force -ErrorAction SilentlyContinue)).Count } catch { $targetExistingItems = 0 }
    if ($targetExistingItems -gt 0) {
        $warning = Get-UiString -Key 'MediaUsbExistingItemsWarningFormat' -Args @([int]$targetExistingItems)
        $warnings.Add($warning) | Out-Null
        Add-MediaBuildLog $warning
    }

    if ($drive -and $drive.IsReady) {
        try { $fileSystem = [string]$drive.DriveFormat } catch { $fileSystem = '' }
        try { $availableFreeSpace = [int64]$drive.AvailableFreeSpace } catch { $availableFreeSpace = 0 }
        try { $targetDriveType = [string]$drive.DriveType } catch { $targetDriveType = '-' }
        $targetIsRemovable = $drive.DriveType -eq [System.IO.DriveType]::Removable
        $fileSystemHint = Get-MediaUsbFileSystemHint -FileSystem $fileSystem
        if (-not [string]::IsNullOrWhiteSpace($fileSystemHint)) {
            $warnings.Add($fileSystemHint) | Out-Null
            Add-MediaBuildLog $fileSystemHint
        }

        if (-not $targetIsRemovable) {
            $warning = Get-UiString -Key 'MediaUsbNonRemovableWarning' -Args @($targetDriveType)
            $warnings.Add($warning) | Out-Null
            Add-MediaBuildLog $warning
        }

        if ([int64]$sizeInfo.TotalBytes -gt 0 -and $availableFreeSpace -lt [int64]$sizeInfo.TotalBytes) {
            throw (Get-UiString -Key 'MediaUsbInsufficientSpaceFormat' -Args @($drive.Name, (Format-MediaBytes $availableFreeSpace), (Format-MediaBytes $sizeInfo.TotalBytes)))
        }

        $largestFile = $sizeInfo.LargestFile
        if ($largestFile -and $fileSystem -eq 'FAT32' -and [int64]$largestFile.Length -ge 4GB) {
            throw (Get-UiString -Key 'MediaUsbFat32LargeFileFormat' -Args @([string]$largestFile.FullName, (Format-MediaBytes ([int64]$largestFile.Length))))
        }
    }

    if ($hasSources -and $hasBootFiles) {
        $bootHint = Get-UiString -Key 'MediaUsbBootReadyHint'
        Add-MediaBuildLog $bootHint
    } else {
        if (-not $hasSources) { $warnings.Add((Get-UiString -Key 'MediaUsbMissingSourcesWarning')) | Out-Null }
        if (-not $hasBootFiles) { $warnings.Add((Get-UiString -Key 'MediaUsbMissingBootWarning')) | Out-Null }
    }

    return [pscustomobject]@{
        Source             = $sourceFull
        Target             = $targetFull
        SourceBytes        = [int64]$sizeInfo.TotalBytes
        SourceText         = Format-MediaBytes ([int64]$sizeInfo.TotalBytes)
        FileCount          = [int]$sizeInfo.FileCount
        TargetFreeBytes    = $availableFreeSpace
        TargetFreeText     = $(if ($availableFreeSpace -gt 0) { Format-MediaBytes $availableFreeSpace } else { '-' })
        TargetDriveName    = $(if ($drive) { [string]$drive.Name } else { '-' })
        TargetFileSystem   = $(if ([string]::IsNullOrWhiteSpace($fileSystem)) { '-' } else { $fileSystem })
        TargetDriveType    = $targetDriveType
        TargetIsRemovable  = $targetIsRemovable
        TargetExistingItems = [int]$targetExistingItems
        Warnings           = @($warnings.ToArray())
        BootReadiness      = $bootReadiness
        HasSources         = $hasSources
        HasBootFiles       = $hasBootFiles
    }
}

function Start-MediaUsbCheck {
    if ($script:mediaBusy) { return }

    try {
        $check = Test-MediaUsbCopyPrerequisites -SourcePath (Get-MediaUsbSource) -TargetPath $script:ctx.SelectedUsbTargetPath
        $message = Get-UiString -Key 'MediaUsbCheckOkMessageDetailsFormat' -Args @(
            [string]$check.Source,
            [string]$check.Target,
            [string]$check.TargetFileSystem,
            [string]$check.TargetDriveType,
            [int]$check.TargetExistingItems,
            [string]$check.SourceText,
            [string]$check.TargetFreeText
        )
        if (@($check.Warnings).Count -gt 0) {
            $message = $message + "`r`n`r`n" + (@($check.Warnings) -join "`r`n")
        }
        Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCheckStatusFormat' -Args @([string]$check.SourceText, [string]$check.TargetFreeText, [string]$check.TargetDriveName))
        Set-MediaBuildStatus -Message (Get-UiString -Key 'MediaUsbCheckOkTitle') -Detail $message -SizeBytes ([int64]$check.SourceBytes) -SizeText ([string]$check.SourceText)
        if ($script:ctx.SetStatus) { & $script:ctx.SetStatus (Get-UiString -Key 'MediaUsbCheckStatusFormat' -Args @([string]$check.SourceText, [string]$check.TargetFreeText, [string]$check.TargetDriveName)) }
        Show-UiInfo -Title (Get-UiString -Key 'MediaUsbCheckOkTitle') -Message $message
        Refresh-MediaBuilderUI
    } catch {
        Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'MediaUsbCheckOkTitle')
    }
}

function Start-MediaUsbCopyAsync {
    if ($script:mediaBusy) { return }

    try {
        $source = Get-MediaUsbSource
        $target = $script:ctx.SelectedUsbTargetPath
        $check = Test-MediaUsbCopyPrerequisites -SourcePath $source -TargetPath $target

        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
        $answer = [System.Windows.MessageBox]::Show(
            (Get-UiString -Key 'MediaUsbCopyConfirmDetailsFormat' -Args @([string]$check.Source, [string]$check.Target, [string]$check.SourceText, [string]$check.TargetFreeText, [string]$check.TargetFileSystem, [string]$check.TargetDriveType, [int]$check.TargetExistingItems)),
            (Get-UiString -Key 'MediaUsbCopyTitle'),
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Information
        )
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Set-MediaBusy -Busy $true -Reason (Get-UiString -Key 'MediaUsbCopyBusy')
        Set-MediaBuildStatus -Message (Get-UiString -Key 'MediaUsbCopyBusy') -Detail (Get-UiString -Key 'MediaUsbCopyDetail') -SizeBytes ([int64]$check.SourceBytes) -SizeText (Get-UiString -Key 'MediaUsbCopySizeText')
        Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCopyStartLogFormat' -Args @([string]$check.Source, [string]$check.Target))

        $safeSource = ([string]$check.Source).Replace("'", "''")
        $safeTarget = ([string]$check.Target).Replace("'", "''")
        $code = @"
`$ErrorActionPreference = 'Stop'
`$source = '$safeSource'
`$target = '$safeTarget'
`$args = @(`$source, `$target, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/NP')
`$output = & robocopy.exe @args 2>&1 | Out-String
`$exitCode = `$LASTEXITCODE
if (`$exitCode -gt 7) {
    throw "__ROBOCOPY_FAILED__" -f `$exitCode, `$output
}
[pscustomobject]@{
    Source = `$source
    Target = `$target
    ExitCode = `$exitCode
    Output = `$output
}
"@
        $code = $code.Replace('__ROBOCOPY_FAILED__', (Get-UiString -Key 'MediaUsbRobocopyFailedFormat').Replace("'", "''"))

        Start-UiTask -Label 'MediaBuilder:UsbCopy' -Work ([scriptblock]::Create($code)) -OnCompleted {
            param($result)
            try {
                $item = @($result) | Select-Object -First 1
                Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCopyDoneLogFormat' -Args @([int]$item.ExitCode))
                $detail = Get-UiString -Key 'MediaUsbCopyDoneDetailFormat' -Args @([string]$item.Target, [int]$item.ExitCode)
                Set-MediaBuildStatus -Message (Get-UiString -Key 'MediaUsbCopyDone') -Detail $detail -SizeBytes 0 -SizeText (Get-UiString -Key 'MediaUsbCopyDone')
                if ($script:ctx.SetStatus) { & $script:ctx.SetStatus (Get-UiString -Key 'MediaUsbCopyDoneStatus') }
            } finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
            }
        } -OnError {
            param($ex)
            try {
                Add-MediaBuildLog (Get-UiString -Key 'MediaUsbCopyErrorLogFormat' -Args @($ex.Message))
                Show-UiError -Message $ex.Message -Title (Get-UiString -Key 'MediaUsbCopyTitle')
            } finally {
                Set-MediaBusy -Busy $false
                Refresh-MediaBuilderUI
                if ($script:ctx.SetStatus) { & $script:ctx.SetStatus 'Ready' }
            }
        }
    } catch {
        Show-UiError -Message $_.Exception.Message -Title (Get-UiString -Key 'MediaUsbCopyTitle')
    }
}

