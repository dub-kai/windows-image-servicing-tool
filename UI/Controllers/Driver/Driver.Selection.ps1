function Get-SelectedDriverItems {
    if (-not $script:ctx) { return @() }

    $lst = $script:ctx["LstDrivers"]
    if (-not $lst) { return @() }

    try {
        if ($lst.SelectedItems -and $lst.SelectedItems.Count -gt 0) {
            return @($lst.SelectedItems)
        }
    } catch {}

    try {
        if ($lst.SelectedItem) {
            return @($lst.SelectedItem)
        }
    } catch {}

    return @()
}

function Refresh-DriverUI {
    if (-not $script:ctx) { return }

    $mount = Resolve-DriverMountDir
    $allDrivers = $false
    try {
        $chkAll = $script:ctx["ChkDriverAll"]
        if ($chkAll) { $allDrivers = [bool]$chkAll.IsChecked }
    } catch { $allDrivers = $false }

    if ($script:ctx["TxtDriverMountUsed"]) {
        try {
            $modeText = if ($allDrivers) { "Vollständig inkl. Inbox" } else { "Schnellansicht ohne Inbox" }
            $script:ctx["TxtDriverMountUsed"].Text = ("Mount: {0} | Ansicht: {1}" -f (Get-DisplayValue $mount), $modeText)
        } catch {}
    }

    $selItems = @(Get-SelectedDriverItems)
    $selCount = $selItems.Count

    $removableCount = 0
    $firstName = $null

    foreach ($it in $selItems) {
        $pn = $null
        $inboxTxt = $null

        try {
            if ($it.PSObject.Properties.Match("PublishedName").Count -gt 0) {
                $pn = [string]$it.PublishedName
            }
        } catch {}

        try {
            if ($it.PSObject.Properties.Match("Inbox").Count -gt 0) {
                $inboxTxt = [string]$it.Inbox
            }
        } catch {}

        if (-not $firstName -and $pn) { $firstName = $pn }

        $isInbox = ConvertTo-InboxBool -InboxText $inboxTxt
        if ($pn -and ($isInbox -ne $true)) {
            $removableCount++
        }
    }

    $selText = "-"
    if ($selCount -eq 1) {
        $selText = if ($firstName) { $firstName } else { "-" }
    }
    elseif ($selCount -gt 1) {
        $selText = ("{0} ausgewählt (entfernbar: {1})" -f $selCount, $removableCount)
    }

    if ($script:ctx["TxtDriverSelected"]) {
        try {
            $script:ctx["TxtDriverSelected"].Text = ("Selected: {0}" -f $selText)
        } catch {}
    }

    $mountUsable = Test-DriverMountUsable -MountDir $mount
    $canWork = (-not $script:isBusy) -and $mountUsable -and (-not (Get-ImageServicingBusy))

    if ($script:ctx["BtnDriverLoadDrivers"]) {
        try {
            $script:ctx["BtnDriverLoadDrivers"].IsEnabled = $canWork
            $script:ctx["BtnDriverLoadDrivers"].Content = if ($allDrivers) { "Treiber laden (vollständig)" } else { "Treiber laden" }
        } catch {}
    }

    if ($script:ctx["BtnDriverAddDrivers"]) {
        try { $script:ctx["BtnDriverAddDrivers"].IsEnabled = $canWork } catch {}
    }

    $canRemove = $canWork -and ($removableCount -gt 0)
    if ($script:ctx["BtnDriverRemoveSelected"]) {
        try { $script:ctx["BtnDriverRemoveSelected"].IsEnabled = $canRemove } catch {}
    }

    $count = 0
    try {
        $lst = $script:ctx["LstDrivers"]
        if ($lst -and $lst.ItemsSource) {
            $count = @($lst.ItemsSource).Count
        }
    } catch {
        $count = 0
    }

    if ($script:ctx["TxtDriverCount"]) {
        try {
            $suffix = if ($allDrivers) { " | inkl. Inbox" } else { " | ohne Inbox" }
            $script:ctx["TxtDriverCount"].Text = ("Treiber: {0}{1}" -f $count, $suffix)
        } catch {}
    }
}
