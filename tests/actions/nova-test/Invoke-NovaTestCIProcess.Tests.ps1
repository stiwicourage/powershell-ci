BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:runner = Join-Path $root 'actions/nova-test/Invoke-NovaTestCI.ps1'

    function Initialize-CiProcessModuleFixture {
        param([string]$Path, [string]$Name, [string]$Body)
        $null = New-Item -ItemType Directory -Path $Path -Force
        $Body | Set-Content (Join-Path $Path "$Name.psm1")
        "@{ RootModule = '$Name.psm1'; ModuleVersion = '1.0.0' }" | Set-Content (Join-Path $Path "$Name.psd1")
    }

    function Invoke-CiProcessRunnerFixture {
        param([string]$ModuleRoot, [string]$Project, [string]$Arguments = '')
        $separator = [IO.Path]::PathSeparator
        $command = '$env:PSModulePath = "{0}{1}" + $env:PSModulePath; & "{2}" -ProjectRoot "{3}" -OutputDirectory "{3}/published" -TestIsolation process {4}' -f $ModuleRoot, $separator, $script:runner, $Project, $Arguments
        $output = @(& (Get-Process -Id $PID).Path -NoLogo -NoProfile -Command $command 2>&1)
        return @{ ExitCode = $LASTEXITCODE; Output = @($output | ForEach-Object { $_.ToString() }) }
    }

    $script:novaBody = @'
function Invoke-NovaBuild { $PID | Set-Content './artifacts/runner-pid.txt'; 'build' }
function Get-NovaProjectInfo {
    return @{ ProjectRoot = (Get-Location).Path; ProjectName = 'Fixture'; OutputModuleDir = (Join-Path (Get-Location).Path 'dist/Fixture') }
}
function Write-FixturePhase {
    param([string]$Phase, [string[]]$ExcludeTagFilter)
    "$PID|$(Get-FixtureValue)|$($ExcludeTagFilter -join ',')" | Set-Content "./artifacts/$Phase.txt"
    if (Test-Path "./fail-$Phase") { throw "$Phase failed" }
}
function Invoke-NovaTest {
    param([string[]]$ExcludeTagFilter)
    Write-FixturePhase -Phase unit -ExcludeTagFilter $ExcludeTagFilter
    '<report name="unit" />' | Set-Content './artifacts/coverage.xml'
    'unit'
}
function Test-NovaBuild {
    param([string[]]$ExcludeTagFilter)
    Write-FixturePhase -Phase integration -ExcludeTagFilter $ExcludeTagFilter
    '<test-results />' | Set-Content './artifacts/TestResults.xml'
    '<report name="integration" />' | Set-Content './artifacts/coverage.xml'
    'integration'
}
'@
}

Describe 'Nova runner with process test isolation' {
    BeforeEach {
        $moduleRoot = Join-Path $TestDrive "modules-$([guid]::NewGuid().ToString('N'))"
        $project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path "$project/artifacts" -Force
        Initialize-CiProcessModuleFixture -Path "$moduleRoot/NovaModuleTools" -Name NovaModuleTools -Body $script:novaBody
        Initialize-CiProcessModuleFixture -Path "$project/dist/Fixture" -Name Fixture -Body "function Get-FixtureValue { 'sut' }"
    }

    It 'runs each phase in a fresh process with the built SUT and forwarded exclusions' {
        $result = Invoke-CiProcessRunnerFixture -ModuleRoot $moduleRoot -Project $project -Arguments '-ExcludeTag Live, Slow'
        $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
        $result.Output -join ',' | Should -BeExactly 'build,unit,integration'
        $runnerPid = (Get-Content "$project/artifacts/runner-pid.txt" -Raw).Trim()
        $unit = (Get-Content "$project/artifacts/unit.txt" -Raw).Trim() -split '\|'
        $integration = (Get-Content "$project/artifacts/integration.txt" -Raw).Trim() -split '\|'
        $unit[0] | Should -Not -Be $runnerPid
        $integration[0] | Should -Not -BeIn @($runnerPid, $unit[0])
        $unit[1..2] | Should -Be @('sut', 'Live,Slow')
        $integration[1..2] | Should -Be @('sut', 'Live,Slow')
        (Get-Content "$project/published/coverage.xml" -Raw).Trim() | Should -BeExactly '<report name="unit" />'
        Test-Path "$project/published/fixture-nunit.xml" | Should -BeTrue
    }

    It 'fails without build validation when the unit process fails' {
        $null = New-Item -ItemType File -Path "$project/fail-unit"
        $result = Invoke-CiProcessRunnerFixture -ModuleRoot $moduleRoot -Project $project
        $result.ExitCode | Should -Be 1
        $result.Output -join "`n" | Should -Match 'Invoke-NovaTest failed in a fresh PowerShell process'
        Test-Path "$project/artifacts/integration.txt" | Should -BeFalse
    }

    It 'skips the build validation process when requested' {
        $result = Invoke-CiProcessRunnerFixture -ModuleRoot $moduleRoot -Project $project -Arguments '-SkipBuildValidation'
        $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
        $result.Output -join ',' | Should -BeExactly 'build,unit'
        Test-Path "$project/artifacts/integration.txt" | Should -BeFalse
    }
}
