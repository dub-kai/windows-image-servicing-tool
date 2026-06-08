[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputDir,
    [int]$MaxIssues = 0
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
    $OutputDir = Join-Path $ProjectRoot 'Work\Temp\ThemeScan'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutputDir ("theme_scan_{0}" -f $stamp)
$resultPath = Join-Path $runDir 'theme_scan_result.json'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Import-ThemeScanModules {
    Import-Module (Join-Path $ProjectRoot 'Core\Bootstrap.psm1') -Global -Force -DisableNameChecking
    Set-ProjectRoot -Path $ProjectRoot | Out-Null

    foreach ($module in @(
        'UI\UiHelpers.psm1',
        'Core\Config.psm1',
        'UI\Localization.psm1',
        'UI\Theme.psm1',
        'UI\Xaml.psm1'
    )) {
        Import-Module (Resolve-ProjectPath $module -MustExist) -Global -Force -DisableNameChecking
    }
}

function Add-ThemeScanChild {
    param(
        [Parameter(Mandatory)][System.Collections.Queue]$Queue,
        [AllowNull()]$Child
    )

    if ($null -ne $Child -and ($Child -isnot [string])) {
        try { $Queue.Enqueue($Child) } catch {}
    }
}

function Add-ThemeScanChildren {
    param(
        [Parameter(Mandatory)][System.Collections.Queue]$Queue,
        [Parameter(Mandatory)]$Element
    )

    try { Add-ThemeScanChild -Queue $Queue -Child $Element.Content } catch {}
    try { Add-ThemeScanChild -Queue $Queue -Child $Element.Header } catch {}
    try { Add-ThemeScanChild -Queue $Queue -Child $Element.ToolTip } catch {}
    try { Add-ThemeScanChild -Queue $Queue -Child $Element.View } catch {}

    try {
        foreach ($item in @($Element.Items)) {
            Add-ThemeScanChild -Queue $Queue -Child $item
        }
    } catch {}

    try {
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Element)) {
            Add-ThemeScanChild -Queue $Queue -Child $child
        }
    } catch {}

    try {
        if ($Element -is [System.Windows.DependencyObject]) {
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
            for ($i = 0; $i -lt $count; $i++) {
                Add-ThemeScanChild -Queue $Queue -Child ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i))
            }
        }
    } catch {}
}

function Get-ThemeScanBrushInfo {
    param([AllowNull()]$Brush)

    if (-not ($Brush -is [System.Windows.Media.SolidColorBrush])) { return $null }

    $color = $Brush.Color
    if ([int]$color.A -le 8) { return $null }

    $r = [double]$color.R / 255.0
    $g = [double]$color.G / 255.0
    $b = [double]$color.B / 255.0
    $luminance = (0.2126 * $r) + (0.7152 * $g) + (0.0722 * $b)

    [pscustomobject]@{
        Hex       = ('#{0:X2}{1:X2}{2:X2}{3:X2}' -f [int]$color.A, [int]$color.R, [int]$color.G, [int]$color.B)
        Alpha     = [int]$color.A
        Luminance = [Math]::Round($luminance, 3)
    }
}

function Get-ThemeScanElementName {
    param([Parameter(Mandatory)]$Element)

    $typeName = 'Unknown'
    $name = ''
    try { $typeName = $Element.GetType().Name } catch {}
    try { $name = [string]$Element.Name } catch {}

    if ([string]::IsNullOrWhiteSpace($name)) { return $typeName }
    return ('{0}#{1}' -f $typeName, $name)
}

function Invoke-ThemeScanPage {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [double]$BackgroundLimit = 0.78,
        [double]$BorderLimit = 0.86
    )

    $page = Import-XamlFile -RelativePath $RelativePath
    Apply-UiTheme -Root $page -Theme Dark
    try { $page.UpdateLayout() } catch {}

    $issues = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Queue
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    Add-ThemeScanChild -Queue $queue -Child $page

    while ($queue.Count -gt 0) {
        $element = $queue.Dequeue()
        if ($null -eq $element) { continue }

        $hash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($element)
        if (-not $seen.Add($hash)) { continue }

        foreach ($propertyName in @('Background', 'RowBackground', 'AlternatingRowBackground', 'BorderBrush')) {
            $value = $null
            try {
                if ($element.PSObject.Properties.Match($propertyName).Count -gt 0) {
                    $value = $element.$propertyName
                }
            } catch {}

            $brushInfo = Get-ThemeScanBrushInfo -Brush $value
            if (-not $brushInfo) { continue }

            $limit = if ($propertyName -eq 'BorderBrush') { $BorderLimit } else { $BackgroundLimit }
            if ([double]$brushInfo.Luminance -gt $limit) {
                [void]$issues.Add([pscustomobject]@{
                    Page      = $RelativePath
                    Element   = Get-ThemeScanElementName -Element $element
                    Property  = $propertyName
                    Color     = [string]$brushInfo.Hex
                    Luminance = [double]$brushInfo.Luminance
                })
            }
        }

        Add-ThemeScanChildren -Queue $queue -Element $element
    }

    [pscustomobject]@{
        Page       = $RelativePath
        ElementCount = [int]$seen.Count
        IssueCount = [int]$issues.Count
        Issues     = @($issues.ToArray())
    }
}

Set-Location -LiteralPath $ProjectRoot
Import-ThemeScanModules

$pages = @(
    'UI\Pages\Dashboard.xaml',
    'UI\Pages\Images.xaml',
    'UI\Pages\MediaBuilder.xaml',
    'UI\Pages\Driver.xaml',
    'UI\Pages\Updates.xaml',
    'UI\Pages\Settings.xaml'
)

$pageResults = @()
foreach ($page in $pages) {
    $pageResults += Invoke-ThemeScanPage -RelativePath $page
}

$issues = @($pageResults | ForEach-Object { @($_.Issues) })
$ok = ($issues.Count -le $MaxIssues)
$result = [pscustomobject]@{
    Ok          = $ok
    ProjectRoot = $ProjectRoot
    OutputDir   = $runDir
    ResultPath  = $resultPath
    MaxIssues   = $MaxIssues
    IssueCount  = [int]$issues.Count
    Pages       = $pageResults
    Issues      = $issues
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("Theme scan result: {0} issue(s), result={1}" -f $issues.Count, $resultPath)

if (-not $ok) { exit 1 }
exit 0
