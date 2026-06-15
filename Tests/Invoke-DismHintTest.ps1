[CmdletBinding()]
param(
    [string]$ProjectRoot = ''
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

Import-Module (Join-Path $ProjectRoot 'Core\Bootstrap.psm1') -Global -Force -DisableNameChecking
Set-ProjectRoot -Path $ProjectRoot | Out-Null
Import-Module (Resolve-ProjectPath 'Services\DismService.psm1' -MustExist) -Force -DisableNameChecking

$cases = @(
    @{ Code = 32; Text = 'The process cannot access the file because it is being used by another process.'; Must = 'Explorer' },
    @{ Code = 87; Text = 'Error: 87 The option is unknown.'; Must = 'Argumente' },
    @{ Code = 1; Text = '0xc142011d partially unmounted'; Must = 'Cleanup-Wim' },
    @{ Code = 5; Text = 'Access is denied'; Must = 'Administrator' },
    @{ Code = 740; Text = ''; Must = 'Administrator' },
    @{ Code = 112; Text = 'not enough space'; Must = 'Speicher' }
)

foreach ($case in $cases) {
    $hint = Get-DismUserHint -ExitCode ([int]$case.Code) -Text ([string]$case.Text)
    if ([string]::IsNullOrWhiteSpace($hint)) {
        throw "No hint returned for $($case.Code)."
    }
    if ($hint -notmatch [regex]::Escape([string]$case.Must)) {
        throw "Hint for $($case.Code) did not contain '$($case.Must)': $hint"
    }
    Write-Host ("DISM hint {0}: OK" -f $case.Code)
}

$message = Format-DismUserMessage -ExitCode 32 -Text 'Error: 32' -Operation 'DISM Unmount-Image'
if ($message -notmatch 'DISM Unmount-Image' -or $message -notmatch 'ExitCode=32') {
    throw 'Formatted DISM user message did not include operation and exit code.'
}

Write-Host 'RESULT OK'
