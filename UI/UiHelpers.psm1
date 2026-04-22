Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DisplayValue {
    param($Value)
    if ($null -eq $Value) { return "-" }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return "-" }
    return $s
}

function New-BitmapImageFromFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath)) { return $null }

    try {
        $uri = New-Object System.Uri($FilePath, [System.UriKind]::Absolute)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.UriSource = $uri
        $bmp.EndInit()
        $bmp.Freeze()
        return $bmp
    } catch {
        return $null
    }
}

function Show-UiError {
    param([string]$Message,[string]$Title="Fehler")

    # -> WICHTIG: Fehler + Stack ins Log schreiben, damit wir die echte Zeile sehen
    try {
        $er = $null
        if ($global:Error.Count -gt 0) { $er = $global:Error[0] }

        $stack = $null
        $exmsg = $null
        if ($er) {
            try { $stack = $er.ScriptStackTrace } catch {}
            try { $exmsg = $er.Exception.Message } catch {}
        }

        $call = $null
        try {
            $call = (Get-PSCallStack | ForEach-Object { "$($_.Command) @ $($_.Location)" }) -join "`n"
        } catch {}

        Write-Log -Level ERROR -Message ("UI ERROR: {0}`nERRMSG: {1}`nSCRIPTSTACK:`n{2}`nCALLSTACK:`n{3}" -f $Message, $exmsg, $stack, $call) -ToConsole
    } catch {}

    try { [System.Windows.MessageBox]::Show($Message,$Title,"OK","Error") | Out-Null } catch {}
}

function Show-UiInfo {
    param([string]$Message,[string]$Title="Hinweis")
    try { [System.Windows.MessageBox]::Show($Message,$Title,"OK","Information") | Out-Null } catch {}
}

function Find-Ui {
    param(
        [Parameter(Mandatory)]$Root,
        [Parameter(Mandatory)][string]$Name
    )
    try { return $Root.FindName($Name) } catch { return $null }
}

function Set-UiText {
    param(
        [Parameter(Mandatory)]$Root,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()]$Value
    )

    $el = Find-Ui -Root $Root -Name $Name
    if (-not $el) {
        try { Write-Log -Level WARN -Message ("UI: FindName fehlgeschlagen: {0}" -f $Name) } catch {}
        return
    }

    $text = (Get-DisplayValue $Value)

    if ($el.PSObject.Properties.Match("Text").Count -gt 0) { $el.Text = $text; return }
    if ($el.PSObject.Properties.Match("Content").Count -gt 0) { $el.Content = $text; return }

    try {
        Write-Log -Level WARN -Message ("UI: Element '{0}' hat weder Text noch Content (Type={1})" -f $Name, $el.GetType().FullName)
    } catch {}
}

function Set-UiEnabled {
    param(
        [Parameter(Mandatory)]$Root,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Enabled
    )
    $el = Find-Ui -Root $Root -Name $Name
    if (-not $el) { return }
    if ($el.PSObject.Properties.Match("IsEnabled").Count -gt 0) { $el.IsEnabled = $Enabled }
}

# Global registrieren (Event/Timer/Async-Kontext)
Set-Item -Path function:global:Get-DisplayValue         -Value ${function:Get-DisplayValue}         -Force
Set-Item -Path function:global:New-BitmapImageFromFile  -Value ${function:New-BitmapImageFromFile}  -Force
Set-Item -Path function:global:Show-UiError             -Value ${function:Show-UiError}             -Force
Set-Item -Path function:global:Show-UiInfo              -Value ${function:Show-UiInfo}              -Force
Set-Item -Path function:global:Find-Ui                  -Value ${function:Find-Ui}                  -Force
Set-Item -Path function:global:Set-UiText               -Value ${function:Set-UiText}               -Force
Set-Item -Path function:global:Set-UiEnabled            -Value ${function:Set-UiEnabled}            -Force

Export-ModuleMember -Function `
    Get-DisplayValue, `
    New-BitmapImageFromFile, `
    Show-UiError, `
    Show-UiInfo, `
    Find-Ui, `
    Set-UiText, `
    Set-UiEnabled