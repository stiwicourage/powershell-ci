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

    It 'feeds the existing analyzer version input into isolated dependency selection' {
        $text = Get-Content (Join-Path $root '.github/workflows/tests.yml') -Raw
        $text | Should -Match 'script-analyzer-required-version: \$\{\{ inputs.script-analyzer-required-version \}\}'
    }
}
