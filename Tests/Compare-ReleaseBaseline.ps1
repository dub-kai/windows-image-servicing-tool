[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PreviousStatusPath = '',
    [string]$CurrentStatusPath = ''
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

if ([string]::IsNullOrWhiteSpace($CurrentStatusPath)) {
    $CurrentStatusPath = Join-Path $ProjectRoot 'Docs\ReleaseStatus.md'
}

function Get-BaselineMetricMap {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Baseline file not found: $Path" }
    $map = [ordered]@{}
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^- (?<name>[^:]+): (?<value>\d+) ms') {
            $map[[string]$Matches['name']] = [int]$Matches['value']
        }
        if ($line -match '^- (?<name>[^:]+): cold (?<cold>\d+) ms, warm avg (?<warm>\d+) ms, warm max (?<max>\d+) ms') {
            $name = [string]$Matches['name']
            $map["$name cold"] = [int]$Matches['cold']
            $map["$name warm avg"] = [int]$Matches['warm']
            $map["$name warm max"] = [int]$Matches['max']
        }
    }
    return $map
}

$current = Get-BaselineMetricMap -Path $CurrentStatusPath

if ([string]::IsNullOrWhiteSpace($PreviousStatusPath)) {
    Write-Host "Current baseline: $CurrentStatusPath"
    foreach ($key in $current.Keys) {
        Write-Host ("{0}: {1} ms" -f $key, $current[$key])
    }
    exit 0
}

$previous = Get-BaselineMetricMap -Path $PreviousStatusPath
Write-Host ("Comparing previous={0}" -f $PreviousStatusPath)
Write-Host ("       current ={0}" -f $CurrentStatusPath)

foreach ($key in $current.Keys) {
    if (-not $previous.Contains($key)) { continue }
    $old = [int]$previous[$key]
    $new = [int]$current[$key]
    $delta = $new - $old
    $pct = if ($old -gt 0) { [Math]::Round(($delta / [double]$old) * 100.0, 1) } else { 0 }
    Write-Host ("{0}: {1} -> {2} ms ({3:+0;-0;0} ms, {4:+0.0;-0.0;0.0}%)" -f $key, $old, $new, $delta, $pct)
}
