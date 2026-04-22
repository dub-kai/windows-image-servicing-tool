Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Catalog\Catalog.Debug.ps1')
. (Join-Path $PSScriptRoot 'Catalog\Catalog.Parse.ps1')
. (Join-Path $PSScriptRoot 'Catalog\Catalog.Match.ps1')
. (Join-Path $PSScriptRoot 'Catalog\Catalog.Search.ps1')
. (Join-Path $PSScriptRoot 'Catalog\Catalog.Download.ps1')

try {
    $existingRoot = Get-CatalogDebugRoot
    if (-not [string]::IsNullOrWhiteSpace($existingRoot)) {
        Invoke-CatalogDebugCleanup -Root $existingRoot -KeepNewest 12 -MaxAgeDays 2
    }
} catch {}

Export-ModuleMember -Function `
    Search-WindowsUpdateCatalog, `
    Search-WindowsUpdateCatalogBatch, `
    Get-RecommendedCatalogSubset, `
    Get-CatalogRecommendations, `
    Download-CatalogUpdate