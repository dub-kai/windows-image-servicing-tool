Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Thread-Safety über Monitor-Lock
$script:StateLock = New-Object object
$script:State = $null

function Initialize-AppState {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Initial
    )

    $new = @{}

    if ($Initial) {
        foreach ($k in $Initial.Keys) {
            $new[$k] = $Initial[$k]
        }
    }

    [System.Threading.Monitor]::Enter($script:StateLock)
    try {
        $script:State = $new
    } finally {
        [System.Threading.Monitor]::Exit($script:StateLock)
    }

    return $script:State
}

function Get-AppState {
    [CmdletBinding()]
    param()

    if (-not $script:State) {
        $null = Initialize-AppState
    }

    [System.Threading.Monitor]::Enter($script:StateLock)
    try {
        # Shallow copy zurückgeben, damit Consumer nicht direkt mutieren
        $copy = @{}
        foreach ($k in $script:State.Keys) { $copy[$k] = $script:State[$k] }
        return $copy
    } finally {
        [System.Threading.Monitor]::Exit($script:StateLock)
    }
}

function Get-AppStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        $Default = $null
    )

    if (-not $script:State) {
        $null = Initialize-AppState
    }

    [System.Threading.Monitor]::Enter($script:StateLock)
    try {
        if ($script:State.ContainsKey($Key)) {
            return $script:State[$Key]
        }
        return $Default
    } finally {
        [System.Threading.Monitor]::Exit($script:StateLock)
    }
}

function Set-AppStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        $Value
    )

    if (-not $script:State) {
        $null = Initialize-AppState
    }

    [System.Threading.Monitor]::Enter($script:StateLock)
    try {
        $script:State[$Key] = $Value
    } finally {
        [System.Threading.Monitor]::Exit($script:StateLock)
    }
}

function Remove-AppStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if (-not $script:State) {
        $null = Initialize-AppState
    }

    [System.Threading.Monitor]::Enter($script:StateLock)
    try {
        if ($script:State.ContainsKey($Key)) {
            $null = $script:State.Remove($Key)
        }
    } finally {
        [System.Threading.Monitor]::Exit($script:StateLock)
    }
}

function Clear-AppState {
    [CmdletBinding()]
    param()

    [System.Threading.Monitor]::Enter($script:StateLock)
    try {
        $script:State = @{}
    } finally {
        [System.Threading.Monitor]::Exit($script:StateLock)
    }
}

Export-ModuleMember -Function `
    Initialize-AppState, `
    Get-AppState, `
    Get-AppStateValue, `
    Set-AppStateValue, `
    Remove-AppStateValue, `
    Clear-AppState