BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:scriptPath = Join-Path $root 'actions/check-unreleased-entries/Test-UnreleasedEntries.ps1'
    function Move-UnreleasedChangelog {
        param([string]$Path, [string]$Version)
        throw "Unmocked promotion of $Path to $Version."
    }
}

Describe 'Test-UnreleasedEntries' {
    BeforeEach {
        $script:changelog = Join-Path $TestDrive 'CHANGELOG.md'
        $script:releaseNote = Join-Path $TestDrive 'RELEASE_NOTE.md'
        'original changelog' | Set-Content -LiteralPath $changelog
        'original release note' | Set-Content -LiteralPath $releaseNote
        Mock Move-UnreleasedChangelog { [pscustomobject]@{ ReleaseNotesBody = "### Added`n`n- Entry." } }
    }

    It 'passes when every file has entries under [Unreleased]' {
        { & $scriptPath -Path $changelog, $releaseNote } | Should -Not -Throw
        Should -Invoke Move-UnreleasedChangelog -Exactly -Times 2
    }

    It 'fails and names a file with no entries under [Unreleased]' {
        Mock Move-UnreleasedChangelog { [pscustomobject]@{ ReleaseNotesBody = '' } } -ParameterFilter { $Path -notlike "$TestDrive*" }

        { & $scriptPath -Path $changelog } | Should -Throw '*CHANGELOG.md has no entries under [[]Unreleased[]]*'
    }

    It 'reports every file without entries in one failure' {
        Mock Move-UnreleasedChangelog { [pscustomobject]@{ ReleaseNotesBody = '  ' } }

        { & $scriptPath -Path $changelog, $releaseNote } | Should -Throw '*CHANGELOG.md*RELEASE_NOTE.md*'
    }

    It 'fails when a file is missing' {
        { & $scriptPath -Path (Join-Path $TestDrive 'MISSING.md') } | Should -Throw '*MISSING.md*does not exist*'
    }

    It 'never modifies the checked files' {
        & $scriptPath -Path $changelog, $releaseNote

        (Get-Content -LiteralPath $changelog -Raw).TrimEnd() | Should -BeExactly 'original changelog'
        (Get-Content -LiteralPath $releaseNote -Raw).TrimEnd() | Should -BeExactly 'original release note'
    }
}
