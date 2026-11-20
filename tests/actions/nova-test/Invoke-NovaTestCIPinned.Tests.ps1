BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'actions/install-ps-modules/CiDependencyRoot.ps1')
    $runner = Join-Path $root 'actions/nova-test/Invoke-NovaTestCI.ps1'

    function Initialize-CiRunnerModuleFixture {
        param([string]$Path, [string]$Name, [string]$Body, [string]$Version = '1.0.0')
        $null = New-Item -ItemType Directory -Path $Path -Force
        $Body | Set-Content (Join-Path $Path "$Name.psm1")
        "@{ RootModule = '$Name.psm1'; ModuleVersion = '$Version' }" |
            Set-Content (Join-Path $Path "$Name.psd1")
    }

    function Invoke-CiPinnedRunnerFixture {
        param([object]$Owner, [string]$Project, [string]$Runner, [string]$TestIsolation = 'session')
        $command = '$env:POWERSHELL_CI_MODULE_ROOT="{0}"; $env:POWERSHELL_CI_OWNER_TOKEN="{1}"; & "{2}" -ProjectRoot "{3}" -OutputDirectory "{3}/published" -PesterRequiredVersion 5.7.1 -TestIsolation {4}' -f $Owner.Path, $Owner.Token, $Runner, $Project, $TestIsolation
        $output = @(& (Get-Process -Id $PID).Path -NoLogo -NoProfile -Command $command 2>&1)
        return @{ ExitCode = $LASTEXITCODE; Output = @($output | ForEach-Object { $_.ToString() }) }
    }

    $script:novaBody = @'
function Invoke-NovaBuild { 'build' }
function Get-NovaProjectInfo {
    return @{ ProjectRoot = (Get-Location).Path; ProjectName = 'Fixture'; OutputModuleDir = (Join-Path (Get-Location).Path 'dist/Fixture') }
}
function Invoke-NovaTest {
    param([string[]]$ExcludeTagFilter)
    Get-FixtureValue | Out-Null
    $evidence = Get-Content './published/runtime-evidence.json' -Raw | ConvertFrom-Json
    if (-not ($evidence.Modules | Where-Object Name -EQ Fixture)) { throw 'SUT missing from pre-test runtime evidence.' }
    '<report name="unit" />' | Set-Content './artifacts/coverage.xml'
    $ExcludeTagFilter -join ',' | Set-Content './artifacts/unit-tags.txt'
    'unit'
}
function Test-NovaBuild {
    param([string[]]$ExcludeTagFilter)
    '<test-results />' | Set-Content './artifacts/TestResults.xml'
    '<report name="integration" />' | Set-Content './artifacts/coverage.xml'
    $ExcludeTagFilter -join ',' | Set-Content './artifacts/integration-tags.txt'
    'integration'
}
if (Test-Path './rogue/Rogue.psd1') { Import-Module './rogue/Rogue.psd1' -Global }
'@
}

Describe 'Pinned isolated Nova runner with a workspace SUT' {
    BeforeEach {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive "powershell-ci-modules-$([guid]::NewGuid().ToString('N'))")
        $project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path "$project/artifacts" -Force
        Initialize-CiRunnerModuleFixture -Path "$($owner.Path)/Pester/5.7.1" -Name Pester -Version 5.7.1 -Body ''
        Initialize-CiRunnerModuleFixture -Path "$($owner.Path)/NovaModuleTools" -Name NovaModuleTools -Body $script:novaBody
        Initialize-CiRunnerModuleFixture -Path "$project/dist/Fixture" -Name Fixture -Body "function Get-FixtureValue { 'sut' }; 'imported' | Set-Content './artifacts/sut-imported.txt'"
    }

    AfterEach { Remove-CiDependencyRoot -Owner $owner }

    It 'imports the workspace SUT and reaches both phases and reports with owned pinned Pester (<TestIsolation>)' -ForEach @(
        @{ TestIsolation = 'session' }
        @{ TestIsolation = 'process' }
    ) {
        $result = Invoke-CiPinnedRunnerFixture -Owner $owner -Project $project -Runner $runner -TestIsolation $TestIsolation
        $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
        $result.Output -join ',' | Should -BeExactly 'build,unit,integration'
        (Get-Content "$project/published/coverage.xml" -Raw).Trim() | Should -BeExactly '<report name="unit" />'
        Test-Path "$project/published/fixture-nunit.xml" | Should -BeTrue
        $evidence = Get-Content "$project/published/runtime-evidence.json" -Raw | ConvertFrom-Json
        ($evidence.Modules | Where-Object Name -EQ Fixture).Path | Should -BeExactly (Join-Path (Resolve-Path "$project/dist/Fixture").Path 'Fixture.psm1')
        ($evidence.Modules | Where-Object Name -EQ Pester).Path | Should -BeExactly (Join-Path $owner.Path 'Pester/5.7.1/Pester.psm1')
        ($evidence.Modules | Where-Object Name -EQ Pester).Version | Should -BeExactly '5.7.1'
    }

    It 'still rejects a workspace CI dependency loaded by Nova before importing the SUT' {
        Initialize-CiRunnerModuleFixture -Path "$project/rogue" -Name Rogue -Body "function Get-RogueValue { 'rogue' }"
        $result = Invoke-CiPinnedRunnerFixture -Owner $owner -Project $project -Runner $runner
        $result.ExitCode | Should -Be 1
        $result.Output -join "`n" | Should -Match 'Dependency resolved outside isolation: Rogue'
        Test-Path "$project/published/runtime-evidence.json" | Should -BeFalse
        Test-Path "$project/published/fixture-nunit.xml" | Should -BeFalse
        Test-Path "$project/artifacts/coverage.xml" | Should -BeFalse
        Test-Path "$project/artifacts/sut-imported.txt" | Should -BeFalse
    }
}
