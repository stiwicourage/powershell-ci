BeforeAll {
    $script:scriptPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/Set-InternalActionRefs.ps1'
}

Describe 'Set-InternalActionRefs' {
    BeforeEach {
        $script:examples = Join-Path $TestDrive 'examples'
        New-Item -ItemType Directory -Path $examples -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $examples 'Tests.yml') -NoNewline -Value (
            "jobs:`n  t:`n    uses: stiwicourage/powershell-ci/.github/workflows/tests.yml@0.1.0`n    with:`n      x: actions/checkout@v4`n")
        Set-Content -LiteralPath (Join-Path $examples 'dependabot.yml') -NoNewline -Value '- "stiwicourage/powershell-ci*"'
    }

    It 'pins every powershell-ci reference in the given directory to the release version' {
        & $scriptPath -Ref '0.5.0' -Path $examples | Out-Null

        $text = Get-Content -LiteralPath (Join-Path $examples 'Tests.yml') -Raw
        $text | Should -Match 'powershell-ci/\.github/workflows/tests\.yml@0\.5\.0\n'
        $text | Should -Match 'x: actions/checkout@v4'
        Get-Content -LiteralPath (Join-Path $examples 'dependabot.yml') -Raw | Should -Be '- "stiwicourage/powershell-ci*"'
    }

    It 'targets the sibling examples directory by default' {
        $scripts = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts') -Force
        Copy-Item -LiteralPath $scriptPath -Destination $scripts.FullName

        & (Join-Path $scripts.FullName 'Set-InternalActionRefs.ps1') -Ref '0.5.0' | Out-Null

        Get-Content -LiteralPath (Join-Path $examples 'Tests.yml') -Raw | Should -Match 'tests\.yml@0\.5\.0'
    }
}
