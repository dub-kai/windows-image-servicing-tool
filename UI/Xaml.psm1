Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# WPF Assemblies laden (nur einmal)
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
} catch {
    # Falls bereits geladen -> egal
}

function Import-XamlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    # Wir erwarten, dass Bootstrap bereits geladen ist (Resolve-ProjectPath).
    $path = Resolve-ProjectPath $RelativePath -MustExist

    [xml]$xaml = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader $xaml

    try {
        return [System.Windows.Markup.XamlReader]::Load($reader)
    } catch {
        throw "XAML Laden fehlgeschlagen ($RelativePath): $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Import-XamlFile