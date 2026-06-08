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
        [AllowNull()]$Child,
        [AllowNull()]$BackgroundInfo = $null
    )

    if ($null -ne $Child -and ($Child -isnot [string])) {
        try {
            $Queue.Enqueue([pscustomobject]@{
                Element    = $Child
                Background = $BackgroundInfo
            })
        } catch {}
    }
}

function Add-ThemeScanChildren {
    param(
        [Parameter(Mandatory)][System.Collections.Queue]$Queue,
        [Parameter(Mandatory)]$Element,
        [AllowNull()]$BackgroundInfo = $null
    )

    try { Add-ThemeScanChild -Queue $Queue -Child $Element.Content -BackgroundInfo $BackgroundInfo } catch {}
    try { Add-ThemeScanChild -Queue $Queue -Child $Element.Header -BackgroundInfo $BackgroundInfo } catch {}
    try { Add-ThemeScanChild -Queue $Queue -Child $Element.ToolTip -BackgroundInfo $BackgroundInfo } catch {}
    try { Add-ThemeScanChild -Queue $Queue -Child $Element.View -BackgroundInfo $BackgroundInfo } catch {}

    try {
        foreach ($item in @($Element.Items)) {
            Add-ThemeScanChild -Queue $Queue -Child $item -BackgroundInfo $BackgroundInfo
        }
    } catch {}

    try {
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Element)) {
            Add-ThemeScanChild -Queue $Queue -Child $child -BackgroundInfo $BackgroundInfo
        }
    } catch {}

    try {
        if ($Element -is [System.Windows.DependencyObject]) {
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
            for ($i = 0; $i -lt $count; $i++) {
                Add-ThemeScanChild -Queue $Queue -Child ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i)) -BackgroundInfo $BackgroundInfo
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

    $linear = {
        param([double]$Channel)
        if ($Channel -le 0.03928) { return ($Channel / 12.92) }
        return [Math]::Pow((($Channel + 0.055) / 1.055), 2.4)
    }

    $relativeLuminance = (0.2126 * (& $linear $r)) + (0.7152 * (& $linear $g)) + (0.0722 * (& $linear $b))

    [pscustomobject]@{
        Hex       = ('#{0:X2}{1:X2}{2:X2}{3:X2}' -f [int]$color.A, [int]$color.R, [int]$color.G, [int]$color.B)
        Alpha     = [int]$color.A
        Luminance = [Math]::Round($luminance, 3)
        RelativeLuminance = [Math]::Round($relativeLuminance, 4)
    }
}

function Get-ThemeScanContrastRatio {
    param(
        [Parameter(Mandatory)]$Foreground,
        [Parameter(Mandatory)]$Background
    )

    $lighter = [Math]::Max([double]$Foreground.RelativeLuminance, [double]$Background.RelativeLuminance)
    $darker = [Math]::Min([double]$Foreground.RelativeLuminance, [double]$Background.RelativeLuminance)
    return [Math]::Round((($lighter + 0.05) / ($darker + 0.05)), 2)
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
    Add-ThemeScanChild -Queue $queue -Child $page -BackgroundInfo $null

    while ($queue.Count -gt 0) {
        $entry = $queue.Dequeue()
        $element = $entry.Element
        $inheritedBackground = $entry.Background
        if ($null -eq $element) { continue }

        $hash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($element)
        if (-not $seen.Add($hash)) { continue }

        $effectiveBackground = $inheritedBackground

        foreach ($propertyName in @('Background', 'RowBackground', 'AlternatingRowBackground', 'BorderBrush')) {
            $value = $null
            try {
                if ($element.PSObject.Properties.Match($propertyName).Count -gt 0) {
                    $value = $element.$propertyName
                }
            } catch {}

            $brushInfo = Get-ThemeScanBrushInfo -Brush $value
            if (-not $brushInfo) { continue }

            if ($propertyName -in @('Background', 'RowBackground', 'AlternatingRowBackground')) {
                $effectiveBackground = $brushInfo
            }

            $limit = if ($propertyName -eq 'BorderBrush') { $BorderLimit } else { $BackgroundLimit }
            if ([double]$brushInfo.Luminance -gt $limit) {
                [void]$issues.Add([pscustomobject]@{
                    Type      = 'BrightSurface'
                    Page      = $RelativePath
                    Element   = Get-ThemeScanElementName -Element $element
                    Property  = $propertyName
                    Color     = [string]$brushInfo.Hex
                    Luminance = [double]$brushInfo.Luminance
                })
            }
        }

        try {
            if ($effectiveBackground) {
                $foreground = $null
                if ($element.PSObject.Properties.Match('Foreground').Count -gt 0) {
                    $foreground = Get-ThemeScanBrushInfo -Brush $element.Foreground
                }

                if ($foreground) {
                    $contrast = Get-ThemeScanContrastRatio -Foreground $foreground -Background $effectiveBackground
                    if ($contrast -lt 3.0) {
                        [void]$issues.Add([pscustomobject]@{
                            Type       = 'LowContrastText'
                            Page       = $RelativePath
                            Element    = Get-ThemeScanElementName -Element $element
                            Property   = 'Foreground'
                            Color      = [string]$foreground.Hex
                            Background = [string]$effectiveBackground.Hex
                            Contrast   = [double]$contrast
                        })
                    }
                }
            }
        } catch {}

        Add-ThemeScanChildren -Queue $queue -Element $element -BackgroundInfo $effectiveBackground
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
$issueSummary = @($issues | Group-Object Type, Page | ForEach-Object {
    $typeName = ''
    $pageName = ''
    try {
        $parts = [string]$_.Name -split ', ', 2
        $typeName = [string]$parts[0]
        if ($parts.Count -gt 1) { $pageName = [string]$parts[1] }
    } catch {}

    [pscustomobject]@{
        Type  = $typeName
        Page  = $pageName
        Count = [int]$_.Count
    }
})
$result = [pscustomobject]@{
    Ok          = $ok
    ProjectRoot = $ProjectRoot
    OutputDir   = $runDir
    ResultPath  = $resultPath
    MaxIssues   = $MaxIssues
    IssueCount  = [int]$issues.Count
    IssueSummary = $issueSummary
    Pages       = $pageResults
    Issues      = $issues
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("Theme scan result: {0} issue(s), result={1}" -f $issues.Count, $resultPath)
if ($issues.Count -gt 0) {
    foreach ($summary in $issueSummary) {
        Write-Host ("  {0} {1}: {2}" -f $summary.Type, $summary.Page, $summary.Count)
    }
}

if (-not $ok) { exit 1 }
exit 0
