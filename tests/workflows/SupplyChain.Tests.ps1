BeforeAll {
    $script:root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe 'OpenSSF Scorecard readiness' {
    It 'pins every external action in <Name> to a full commit SHA' -ForEach @(
        Get-ChildItem (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.github/workflows'), (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'actions') -Recurse -Include *.yml |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $external = Select-String -Path $Path -Pattern '^\s*(?:-\s+)?uses:\s*(\S+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } |
            Where-Object { $_ -notmatch '^\./' }
        $unpinned = @($external | Where-Object { $_ -notmatch '@[0-9a-f]{40}$' })
        $unpinned | Should -BeNullOrEmpty
    }

    It 'grants no write permission at the top level of <Name>' -ForEach @(
        Get-ChildItem (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.github/workflows') -Filter *.yml |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $text = Get-Content -LiteralPath $Path -Raw
        $topLevel = [regex]::Match($text, '(?m)^permissions:\r?\n((?:[ ]+\S.*\r?\n)+)')
        $topLevel.Groups[1].Value | Should -Not -Match ':\s*write'
    }

    It 'runs Scorecard with published results using pinned actions' {
        $text = Get-Content (Join-Path $root '.github/workflows/scorecard.yml') -Raw
        $text | Should -Match 'ossf/scorecard-action@[0-9a-f]{40}'
        $text | Should -Match 'publish_results: true'
        $text | Should -Match 'security-events: write'
        $text | Should -Match 'id-token: write'
    }

    It 'ships a security policy and a Dependabot config for GitHub Actions' {
        Test-Path (Join-Path $root 'SECURITY.md') | Should -BeTrue
        $dependabot = Get-Content (Join-Path $root '.github/dependabot.yml') -Raw
        $dependabot | Should -Match 'package-ecosystem: github-actions'
    }
}

Describe 'OpenSSF Best Practices documentation' {
    It 'explains the contribution process and requirements in CONTRIBUTING.md' {
        $text = Get-Content (Join-Path $root 'CONTRIBUTING.md') -Raw
        $text | Should -Match 'pull request'
        $text | Should -Match 'Invoke-Pester'
        $text | Should -Match 'CHANGELOG\.md'
        $text | Should -Match 'SECURITY\.md'
        $text | Should -Match 'issues/new'
    }

    It 'offers bug-report and feature-request issue forms' -ForEach @('bug_report.yml', 'feature_request.yml') {
        Test-Path (Join-Path $root ".github/ISSUE_TEMPLATE/$_") | Should -BeTrue
    }

    It 'shows the tag version and OpenSSF Best Practices badges at the top of the README' {
        $lines = Get-Content (Join-Path $root 'README.md') -TotalCount 4
        ($lines -join "`n") | Should -Match '\[!\[Tag\]\(https://img\.shields\.io/github/v/tag/stiwicourage/powershell-ci[^)]*\)\]\(https://github\.com/stiwicourage/powershell-ci/tags\)'
        ($lines -join "`n") | Should -Match '\[!\[OpenSSF Best Practices\]\(https://www\.bestpractices\.dev/projects/17041/badge\)\]\(https://www\.bestpractices\.dev/projects/17041\)'
    }

    It 'links the community files and the input reference from the README' {
        $text = Get-Content (Join-Path $root 'README.md') -Raw
        $text | Should -Match '\(CONTRIBUTING\.md\)'
        $text | Should -Match '\(SECURITY\.md\)'
        $text | Should -Match '\(CODE_OF_CONDUCT\.md\)'
        $text | Should -Match '\(LICENSE\)'
        $text | Should -Match '(?i)## Reference'
        $text | Should -Match '(?i)## Using it securely'
    }
}

Describe 'OpenSSF Best Practices docs folder' {
    It 'documents <Topic> in docs/<File>' -ForEach @(
        @{ Topic = 'installing, starting and using the workflows'; File = 'GETTING-STARTED.md'; Pattern = '(?s)(?=.*## Install)(?=.*## Start)(?=.*## Use)' }
        @{ Topic = 'secure use'; File = 'USING-SECURELY.md'; Pattern = '(?s)(?=.*(?i)pin)(?=.*(?i)permissions)(?=.*(?i)secrets)' }
    ) {
        $text = Get-Content (Join-Path $root "docs/$File") -Raw
        $text | Should -Match $Pattern
    }

    It 'links the docs folder from the README' {
        (Get-Content (Join-Path $root 'README.md') -Raw) | Should -Match '\(docs/GETTING-STARTED\.md\)'
        (Get-Content (Join-Path $root 'README.md') -Raw) | Should -Match '\(docs/USING-SECURELY\.md\)'
    }
}
