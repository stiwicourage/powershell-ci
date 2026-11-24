[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TagName,

    [AllowEmptyString()]
    [string]$NotesFile = '',

    [string[]]$AssetPath = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReleaseNotesArgument {
    param([string]$Tag, [string]$Path)

    $hasNotes = $Path -and (Test-Path -LiteralPath $Path -PathType Leaf) -and
        -not [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $Path -Raw))
    if ($hasNotes) {
        return @('--notes-file', $Path)
    }
    return @('--notes', "Version $Tag has been released.")
}

function Assert-AssetExists {
    param([string[]]$Path)

    foreach ($asset in $Path) {
        if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
            throw "Release asset '$asset' does not exist."
        }
    }
}

Assert-AssetExists -Path $AssetPath
$arguments = @('release', 'create', $TagName, '--title', $TagName, '--verify-tag')
$arguments += Get-ReleaseNotesArgument -Tag $TagName -Path $NotesFile
if ($TagName -match '-') {
    $arguments += '--prerelease'
}
$arguments += $AssetPath

gh @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Could not create GitHub release '$TagName' (gh exit code $LASTEXITCODE)."
}
