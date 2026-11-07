[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')]
    [string]$Ref,

    [string]$Path = (Join-Path $PSScriptRoot '../.github/workflows')
)

Set-StrictMode -Version Latest

$pattern = '(stiwicourage/powershell-ci/[^\s@]+)@\S+'
$files = Get-ChildItem -LiteralPath $Path -Filter '*.yml' -File

foreach ($file in $files) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $updated = [regex]::Replace($content, $pattern, "`$1@$Ref")
    if ($updated -ne $content) {
        Set-Content -LiteralPath $file.FullName -Value $updated -NoNewline
        Write-Output "Pinned internal references in $($file.Name) to '$Ref'."
    }
}
