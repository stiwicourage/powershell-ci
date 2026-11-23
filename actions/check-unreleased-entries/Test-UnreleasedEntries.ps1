[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Promotes a throwaway copy so the checked file is never modified.
function Test-HasUnreleasedEntries {
    param([string]$FilePath)

    $copy = Join-Path ([System.IO.Path]::GetTempPath()) "$([guid]::NewGuid().ToString('N'))-$([System.IO.Path]::GetFileName($FilePath))"
    try {
        Copy-Item -LiteralPath $FilePath -Destination $copy
        $result = Move-UnreleasedChangelog -Path $copy -Version '0.0.0'
        return -not [string]::IsNullOrWhiteSpace($result.ReleaseNotesBody)
    }
    finally {
        Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
    }
}

function Get-FilesWithoutUnreleasedEntries {
    param([string[]]$FilePath)

    foreach ($file in $FilePath) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "$file does not exist."
        }
        if (-not (Test-HasUnreleasedEntries -FilePath $file)) {
            [System.IO.Path]::GetFileName($file)
        }
    }
}

$missing = @(Get-FilesWithoutUnreleasedEntries -FilePath $Path)
if ($missing.Count -gt 0) {
    throw "$($missing -join ', ') has no entries under [Unreleased]. Add them before merging into the release branch, because the release promotes [Unreleased] and stops when it is empty."
}
