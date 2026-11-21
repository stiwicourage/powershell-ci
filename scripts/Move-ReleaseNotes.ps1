[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [Parameter(Mandatory)]
    [string]$ReleaseNotesPath,

    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Move-ReleaseFileSection {
    param([string]$Root, [string]$FileName, [string]$ReleaseVersion)

    $result = Move-UnreleasedChangelog -Path (Join-Path $Root $FileName) -Version $ReleaseVersion
    if ([string]::IsNullOrWhiteSpace($result.ReleaseNotesBody)) {
        throw "$FileName has no entries under [Unreleased]. Add them before releasing $ReleaseVersion."
    }
    return $result
}

$changelog = Move-ReleaseFileSection -Root $ProjectRoot -FileName 'CHANGELOG.md' -ReleaseVersion $Version
$releaseNote = Move-ReleaseFileSection -Root $ProjectRoot -FileName 'RELEASE_NOTE.md' -ReleaseVersion $Version
Set-Content -LiteralPath $ReleaseNotesPath -Value $releaseNote.ReleaseNotesBody -Encoding utf8

[pscustomobject]@{
    TagMessage       = $changelog.TagMessageText
    ReleaseNotesPath = $ReleaseNotesPath
}
