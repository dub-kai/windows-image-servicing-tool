Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Update\UpdateService.Dism.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdateService.Parse.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdateService.Image.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdateService.Context.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdateService.Integration.ps1')

Export-ModuleMember -Function Get-MountedImageUpdateContext, Invoke-CatalogUpdateIntegration
