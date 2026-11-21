BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:release = (Get-Content (Join-Path $root '.github/workflows/release.yml') -Raw) -replace '\r\n', "`n"
    $script:stepNames = @([regex]::Matches($release, '(?m)^      - name: (.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
    function Get-ReleaseStep {
        param([string]$Name)
        $pattern = '(?ms)^      - name: ' + [regex]::Escape($Name) + '\n.*?(?=^      - name: |\z)'
        return [regex]::Match($script:release, $pattern).Value
    }
}

Describe 'Release workflow changelog and release-note contract' {
    It 'installs KeepAChangelog next to SemanticRelease' {
        Get-ReleaseStep -Name 'Install release tooling' | Should -Match 'modules: SemanticRelease KeepAChangelog'
    }

    It 'promotes the unreleased sections after versioning and before the release commit' {
        $promote = [array]::IndexOf($stepNames, 'Promote unreleased changelog and release notes')
        $promote | Should -BeGreaterThan ([array]::IndexOf($stepNames, 'Determine next version from Conventional Commits'))
        $promote | Should -BeLessThan ([array]::IndexOf($stepNames, 'Create verified release commit'))

        $step = Get-ReleaseStep -Name 'Promote unreleased changelog and release notes'
        $step | Should -Match "steps.version.outputs.needs_release == 'true'"
        $step | Should -Match 'VERSION: \$\{\{ steps.version.outputs.version \}\}'
    }

    It 'publishes the promoted notes and tag message as step outputs' {
        $originalOutput = $env:GITHUB_OUTPUT
        $originalVersion = $env:VERSION
        $originalTemp = $env:RUNNER_TEMP
        Push-Location $TestDrive
        try {
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts') -Force | Out-Null
            "param(`$Version, `$ReleaseNotesPath) [pscustomobject]@{ TagMessage = `"Added``n``nTag for `$Version`"; ReleaseNotesPath = `$ReleaseNotesPath }" |
                Set-Content (Join-Path $TestDrive 'scripts/Move-ReleaseNotes.ps1')
            $env:GITHUB_OUTPUT = Join-Path $TestDrive 'output.txt'
            $env:VERSION = '1.2.3'
            $env:RUNNER_TEMP = $TestDrive

            $run = (Get-ReleaseStep -Name 'Promote unreleased changelog and release notes') -split '        run: \|\n', 2
            & ([scriptblock]::Create($run[1]))

            $output = Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw
            $output | Should -Match ('notes_path=' + [regex]::Escape((Join-Path $TestDrive 'release-notes.md')))
            $output | Should -Match '(?s)tag_message<<(?<d>[0-9a-f-]+)\r?\nAdded\r?\n\r?\nTag for 1\.2\.3\r?\n\k<d>'
        }
        finally {
            Pop-Location
            $env:GITHUB_OUTPUT = $originalOutput
            $env:VERSION = $originalVersion
            $env:RUNNER_TEMP = $originalTemp
        }
    }

    It 'uses the changelog section as the annotated tag message' {
        Get-ReleaseStep -Name 'Create annotated release tag' | Should -Match 'message: \$\{\{ steps.notes.outputs.tag_message \}\}'
    }

    It 'creates the GitHub release from the promoted release notes instead of generated notes' {
        $step = Get-ReleaseStep -Name 'Create GitHub release'
        $step | Should -Match "'--notes-file', \`$env:NOTES_PATH"
        $step | Should -Match 'NOTES_PATH: \$\{\{ steps.notes.outputs.notes_path \}\}'
        $step | Should -Not -Match 'generate-notes'
    }
}
