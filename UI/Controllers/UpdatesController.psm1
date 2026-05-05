Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Resolve-ProjectPath 'UI\UiHelpers.psm1' -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath 'UI\UiAsync.psm1'   -MustExist) -Force -DisableNameChecking -Global
Import-Module (Resolve-ProjectPath 'Services\UpdateService.psm1'               -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath 'Services\WindowsUpdateCatalogService.psm1' -MustExist) -Force -DisableNameChecking
Import-Module (Resolve-ProjectPath 'Services\MountedWimService.psm1'           -MustExist) -Force -DisableNameChecking

. (Join-Path $PSScriptRoot 'Update\UpdatesController.State.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdatesController.View.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdatesController.Catalog.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdatesController.Packages.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdatesController.Actions.ps1')
. (Join-Path $PSScriptRoot 'Update\UpdatesController.Init.ps1')

Export-ModuleMember -Function Initialize-UpdatesController, Refresh-UpdatesUI, Invoke-CatalogSearchUi
