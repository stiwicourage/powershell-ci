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

Describe 'Release workflow example pinning' {
    It 'pins the examples to the release version before the release commit' {
        $step = Get-ReleaseStep -Name 'Pin examples to the release version'
        $step | Should -Match "if: \$\{\{ steps\.version\.outputs\.needs_release == 'true' \}\}"
        $step | Should -Match 'VERSION: \$\{\{ steps\.version\.outputs\.version \}\}'
        $step | Should -Match './scripts/Set-InternalActionRefs.ps1 -Ref \$env:VERSION -Path ./examples'
        $stepNames.IndexOf('Pin examples to the release version') | Should -BeGreaterThan $stepNames.IndexOf('Determine next version from Conventional Commits')
        $stepNames.IndexOf('Pin examples to the release version') | Should -BeLessThan $stepNames.IndexOf('Create verified release commit')
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
        $step | Should -Match 'uses: \./actions/create-github-release'
        $step | Should -Match 'notes-file: \$\{\{ steps.notes.outputs.notes_path \}\}'
        $step | Should -Not -Match 'generate-notes'
    }

    It 'attaches the signed archive and its Sigstore bundle to the GitHub release' {
        $step = Get-ReleaseStep -Name 'Create GitHub release'
        $step | Should -Match 'assets: \$\{\{ steps.package.outputs.archive \}\} \$\{\{ steps.sign.outputs.bundle \}\}'
    }
}

Describe 'Release workflow signing' {
    It 'packages and signs the release commit between the develop push and the GitHub release' {
        $push = [array]::IndexOf($stepNames, 'Push verified develop commit')
        $package = [array]::IndexOf($stepNames, 'Package release assets')
        $sign = [array]::IndexOf($stepNames, 'Sign release assets')
        $package | Should -BeGreaterThan $push
        $sign | Should -BeGreaterThan $package
        $sign | Should -BeLessThan ([array]::IndexOf($stepNames, 'Create GitHub release'))
    }

    It 'archives the release commit and signs it keyless with cosign' {
        $package = Get-ReleaseStep -Name 'Package release assets'
        $package | Should -Match 'id: package'
        $package | Should -Match 'git archive --format=zip'
        $package | Should -Match "steps.version.outputs.needs_release == 'true'"
        $sign = Get-ReleaseStep -Name 'Sign release assets'
        $sign | Should -Match 'id: sign'
        $sign | Should -Match 'cosign sign-blob --yes --bundle'
        $release | Should -Match 'sigstore/cosign-installer@[0-9a-f]{40}'
    }

    It 'lets only the release job request an OIDC token' {
        $release | Should -Match '(?m)^jobs:\n  release:\n    permissions:\n(?:      [^\n]+\n)*      id-token: write'
        $release | Should -Not -Match '(?m)^permissions:\n(?:  [^\n]+\n)*  id-token'
    }
}

Describe 'Release workflow ruleset bypass' {
    It 'creates a pinned GitHub App token only when RELEASE_APP_ID is configured' {
        $step = Get-ReleaseStep -Name 'Create release app token'
        $step | Should -Match 'id: app_token'
        $step | Should -Match "if: \$\{\{ vars\.RELEASE_APP_ID != '' \}\}"
        $step | Should -Match 'actions/create-github-app-token@[0-9a-f]{40} # v'
        $step | Should -Match 'app-id: \$\{\{ vars\.RELEASE_APP_ID \}\}'
        $step | Should -Match 'private-key: \$\{\{ secrets\.RELEASE_APP_PRIVATE_KEY \}\}'
        $stepNames.IndexOf('Create release app token') | Should -BeLessThan $stepNames.IndexOf('Push verified release commit')
    }

    It 'pushes both branch updates with the app token and falls back to GITHUB_TOKEN' {
        foreach ($name in 'Push verified release commit', 'Push verified develop commit') {
            Get-ReleaseStep -Name $name | Should -Match 'token: \$\{\{ steps\.app_token\.outputs\.token \|\| github\.token \}\}'
        }
    }
}
