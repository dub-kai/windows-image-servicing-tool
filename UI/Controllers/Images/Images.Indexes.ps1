Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-WimCache {
    $v = Get-Variable -Name wimCache -Scope Script -ErrorAction SilentlyContinue
    if (-not $v -or $null -eq $v.Value) {
        Set-Variable -Name wimCache -Scope Script -Value (@{}) -Force
    }
    return (Get-Variable -Name wimCache -Scope Script).Value
}
$null = Ensure-WimCache

function Convert-WimInfoResultToItems {
    param(
        [Parameter(Mandatory)]
        $Result
    )

    if ($null -eq $Result) {
        return @()
    }

    # Fall 1: direkter Container mit .Items
    try {
        if ($Result.PSObject.Properties.Match('Items').Count -gt 0) {
            return @($Result.Items)
        }
    } catch {}

    # Fall 2: Array mit genau 1 Wrapper-Objekt, das .Items enthält
    try {
        $asArray = @($Result)
        if ($asArray.Count -eq 1) {
            $first = $asArray[0]
            if ($null -ne $first) {
                if ($first.PSObject.Properties.Match('Items').Count -gt 0) {
                    return @($first.Items)
                }
            }
        }
    } catch {}

    # Fall 3: Ergebnis ist schon direkt die Liste
    return @($Result)
}

function Get-SelectedWimIndex {
    if (-not $script:ctx -or -not $script:ctx.LstWimImages) { return $null }
    $sel = $null
    try { $sel = $script:ctx.LstWimImages.SelectedItem } catch { $sel = $null }
    if (-not $sel) { return $null }
    if ($sel.PSObject.Properties.Match("Index").Count -eq 0) { return $null }
    try { return [int]$sel.Index } catch { return $null }
}

function Update-SelectedIndexUi {
    if (-not $script:ctx) { return }

    $idx = Get-SelectedWimIndex
    try { Set-AppStateValue -Key "SelectedWimIndex" -Value $idx } catch {}

    if ($script:ctx.TxtSelectedIndex) {
        try { $script:ctx.TxtSelectedIndex.Text = if ($null -ne $idx) { [string]$idx } else { "-" } } catch {}
    }

    if (-not $script:isBusy -and $script:ctx.BtnMountSelected) {
        try { $script:ctx.BtnMountSelected.IsEnabled = ($null -ne $idx) } catch {}
    }

    if (-not $script:isBusy -and $script:ctx.BtnExportSelectedIndex) {
        try { $script:ctx.BtnExportSelectedIndex.IsEnabled = ($null -ne $idx) } catch {}
    }
}

function Clear-IndexListUi {
    if (-not $script:ctx) { return }

    if ($script:ctx.LstWimImages) {
        try {
            $script:ctx.LstWimImages.ItemsSource = $null
            $script:ctx.LstWimImages.Items.Refresh()
        } catch {}
    }

    if ($script:ctx.TxtWimSourceUsed) {
        try { $script:ctx.TxtWimSourceUsed.Text = "-" } catch {}
    }

    try { Set-AppStateValue -Key "SelectedWimIndex" -Value $null } catch {}
    Update-SelectedIndexUi
}

function Show-ImagesIndexes {
    param([switch]$ForceReload)

    if (-not $script:ctx) { return }
    if ($script:isBusy) { return }

    try {
        $mode = Get-ImagesViewMode
        if (-not $mode) {
            Clear-IndexListUi
            if ($script:ctx.SetStatus) { & $script:ctx.SetStatus "Keine Quelle gesetzt." }
            return
        }

        $path = $null
        try {
            $path = Get-ImagesPathForMode -Mode $mode
        } catch {
            Clear-IndexListUi
            if ($script:ctx.SetStatus) { & $script:ctx.SetStatus $_.Exception.Message }
            return
        }

        $cacheRef = Ensure-WimCache
        if (-not $ForceReload -and $cacheRef.ContainsKey($path) -and $null -ne $cacheRef[$path]) {
            $items = @($cacheRef[$path])

            if ($script:ctx.LstWimImages) {
                try {
                    $script:ctx.LstWimImages.ItemsSource = $null
                    $script:ctx.LstWimImages.ItemsSource = $items
                    $script:ctx.LstWimImages.Items.Refresh()
                } catch {}
            }

            if ($script:ctx.TxtWimSourceUsed) {
                try { $script:ctx.TxtWimSourceUsed.Text = $path } catch {}
            }

            Update-SelectedIndexUi
            return
        }

        $ctxLocal  = $script:ctx
        $setStatus = $script:ctx.SetStatus

        $fnSetBusy  = ${function:Set-ImagesBusy}
        $fnUpdSel   = ${function:Update-SelectedIndexUi}
        $fnClearIdx = ${function:Clear-IndexListUi}
        $fnConvert  = ${function:Convert-WimInfoResultToItems}

        & $fnSetBusy -Busy $true -Reason ("Indexe laden ({0})..." -f $mode) -Context $ctxLocal

        $dismMod    = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist)
        $wimInfoMod = (Resolve-ProjectPath "Services\WimInfoService.psm1" -MustExist)

        $safeDism   = $dismMod.Replace("'", "''")
        $safeWimInf = $wimInfoMod.Replace("'", "''")
        $safeImg    = $path.Replace("'", "''")

        $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$safeDism'   -Force
Import-Module '$safeWimInf' -Force
Get-WimImageList -ImagePath '$safeImg'
"@

        $onCompleted = {
            param($result)
            try {
                $items = @(& $fnConvert -Result $result)

                try {
                    Write-Log -Level INFO -Message ("Images: entpackte Index-Items={0} fuer {1}" -f $items.Count, $path)
                } catch {}

                $cacheRef[$path] = $items

                if ($ctxLocal.LstWimImages) {
                    try {
                        $ctxLocal.LstWimImages.ItemsSource = $null
                        $ctxLocal.LstWimImages.ItemsSource = $items
                        $ctxLocal.LstWimImages.Items.Refresh()
                    } catch {}
                }

                if ($ctxLocal.TxtWimSourceUsed) {
                    try { $ctxLocal.TxtWimSourceUsed.Text = $path } catch {}
                }

                & $fnUpdSel
            } finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
                if ($setStatus) { & $setStatus "Ready" }
            }
        }.GetNewClosure()

        $onError = {
            param($ex)
            try {
                Show-UiError -Message $ex.Message
                & $fnClearIdx
            } finally {
                & $fnSetBusy -Busy $false -Context $ctxLocal
                if ($setStatus) { & $setStatus "Ready" }
            }
        }.GetNewClosure()

        Start-UiTask -Work (New-WorkerScript -Code $code) -OnCompleted $onCompleted -OnError $onError -Label ("WimInfo:{0}" -f $mode)
    } catch {
        Set-ImagesBusy -Busy $false
        Show-UiError -Message $_.Exception.Message
    }
}