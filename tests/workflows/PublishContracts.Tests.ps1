BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:publishSource = Get-Content (Join-Path $root '.github/workflows/publish.yml') -Raw
    function Invoke-NovaRelease {
        param($Repository, $ApiKey, [switch]$SkipTests, [switch]$ContinuousIntegration)
        throw "Unmocked release for $Repository (key supplied=$([bool]$ApiKey), skip=$SkipTests, CI=$ContinuousIntegration)."
    }
    function Get-NovaProjectInfo { param([switch]$Version) if ($Version) { '1.2.3' } }
    function Move-UnreleasedChangelog { param($Path = './CHANGELOG.md', $Version) @{ TagMessageText = "$Path $Version" } }
    function Test-NovaBuild { 'integration' }
    function Get-PublishStep {
        param([string]$Name)
        $pattern = '(?ms)^      - name: ' + [regex]::Escape($Name) + '\r?\n.*?(?=^      - name: |\z)'
        return [regex]::Match($script:publish, $pattern).Value
    }
}

Describe 'Existing publish commands and branch guards (<LineEnding>)' -ForEach @(
    @{ LineEnding = 'LF'; NewLine = "`n" }
    @{ LineEnding = 'CRLF'; NewLine = "`r`n" }
) {
    BeforeAll { $script:publish = $script:publishSource -replace '\r?\n', $NewLine }

    BeforeEach {
        $script:environment = @{}
        foreach ($name in @('GITHUB_OUTPUT', 'PSGALLERY_API', 'RELEASE_REPOSITORY', 'RELEASE_CI', 'POWERSHELL_CI_BOOTSTRAP', 'PESTER_REQUIRED_VERSION')) {
            $environment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'release-output.txt'
        $env:PSGALLERY_API = 'fixture-not-an-api-key'
        $env:RELEASE_REPOSITORY = 'PSGallery'
        $env:POWERSHELL_CI_BOOTSTRAP = ''
        $env:PESTER_REQUIRED_VERSION = ''
        Mock Invoke-NovaRelease {}
        Mock Move-UnreleasedChangelog { @{ TagMessageText = 'fixture release' } }
    }

    AfterEach {
        foreach ($name in $environment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $environment[$name])
        }
    }

    It 'preserves stable release arguments and both release files (CI=<CI>)' -ForEach @(
        @{ CI = 'true'; ExpectedCI = $true }
        @{ CI = 'false'; ExpectedCI = $false }
    ) {
        $env:RELEASE_CI = $CI
        $run = (Get-PublishStep -Name 'Run release') -split '        run: \|\r?\n', 2
        & ([scriptblock]::Create($run[1]))
        Should -Invoke Invoke-NovaRelease -Exactly -Times 1 -ParameterFilter { $SkipTests -and [bool]$ContinuousIntegration -eq $ExpectedCI }
        Should -Invoke Move-UnreleasedChangelog -Exactly -Times 1 -ParameterFilter { -not $Path -and $Version -eq '1.2.3' }
        Should -Invoke Move-UnreleasedChangelog -Exactly -Times 1 -ParameterFilter { $Path -eq './RELEASE_NOTE.md' -and $Version -eq '1.2.3' }
    }

    It 'routes the existing Test-NovaBuild override without introducing another publish API' {
        $run = (Get-PublishStep -Name 'Run Pester tests') -split '        run: \|\r?\n', 2
        $command = $run[1].Replace('${{ inputs.test-command }}', 'Test-NovaBuild')
        & ([scriptblock]::Create($command)) | Should -BeExactly 'integration'
    }

    It 'retains stable and prerelease branch guards and release-loop prevention' {
        Get-PublishStep -Name 'Run release' | Should -Match 'github.ref_name == inputs.release-branch'
        Get-PublishStep -Name 'Publish develop prerelease' | Should -Match 'github.ref_name == inputs.develop-branch'
        $publish | Should -Match "startsWith\(github.event.head_commit.message \|\| '', 'chore\(release\): '\)"
        $publish | Should -Not -Match 'dry-run'
    }
}
