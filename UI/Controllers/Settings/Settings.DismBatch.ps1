Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Refresh-SettingsDismBatchUI {
    if (-not $script:ctx) { return }

    Set-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismTimeoutSec -Key 'DismTimeoutSec' -Default 900 -Min 60 -Max 86400
    Set-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismLockTimeoutSec -Key 'DismLockTimeoutSec' -Default 1800 -Min 30 -Max 86400
    Set-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismUnmountCommitTimeoutSec -Key 'DismUnmountCommitTimeoutSec' -Default 7200 -Min 900 -Max 172800
    Set-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismUnmountCommitRetryCount -Key 'DismUnmountCommitRetryCount' -Default 3 -Min 1 -Max 20
    Set-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismUnmountCommitRetryDelaySec -Key 'DismUnmountCommitRetryDelaySec' -Default 12 -Min 1 -Max 600
    Set-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsMountedWimRefreshQuietPeriodSec -Key 'MountedWimRefreshQuietPeriodSec' -Default 15 -Min 0 -Max 600
    Set-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsBatchUnmountStepDelaySec -Key 'BatchUnmountStepDelaySec' -Default 4 -Min 0 -Max 600
}

function Save-SettingsDismBatchValues {
    $values = [ordered]@{
        DismTimeoutSec = Get-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismTimeoutSec -Label (Get-UiString -Key 'SettingsDismTimeoutLabel') -Min 60 -Max 86400
        DismLockTimeoutSec = Get-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismLockTimeoutSec -Label (Get-UiString -Key 'SettingsDismLockTimeoutLabel') -Min 30 -Max 86400
        DismUnmountCommitTimeoutSec = Get-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismUnmountCommitTimeoutSec -Label (Get-UiString -Key 'SettingsCommitTimeoutLabel') -Min 900 -Max 172800
        DismUnmountCommitRetryCount = Get-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismUnmountCommitRetryCount -Label (Get-UiString -Key 'SettingsCommitRetryCountLabel') -Min 1 -Max 20
        DismUnmountCommitRetryDelaySec = Get-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsDismUnmountCommitRetryDelaySec -Label (Get-UiString -Key 'SettingsCommitRetryDelayLabel') -Min 1 -Max 600
        MountedWimRefreshQuietPeriodSec = Get-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsMountedWimRefreshQuietPeriodSec -Label (Get-UiString -Key 'SettingsMountRefreshWaitLabel') -Min 0 -Max 600
        BatchUnmountStepDelaySec = Get-SettingsTextBoxInt -TextBox $script:ctx.TxtSettingsBatchUnmountStepDelaySec -Label (Get-UiString -Key 'SettingsBatchUnmountPauseLabel') -Min 0 -Max 600
    }

    foreach ($key in $values.Keys) {
        Set-SettingsConfigValue -Key $key -Value ([int]$values[$key]) -Persist | Out-Null
    }

    Refresh-SettingsDismBatchUI
    if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'SettingsDismBatchSaved') } catch {} }
}

function Reset-SettingsDismBatchValues {
    $defaults = New-DefaultConfig
    foreach ($key in @(
        'DismTimeoutSec',
        'DismLockTimeoutSec',
        'DismUnmountCommitTimeoutSec',
        'DismUnmountCommitRetryCount',
        'DismUnmountCommitRetryDelaySec',
        'MountedWimRefreshQuietPeriodSec',
        'BatchUnmountStepDelaySec'
    )) {
        Set-SettingsConfigValue -Key $key -Value ([int]$defaults[$key]) -Persist | Out-Null
    }

    Refresh-SettingsDismBatchUI
    if ($script:ctx.SetStatus) { try { & $script:ctx.SetStatus (Get-UiString -Key 'SettingsDismBatchDefaultsRestored') } catch {} }
}
