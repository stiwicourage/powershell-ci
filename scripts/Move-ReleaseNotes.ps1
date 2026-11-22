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

# KeepAChangelog 0.3.0 and earlier write an extra blank line at the end of the promoted file.
function Repair-TrailingNewline {
    param([string]$Path)

    $text = [System.IO.File]::ReadAllText($Path).TrimEnd() + "`n"
    [System.IO.File]::WriteAllText($Path, $text)
}

function Move-ReleaseFileSection {
    param([string]$Root, [string]$FileName, [string]$ReleaseVersion)

    $path = Join-Path $Root $FileName
    $result = Move-UnreleasedChangelog -Path $path -Version $ReleaseVersion
    if ([string]::IsNullOrWhiteSpace($result.ReleaseNotesBody)) {
        throw "$FileName has no entries under [Unreleased]. Add them before releasing $ReleaseVersion."
    }
    Repair-TrailingNewline -Path $path
    return $result
}

$changelog = Move-ReleaseFileSection -Root $ProjectRoot -FileName 'CHANGELOG.md' -ReleaseVersion $Version
$releaseNote = Move-ReleaseFileSection -Root $ProjectRoot -FileName 'RELEASE_NOTE.md' -ReleaseVersion $Version
Set-Content -LiteralPath $ReleaseNotesPath -Value $releaseNote.ReleaseNotesBody -Encoding utf8

[pscustomobject]@{
    TagMessage       = $changelog.TagMessageText
    ReleaseNotesPath = $ReleaseNotesPath
}
