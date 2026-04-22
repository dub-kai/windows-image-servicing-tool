function Get-CatalogDebugMode {
    <#
      Off  = keine Debug-Dateien
      Deep = HTML / Rows / Parsed / Batch-Dateien
    #>

    try {
        $envValue = [string]([Environment]::GetEnvironmentVariable('WINIMAGEADMIN_CATALOG_DEEPDEBUG'))
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            switch ($envValue.Trim().ToLowerInvariant()) {
                '1'     { return 'Deep' }
                'true'  { return 'Deep' }
                'yes'   { return 'Deep' }
                'on'    { return 'Deep' }
            }
        }
    } catch {}

    try {
        $cfg = Get-ConfigValue -Key 'CatalogDeepDebug' -Default $false
        if ($cfg -is [bool]) {
            if ($cfg) { return 'Deep' }
        } else {
            $cfgText = [string]$cfg
            if (-not [string]::IsNullOrWhiteSpace($cfgText)) {
                switch ($cfgText.Trim().ToLowerInvariant()) {
                    '1'     { return 'Deep' }
                    'true'  { return 'Deep' }
                    'yes'   { return 'Deep' }
                    'on'    { return 'Deep' }
                }
            }
        }
    } catch {}

    return 'Off'
}

function Test-CatalogDeepDebugEnabled {
    return ((Get-CatalogDebugMode) -eq 'Deep')
}

function Get-CatalogDebugRoot {
    try {
        $root = Resolve-ProjectPath "Work\Logs\Catalog"
        $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction SilentlyContinue
        return $root
    } catch {
        return $null
    }
}

function Invoke-CatalogDebugCleanup {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$KeepNewest = 12,
        [int]$MaxAgeDays = 2
    )

    try {
        if (-not (Test-Path -LiteralPath $Root)) { return }

        $files = @(Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($files.Count -eq 0) { return }

        if ($MaxAgeDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-1 * $MaxAgeDays)
            foreach ($file in $files) {
                try {
                    if ($file.LastWriteTime -lt $cutoff) {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
        }

        $files = @(Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($files.Count -le $KeepNewest) { return }

        foreach ($file in @($files | Select-Object -Skip $KeepNewest)) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    } catch {}
}

function Get-SafeCatalogDebugPrefix {
    param(
        [Parameter(Mandatory)][string]$Text,
        [int]$MaxLength = 80
    )

    $safe = ($Text -replace '[^a-zA-Z0-9]+', '_').ToLowerInvariant().Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'catalog'
    }

    if ($safe.Length -gt $MaxLength) {
        $safe = $safe.Substring(0, $MaxLength).TrimEnd('_')
    }

    return $safe
}

function Write-CatalogDebugFile {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Content
    )

    try {
        if (-not (Test-CatalogDeepDebugEnabled)) {
            return $null
        }

        $root = Get-CatalogDebugRoot
        if ([string]::IsNullOrWhiteSpace($root)) { return $null }

        Invoke-CatalogDebugCleanup -Root $root -KeepNewest 12 -MaxAgeDays 2

        $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
        $safePrefix = Get-SafeCatalogDebugPrefix -Text $Prefix
        $path = Join-Path $root ("{0}_{1}.txt" -f $safePrefix, $stamp)

        [System.IO.File]::WriteAllText($path, $Content, [System.Text.Encoding]::UTF8)

        try {
            Write-Log -Level INFO -Message ("Catalog: Debug-Datei geschrieben: {0}" -f $path)
        } catch {}

        return $path
    } catch {
        return $null
    }
}

function Write-CatalogDebugJson {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)]$Object
    )

    try {
        if (-not (Test-CatalogDeepDebugEnabled)) {
            return $null
        }

        $root = Get-CatalogDebugRoot
        if ([string]::IsNullOrWhiteSpace($root)) { return $null }

        Invoke-CatalogDebugCleanup -Root $root -KeepNewest 12 -MaxAgeDays 2

        $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
        $safePrefix = Get-SafeCatalogDebugPrefix -Text $Prefix
        $path = Join-Path $root ("{0}_{1}.json" -f $safePrefix, $stamp)

        $json = $Object | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)

        try {
            Write-Log -Level INFO -Message ("Catalog: Debug-Datei geschrieben: {0}" -f $path)
        } catch {}

        return $path
    } catch {
        return $null
    }
}