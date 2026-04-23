$script:ctx = $null
$script:isBusy = $false
$script:updateContext = $null
$script:catalogAllResults = @()
$script:catalogWorkResults = @()
$script:catalogVisibleResults = @()
$script:catalogRecommendations = $null
$script:lastCatalogSelectionKey = $null

$script:mountItems = @()
$script:selectedMountDir = $null
$script:suspendMountSelectionEvent = $false
$script:allPackages = @()
$script:visiblePackages = @()
$script:lastRefreshTriggerAtUtc = $null
$script:lastRefreshReason = $null

function New-UpdatesWorkerScript {
    param([Parameter(Mandatory)][string]$Code)
    return [scriptblock]::Create($Code)
}

function ConvertTo-UpdatesPsLiteral {
    param($Value)

    if ($null -eq $Value) { return '$null' }

    if ($Value -is [bool]) {
        if ($Value) { return '$true' }
        return '$false'
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [string]$Value
    }

    $text = [string]$Value
    return "'" + ($text -replace "'", "''") + "'"
}

function ConvertTo-UpdatesBase64Json {
    param($Value)

    if ($null -eq $Value) {
        $json = 'null'
    }
    else {
        $json = $Value | ConvertTo-Json -Compress -Depth 12
    }

    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$json))
}

function Get-UpdatesWorkerPreamble {
    $projectRoot = ConvertTo-UpdatesPsLiteral -Value (Get-ProjectRoot)

    return @"
`$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $projectRoot 'Core\\Bootstrap.psm1') -Force
`$null = Set-ProjectRoot -Path $projectRoot
Import-Module (Join-Path $projectRoot 'Core\\Config.psm1') -Force
`$null = Initialize-Config -Overrides @{ ProjectRoot = $projectRoot; AppDebug = `$true }
Import-Module (Join-Path $projectRoot 'Core\\Logger.psm1') -Force
`$null = Initialize-Logger
Import-Module (Join-Path $projectRoot 'Services\\DismService.psm1') -Force
Import-Module (Join-Path $projectRoot 'Services\\MountedWimService.psm1') -Force
Import-Module (Join-Path $projectRoot 'Services\\UpdateService.psm1') -Force
Import-Module (Join-Path $projectRoot 'Services\\WindowsUpdateCatalogService.psm1') -Force
"@
}

function Get-UpdatesSetStatus {
    if ($script:ctx -and ($script:ctx.SetStatus -is [scriptblock])) {
        return $script:ctx.SetStatus
    }

    return $null
}

function Set-UpdatesStatusText {
    param([string]$Message)

    if ($script:ctx -and $script:ctx.Page) {
        Set-UiText -Root $script:ctx.Page -Name 'TxtUpdatesStatus' -Value $Message
    }

    $setStatus = Get-UpdatesSetStatus
    if ($setStatus) {
        try { & $setStatus $Message } catch {}
    }
}

function Get-AutoCatalogEnabled {
    if (-not $script:ctx -or -not $script:ctx.Page) { return $true }

    $chk = Find-Ui -Root $script:ctx.Page -Name 'ChkUpdatesAutoCatalog'
    if (-not $chk) { return $true }

    return ($chk.IsChecked -ne $false)
}

function Get-SelectedMountDir {
    if ($script:ctx -and $script:ctx.Page) {
        $combo = Find-Ui -Root $script:ctx.Page -Name 'CmbUpdatesMounts'
        if ($combo -and $combo.SelectedItem) {
            try {
                $dir = [string]$combo.SelectedItem.MountDir
                if (-not [string]::IsNullOrWhiteSpace($dir)) {
                    return $dir
                }
            } catch {}
        }
    }

    return $script:selectedMountDir
}
