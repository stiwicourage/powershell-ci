BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scriptPath = Join-Path $root 'scripts/Move-ReleaseNotes.ps1'
    function Move-UnreleasedChangelog {
        param([string]$Path, [string]$Version)
        throw "Unmocked promotion of $Path to $Version."
    }
}

Describe 'Move-ReleaseNotes' {
    BeforeEach {
        $script:projectRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $projectRoot | Out-Null
        $script:notesPath = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).md"
        Mock Move-UnreleasedChangelog -ParameterFilter { $Path -like '*CHANGELOG.md' } {
            [pscustomobject]@{ ReleaseNotesBody = "### Added`n`n- Full detail."; TagMessageText = "Added`n`nFull detail." }
        }
        Mock Move-UnreleasedChangelog -ParameterFilter { $Path -like '*RELEASE_NOTE.md' } {
            [pscustomobject]@{ ReleaseNotesBody = "### Added`n`n- Consumer summary."; TagMessageText = 'unused' }
        }
    }

    It 'promotes both release files in the project root to the released version' {
        & $scriptPath -Version '1.2.3' -ReleaseNotesPath $notesPath -ProjectRoot $projectRoot | Out-Null

        $changelog = Join-Path $projectRoot 'CHANGELOG.md'
        $releaseNote = Join-Path $projectRoot 'RELEASE_NOTE.md'
        Should -Invoke Move-UnreleasedChangelog -Exactly -Times 1 -ParameterFilter { $Path -eq $changelog -and $Version -eq '1.2.3' }
        Should -Invoke Move-UnreleasedChangelog -Exactly -Times 1 -ParameterFilter { $Path -eq $releaseNote -and $Version -eq '1.2.3' }
    }

    It 'writes the promoted release-note section as the GitHub release body' {
        & $scriptPath -Version '1.2.3' -ReleaseNotesPath $notesPath -ProjectRoot $projectRoot | Out-Null

        (Get-Content -LiteralPath $notesPath -Raw).TrimEnd() | Should -BeExactly "### Added`n`n- Consumer summary."
    }

    It 'returns the changelog section as the annotated tag message' {
        $result = & $scriptPath -Version '1.2.3' -ReleaseNotesPath $notesPath -ProjectRoot $projectRoot

        $result.TagMessage | Should -BeExactly "Added`n`nFull detail."
        $result.ReleaseNotesPath | Should -BeExactly $notesPath
    }

    It 'stops the release when <File> has no unreleased entries' -ForEach @(
        @{ File = 'CHANGELOG.md' }
        @{ File = 'RELEASE_NOTE.md' }
    ) {
        Mock Move-UnreleasedChangelog -ParameterFilter { $Path -like "*$File" } { [pscustomobject]@{ ReleaseNotesBody = ''; TagMessageText = '' } }

        { & $scriptPath -Version '1.2.3' -ReleaseNotesPath $notesPath -ProjectRoot $projectRoot } |
            Should -Throw "*$File has no entries under ``[Unreleased``]*"
        Test-Path -LiteralPath $notesPath | Should -BeFalse
    }

    It 'rejects a version that is not a plain semantic version tag' {
        { & $scriptPath -Version 'v1.2.3' -ReleaseNotesPath $notesPath -ProjectRoot $projectRoot } | Should -Throw
        Should -Invoke Move-UnreleasedChangelog -Exactly -Times 0
    }
}
