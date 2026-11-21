BeforeAll {
    $script:root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe 'Shared opt-in workflow contracts' {
    It 'exposes backward-compatible isolation in <Workflow>' -ForEach @(
        @{ Workflow = 'tests' }
        @{ Workflow = 'publish' }
    ) {
        $text = Get-Content (Join-Path $root ".github/workflows/$Workflow.yml") -Raw
        $text | Should -Match 'dependency-mode:\s+description:[^\n]+\s+type: string\s+default: legacy'
        $text | Should -Match 'pester-required-version:'
        $text | Should -Match 'id: ci_modules'
        $text | Should -Match 'always\(\).*module-root'
        $text | Should -Match 'actions/cleanup-ps-modules@develop'
        $text | Should -Match 'isolated mode cannot use install-command'
    }

    It 'reuses existing analyzer inputs without introducing settings or Codecov' {
        $text = Get-Content (Join-Path $root '.github/workflows/tests.yml') -Raw
        $text | Should -Match 'required-version: \$\{\{ inputs.script-analyzer-required-version \}\}'
        $text | Should -Not -Match 'script-analyzer-settings-file|settings-file'
        $text | Should -Not -Match '(?i)codecov'
    }

    It 'exposes session test isolation by default and forwards it to nova-test' {
        $workflow = Get-Content (Join-Path $root '.github/workflows/tests.yml') -Raw
        $action = Get-Content (Join-Path $root 'actions/nova-test/action.yml') -Raw
        $workflow | Should -Match 'test-isolation:\s+description:[^\n]+\s+type: string\s+default: session'
        $workflow | Should -Match 'test-isolation: \$\{\{ inputs.test-isolation \}\}'
        $action | Should -Match 'test-isolation:\s+description:[^\n]+\s+required: false\s+default: session'
        $action | Should -Match '-TestIsolation \$env:TEST_ISOLATION'
    }

    It 'exposes an empty analyzer severity filter by default and forwards it to the analyzer' {
        $workflow = Get-Content (Join-Path $root '.github/workflows/tests.yml') -Raw
        $action = Get-Content (Join-Path $root 'actions/script-analyzer/action.yml') -Raw
        $workflow | Should -Match "script-analyzer-severity:\s+description:[^\n]+\s+type: string\s+default: ''"
        $workflow | Should -Match 'severity: \$\{\{ inputs.script-analyzer-severity \}\}'
        $action | Should -Match "severity:\s+description:[^\n]+\s+required: false\s+default: ''"
        $action | Should -Match '-Severity @\(\$env:SEVERITY -split'
    }

    It 'feeds the existing analyzer version input into isolated dependency selection' {
        $text = Get-Content (Join-Path $root '.github/workflows/tests.yml') -Raw
        $text | Should -Match 'script-analyzer-required-version: \$\{\{ inputs.script-analyzer-required-version \}\}'
    }
}

Describe 'Consumer onboarding examples' {
    It 'ships a Dependabot config that groups powershell-ci updates' {
        $path = Join-Path $root 'examples/dependabot.yml'
        Test-Path -LiteralPath $path | Should -BeTrue
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should -Match 'package-ecosystem: github-actions'
        $text | Should -Match 'interval: weekly'
        $text | Should -Match 'prefix: chore'
        $text | Should -Match 'powershell-ci:\s+patterns:\s+- "stiwicourage/powershell-ci\*"'
    }

    It 'pins <Example> to a release tag that Dependabot can update' -ForEach @(
        @{ Example = 'Tests.yml' }
        @{ Example = 'Publish.yml' }
        @{ Example = 'Security.yml' }
    ) {
        $text = Get-Content -LiteralPath (Join-Path $root "examples/$Example") -Raw
        $references = [regex]::Matches($text, 'stiwicourage/powershell-ci/[^@\s]+@(\S+)')
        $references.Count | Should -BeGreaterThan 0
        $references | ForEach-Object { $_.Groups[1].Value | Should -Match '^\d+\.\d+\.\d+$' }
    }
}
