BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:scriptPath = Join-Path $root 'actions/create-github-release/Publish-GitHubRelease.ps1'
    $script:ghFake = @{ Arguments = $null; ExitCode = 0 }
    function gh {
        $ghFake.Arguments = $args
        $global:LASTEXITCODE = $ghFake.ExitCode
    }
}

Describe 'Publish-GitHubRelease' {
    BeforeEach {
        $ghFake.Arguments = $null
        $ghFake.ExitCode = 0
    }

    It 'uses the release-note file when it has content' {
        $notes = Join-Path $TestDrive 'notes.md'
        "### Added`n`n- Feature" | Set-Content -LiteralPath $notes
        & $scriptPath -TagName '1.2.3' -NotesFile $notes
        $ghFake.Arguments | Should -Be @('release', 'create', '1.2.3', '--title', '1.2.3', '--verify-tag', '--notes-file', $notes)
    }

    It 'uses the default message when <Case>' -ForEach @(
        @{ Case = 'no notes file is given'; File = '' }
        @{ Case = 'the notes file does not exist'; File = 'missing.md' }
        @{ Case = 'the notes file is blank'; File = 'blank.md'; Content = " `n" }
    ) {
        $notes = if ($File) { Join-Path $TestDrive $File } else { '' }
        if ($Content) { $Content | Set-Content -LiteralPath $notes }
        & $scriptPath -TagName '1.2.3' -NotesFile $notes
        $ghFake.Arguments | Should -Be @('release', 'create', '1.2.3', '--title', '1.2.3', '--verify-tag', '--notes', 'Version 1.2.3 has been released.')
    }

    It 'marks prerelease versions as GitHub prereleases' {
        & $scriptPath -TagName '1.2.3-preview' -NotesFile ''
        $ghFake.Arguments | Should -Contain '--prerelease'
    }

    It 'fails when gh cannot create the release' {
        $ghFake.ExitCode = 1
        { & $scriptPath -TagName '1.2.3' -NotesFile '' } | Should -Throw "*GitHub release '1.2.3'*"
    }
}
