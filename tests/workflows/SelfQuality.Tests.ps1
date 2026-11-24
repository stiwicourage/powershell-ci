BeforeAll {
    $script:root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ci = Get-Content (Join-Path $root '.github/workflows/ci.yml') -Raw
}

Describe 'powershell-ci checks itself with CodeScene' {
    It 'calls the shared tests workflow with CodeScene enabled and the access token' {
        $script:ci | Should -Match 'uses: \./\.github/workflows/tests\.yml'
        $script:ci | Should -Match 'codescene-enabled: true'
        $script:ci | Should -Match 'CS_ACCESS_TOKEN: \$\{\{ secrets\.CS_ACCESS_TOKEN \}\}'
    }

    It 'grants the shared workflow the read permissions it declares' {
        $script:ci | Should -Match '(?ms)quality:[^\n]*\n(?:[^\n]*\n)*?\s+permissions:\s+contents: read\s+actions: read'
    }

    It 'produces JaCoCo coverage for the actions and scripts through a script file' {
        $script:ci | Should -Match 'test-command: \./scripts/Invoke-PesterCoverage\.ps1'
        $script = Get-Content (Join-Path $root 'scripts/Invoke-PesterCoverage.ps1') -Raw
        $script | Should -Match 'JaCoCo'
        $script | Should -Match 'artifacts/coverage\.xml'
    }

    It 'keeps the tests from writing to the runner file commands of later steps' {
        $script = Get-Content (Join-Path $root 'scripts/Invoke-PesterCoverage.ps1') -Raw
        $script | Should -Match 'Remove-Item "Env:\$name"'
        foreach ($name in 'GITHUB_ENV', 'GITHUB_OUTPUT', 'GITHUB_PATH') {
            $script | Should -Match "'$name'"
        }
    }
}
