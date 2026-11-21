BeforeDiscovery {
    $script:workflowCases = @(
        @{ Workflow = 'tests' }
        @{ Workflow = 'publish' }
    )
}

BeforeAll {
    $script:root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    function Get-WorkflowJob {
        param([string]$Workflow)
        $path = Join-Path $script:root ".github/workflows/$Workflow.yml"
        $text = (Get-Content -LiteralPath $path -Raw) -replace '\r\n', "`n"
        $jobs = $text.Substring($text.IndexOf("`njobs:`n"))
        return [regex]::Matches($jobs, '(?ms)^  [\w-]+:\n.*?(?=^  [\w-]+:\n|\z)') | ForEach-Object Value
    }
}

Describe 'Reusable workflows run the powershell-ci actions of their own version (<Workflow>)' -ForEach $workflowCases {
    It 'has no branch or tag references to its own actions' {
        $text = Get-Content -LiteralPath (Join-Path $root ".github/workflows/$Workflow.yml") -Raw
        $text | Should -Not -Match 'stiwicourage/powershell-ci/actions/'
    }

    It 'checks out its own commit before the first internal action in every job that uses one' {
        $jobs = @(Get-WorkflowJob -Workflow $Workflow | Where-Object { $_ -match 'uses: \./\.powershell-ci/actions/' })
        $jobs.Count | Should -BeGreaterThan 0
        foreach ($job in $jobs) {
            $checkout = $job.IndexOf('repository: ${{ job.workflow_repository }}')
            $checkout | Should -BeGreaterThan $job.IndexOf('uses: actions/checkout@v4')
            $job | Should -Match 'repository: \$\{\{ job\.workflow_repository \}\}\s+ref: \$\{\{ job\.workflow_sha \}\}\s+path: \.powershell-ci'
            $job.IndexOf('info/exclude') | Should -BeGreaterThan $checkout
            $job.IndexOf('uses: ./.powershell-ci/actions/') | Should -BeGreaterThan $job.IndexOf('info/exclude')
        }
    }
}
