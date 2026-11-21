[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TagName,

    [AllowEmptyString()]
    [string]$NotesFile = ''
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

$arguments = @('release', 'create', $TagName, '--title', $TagName, '--verify-tag')
$arguments += Get-ReleaseNotesArgument -Tag $TagName -Path $NotesFile
if ($TagName -match '-') {
    $arguments += '--prerelease'
}

gh @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Could not create GitHub release '$TagName' (gh exit code $LASTEXITCODE)."
}
