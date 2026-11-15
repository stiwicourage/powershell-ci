BeforeAll {
    $script:root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    function Get-WorkflowConsumerStep {
        param([string]$Workflow)
        $text = Get-Content (Join-Path $root ".github/workflows/$Workflow.yml") -Raw
        return [regex]::Matches($text, '(?ms)^      - name: ([^\n]+)\n(.*?)(?=^      - name: |\z)')
    }
}

Describe 'Each isolated PowerShell step initializes discovery before consumers' {
    It 'bootstraps the existing PSResource repository action before consuming modules' {
        $action = Get-Content (Join-Path $root 'actions/ensure-psresource-repository/action.yml') -Raw
        $action | Should -Match 'Initialize-CiDependencyEnvironment'
    }

    It 'bootstraps every post-install PowerShell run in <Workflow>' -ForEach @(
        @{ Workflow = 'tests' }
        @{ Workflow = 'publish' }
    ) {
        $steps = Get-WorkflowConsumerStep -Workflow $Workflow
        foreach ($step in $steps) {
            if ($step.Value -notmatch '        run:' -or $step.Value -match 'name: (Validate dependency mode|Install required|Install CodeScene)') { continue }
            $step.Value | Should -Match 'POWERSHELL_CI_BOOTSTRAP'
            $step.Value | Should -Match 'Initialize-CiDependencyEnvironment'
        }
    }

    It 'retains the token independently in the next-step environment' {
        . (Join-Path $root 'actions/install-ps-modules/Install-CiModules.ps1')
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-output')
        $old = $env:GITHUB_ENV
        try {
            $env:GITHUB_ENV = Join-Path $TestDrive 'environment.txt'
            Publish-CiDependencyEnvironment -Owner $owner
            Get-Content $env:GITHUB_ENV | Should -Contain "POWERSHELL_CI_OWNER_TOKEN=$($owner.Token)"
        } finally { $env:GITHUB_ENV = $old }
    }

    It 'emits the validated module-root and module-path outputs together' {
        . (Join-Path $root 'actions/install-ps-modules/Install-CiModules.ps1')
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-action-output')
        $old = $env:GITHUB_OUTPUT
        try {
            $env:GITHUB_OUTPUT = Join-Path $TestDrive 'outputs.txt'
            Publish-CiDependencyEnvironment -Owner $owner
            Get-Content $env:GITHUB_OUTPUT | Should -Contain "module-root=$($owner.Path)"
            Get-Content $env:GITHUB_OUTPUT | Should -Contain "module-path=$(Get-CiIsolatedModulePath -ModuleRoot $owner.Path)"
        } finally { $env:GITHUB_OUTPUT = $old }
    }
}
