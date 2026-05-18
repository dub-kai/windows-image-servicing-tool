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

function Get-SelectedWimItems {
    if (-not $script:ctx -or -not $script:ctx.LstWimImages) { return @() }

    $items = @()
    try {
        if ($script:ctx.LstWimImages.SelectedItems) {
            foreach ($item in $script:ctx.LstWimImages.SelectedItems) {
                if ($null -ne $item) { $items += $item }
            }
        }
    } catch {
        $items = @()
    }

    if ($items.Count -eq 0) {
        try {
            if ($script:ctx.LstWimImages.SelectedItem) {
                $items = @($script:ctx.LstWimImages.SelectedItem)
            }
        } catch {}
    }

    return @($items)
}

function Get-SelectedWimImagePath {
    if (-not $script:ctx -or -not $script:ctx.LstWimImages) { return $null }

    $sel = $null
    try { $sel = $script:ctx.LstWimImages.SelectedItem } catch { $sel = $null }
    if ($sel -and $sel.PSObject.Properties.Match("ImagePath").Count -gt 0) {
        $p = [string]$sel.ImagePath
        if (-not [string]::IsNullOrWhiteSpace($p)) {
            return (Normalize-PathText $p)
        }
    }

    try {
        $mode = Get-ImagesViewMode
        if ($mode) { return (Get-ImagesPathForMode -Mode $mode) }
    } catch {}

    return $null
}

function Get-WimSourceSummary {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [int]$ItemCount = 0
    )

    $items = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -eq 0) { return '-' }
    if ($items.Count -eq 1) { return [string]$items[0] }

    return ("{0} Dateien | {1} Indexe" -f $items.Count, $ItemCount)
}

function Set-WimSourceUsedText {
    param(
        $Context,
        [string]$Text
    )

    if (-not $Context) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { $Text = '-' }

    $target = $null
    try { $target = $Context.TxtWimSourceUsed } catch { $target = $null }
    if (-not $target) {
        try { $target = $Context['TxtWimSourceUsed'] } catch { $target = $null }
    }

    if ($target) {
        try {
            $target.Text = $Text
            return
        } catch {}
    }

    try {
        $root = $null
        try { $root = $Context.ImagesPage } catch { $root = $null }
        if (-not $root) { try { $root = $Context['ImagesPage'] } catch { $root = $null } }
        if ($root) { Set-UiText -Root $root -Name 'TxtWimSourceUsed' -Value $Text }
    } catch {}
}

function Update-SelectedIndexUi {
    if (-not $script:ctx) { return }

    $selectedItems = @(Get-SelectedWimItems)
    $idx = Get-SelectedWimIndex
    $imagePath = if ($null -ne $idx) { Get-SelectedWimImagePath } else { $null }
    try { Set-AppStateValue -Key "SelectedWimIndex" -Value $idx } catch {}
    try { Set-AppStateValue -Key "SelectedImagePath" -Value $imagePath } catch {}

    if ($script:ctx.TxtSelectedIndex) {
        try {
            $text = "-"
            if ($selectedItems.Count -gt 1) {
                $text = ("{0} Indexe ausgewählt" -f $selectedItems.Count)
            }
            elseif ($null -ne $idx) {
                $text = [string]$idx
                $sel = $null
                try { $sel = $script:ctx.LstWimImages.SelectedItem } catch {}
                if ($sel -and $sel.PSObject.Properties.Match("FileName").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$sel.FileName)) {
                    $text = ("{0} / Index {1}" -f $sel.FileName, $idx)
                }
            }
            $script:ctx.TxtSelectedIndex.Text = $text
        } catch {}
    }

    if (-not $script:isBusy -and $script:ctx.BtnMountSelected) {
        try { $script:ctx.BtnMountSelected.IsEnabled = ($selectedItems.Count -gt 0) } catch {}
    }

    if (-not $script:isBusy -and $script:ctx.BtnExportSelectedIndex) {
        try { $script:ctx.BtnExportSelectedIndex.IsEnabled = ($selectedItems.Count -eq 1 -and $null -ne $idx) } catch {}
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

    try { Set-WimSourceUsedText -Context $script:ctx -Text "-" } catch {}

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

        $paths = @()
        try {
            $paths = @(Get-ImagesPathsForMode -Mode $mode | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        } catch {
            Clear-IndexListUi
            if ($script:ctx.SetStatus) { & $script:ctx.SetStatus $_.Exception.Message }
            return
        }

        if ($paths.Count -eq 0) {
            Clear-IndexListUi
            if ($script:ctx.SetStatus) { & $script:ctx.SetStatus "Keine Quelle gesetzt." }
            return
        }

        $paths = @($paths | ForEach-Object { Normalize-PathText ([string]$_) })
        $cacheKey = ($paths | ForEach-Object { [string]$_ }) -join '|'

        $cacheRef = Ensure-WimCache
        if (-not $ForceReload -and $cacheRef.ContainsKey($cacheKey) -and $null -ne $cacheRef[$cacheKey]) {
            $items = @($cacheRef[$cacheKey])

            if ($script:ctx.LstWimImages) {
                try {
                    $script:ctx.LstWimImages.ItemsSource = $null
                    $script:ctx.LstWimImages.ItemsSource = $items
                    $script:ctx.LstWimImages.Items.Refresh()
                } catch {}
            }

            try { Set-WimSourceUsedText -Context $script:ctx -Text ([string](Get-WimSourceSummary -Paths $paths -ItemCount $items.Count)) } catch {}

            Update-SelectedIndexUi
            return
        }

        $ctxLocal  = $script:ctx
        $setStatus = $script:ctx.SetStatus

        $fnSetBusy  = ${function:Set-ImagesBusy}
        $fnUpdSel   = ${function:Update-SelectedIndexUi}
        $fnClearIdx = ${function:Clear-IndexListUi}
        $fnConvert  = ${function:Convert-WimInfoResultToItems}
        $fnSetSource = ${function:Set-WimSourceUsedText}
        $fnSummary = ${function:Get-WimSourceSummary}

        & $fnSetBusy -Busy $true -Reason ("Indexe laden ({0})..." -f $mode) -Context $ctxLocal

        $dismMod    = (Resolve-ProjectPath "Services\DismService.psm1" -MustExist)
        $wimInfoMod = (Resolve-ProjectPath "Services\WimInfoService.psm1" -MustExist)

        $safeDism   = $dismMod.Replace("'", "''")
        $safeWimInf = $wimInfoMod.Replace("'", "''")
        $pathLiterals = @($paths | ForEach-Object { "'" + ([string]$_).Replace("'", "''") + "'" }) -join ','

        $code = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$safeDism'   -Force
Import-Module '$safeWimInf' -Force
`$paths = @($pathLiterals)
`$result = New-Object System.Collections.Generic.List[object]
`$sourceOrder = 0
`$leafCounts = @{}

foreach (`$p in `$paths) {
    `$leaf = [System.IO.Path]::GetFileName(`$p)
    `$leafKey = `$leaf.ToLowerInvariant()
    if (-not `$leafCounts.ContainsKey(`$leafKey)) { `$leafCounts[`$leafKey] = 0 }
    `$leafCounts[`$leafKey] = [int]`$leafCounts[`$leafKey] + 1
}

foreach (`$imagePath in `$paths) {
    `$sourceOrder++
    try {
        `$rawWimItems = @(Get-WimImageList -ImagePath `$imagePath)
        if (`$rawWimItems.Count -eq 1 -and `$rawWimItems[0] -is [array]) {
            `$wimItems = @(`$rawWimItems[0])
        } else {
            `$wimItems = `$rawWimItems
        }
    } catch {
        throw ("Get-WimInfo failed for {0}: {1}" -f `$imagePath, `$_.Exception.Message)
    }

    foreach (`$item in `$wimItems) {
        if (`$null -eq `$item) { continue }
        if (`$item.PSObject.Properties.Match('Index').Count -eq 0) { continue }

        `$name = `$null
        `$description = `$null
        if (`$item.PSObject.Properties.Match('Name').Count -gt 0) { `$name = [string]`$item.Name }
        if (`$item.PSObject.Properties.Match('Description').Count -gt 0) { `$description = [string]`$item.Description }
        `$fileName = [System.IO.Path]::GetFileName(`$imagePath)
        `$leafKey = `$fileName.ToLowerInvariant()
        if (`$leafCounts.ContainsKey(`$leafKey) -and [int]`$leafCounts[`$leafKey] -gt 1) {
            `$parent = [System.IO.Path]::GetDirectoryName(`$imagePath)
            `$parentName = if (`$parent) { [System.IO.Path]::GetFileName(`$parent) } else { `$null }
            if (-not [string]::IsNullOrWhiteSpace(`$parentName)) {
                `$fileName = ("{0}\{1}" -f `$parentName, `$fileName)
            }
        }

        `$result.Add([pscustomobject]@{
            SourceOrder = `$sourceOrder
            ImagePath = `$imagePath
            FileName = `$fileName
            Index = [int]`$item.Index
            Name = `$name
            Description = `$description
        }) | Out-Null
    }
}

return ,(`$result.ToArray())
"@

        $onCompleted = {
            param($result)
            try {
                $items = @(& $fnConvert -Result $result)

                try {
                    Write-Log -Level INFO -Message ("Images: entpackte Index-Items={0} fuer {1}" -f $items.Count, (& $fnSummary -Paths $paths -ItemCount $items.Count))
                } catch {}

                $cacheRef[$cacheKey] = $items

                if ($ctxLocal.LstWimImages) {
                    try {
                        $ctxLocal.LstWimImages.ItemsSource = $null
                        $ctxLocal.LstWimImages.ItemsSource = $items
                        $ctxLocal.LstWimImages.Items.Refresh()
                    } catch {}
                }

                try { & $fnSetSource -Context $ctxLocal -Text ([string](& $fnSummary -Paths $paths -ItemCount $items.Count)) } catch {}

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
