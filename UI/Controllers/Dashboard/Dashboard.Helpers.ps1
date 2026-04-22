function Invoke-StateChangedSafe {
    try {
        if ($script:ctx -and $script:ctx.OnStateChanged) { & $script:ctx.OnStateChanged }
    } catch {
        try {
            Write-Log -Level ERROR -Message ("OnStateChanged FAILED: {0}`nSTACK:`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) -ToConsole
        } catch {}
        Show-UiError -Message $_.Exception.Message
    }
}

function Invoke-SetStatusSafe {
    param([string]$Text)
    try {
        if ($script:ctx -and $script:ctx.SetStatus) { & $script:ctx.SetStatus $Text }
    } catch {}
}