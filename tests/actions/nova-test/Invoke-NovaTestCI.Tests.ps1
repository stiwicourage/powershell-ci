BeforeAll {
    function Invoke-NovaBuild {}
    function Get-NovaProjectInfo {}
    function Invoke-NovaTest {
        param([string[]]$ExcludeTagFilter)
        throw "Unmocked unit test collaborator: $ExcludeTagFilter"
    }
    function Test-NovaBuild {
        param([string[]]$ExcludeTagFilter)
        throw "Unmocked integration collaborator: $ExcludeTagFilter"
    }
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:runner = Join-Path $root 'actions/nova-test/Invoke-NovaTestCI.ps1'
}

Describe 'Nova CI existing contracts' {
    BeforeEach {
        $script:originalLocation = (Get-Location).Path
        $script:project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path "$project/artifacts" -Force
        $script:destination = Join-Path $project 'published'
        Mock Import-Module {}
        Mock Remove-Module {}
        Mock Invoke-NovaBuild { 'build' }
        Mock Get-NovaProjectInfo {
            @{ ProjectRoot = $project; ProjectName = 'Fixture'; OutputModuleDir = 'unused' }
        }
        Mock Invoke-NovaTest { 'unit' }
        Mock Test-NovaBuild { 'integration' }
    }

    AfterEach { Set-Location -LiteralPath $script:originalLocation }

    Describe 'Coverage survives both integration report behaviors' {
        BeforeEach {
            Mock Invoke-NovaTest { Set-Content "$project/artifacts/coverage.xml" '<report name="unit" />'; 'unit' }
            Mock Test-NovaBuild {
                Set-Content "$project/artifacts/TestResults.xml" '<test-results />'
                if ($OverwriteCoverage) { Set-Content "$project/artifacts/coverage.xml" '<report name="integration" />' }
                'integration'
            }
        }

        It 'runs unit tests before integration and preserves unit coverage (<Scenario>)' -ForEach @(
            @{ Scenario = 'integration writes NUnit only'; OverwriteCoverage = $false; UseSourceOutput = $false }
            @{ Scenario = 'integration overwrites coverage'; OverwriteCoverage = $true; UseSourceOutput = $false }
            @{ Scenario = 'default output survives overwritten coverage'; OverwriteCoverage = $true; UseSourceOutput = $true }
        ) {
            $outputPath = if ($UseSourceOutput) { Join-Path $project 'artifacts' } else { $destination }
            $result = @(& $runner -ProjectRoot $project -OutputDirectory $outputPath)
            $result -join ',' | Should -BeExactly 'build,unit,integration'
            (Get-Content "$outputPath/coverage.xml" -Raw).Trim() | Should -BeExactly '<report name="unit" />'
            Test-Path "$outputPath/fixture-nunit.xml" | Should -BeTrue
        }
    }

    It 'forwards exclusions to both phases without changing defaults' {
        & $runner -ProjectRoot $project -OutputDirectory $destination -ExcludeTag RepositoryLive
        Should -Invoke Invoke-NovaTest -Exactly -Times 1 -ParameterFilter { $ExcludeTagFilter -contains 'RepositoryLive' -and @($ExcludeTagFilter).Count -eq 1 }
        Should -Invoke Test-NovaBuild -Exactly -Times 1 -ParameterFilter { $ExcludeTagFilter -contains 'RepositoryLive' -and @($ExcludeTagFilter).Count -eq 1 }
    }

    Describe 'Failure streams and retained reports' {
        BeforeEach {
            Mock Invoke-NovaTest {
                Set-Content "$project/artifacts/coverage.xml" '<report name="unit" />'
                Set-Content "$project/artifacts/TestResults.xml" '<test-results />'
                if ($Phase -eq 'unit') { throw 'unit failed' }
                'unit'
            }
            Mock Test-NovaBuild {
                Set-Content "$project/artifacts/coverage.xml" '<report name="integration" />'
                throw 'integration failed'
            }
        }

        It 'retains reports and exit status after a <Phase> failure' -ForEach @(
            @{ Phase = 'unit'; IntegrationCalls = 0 }
            @{ Phase = 'integration'; IntegrationCalls = 1 }
        ) {
            $result = @(& $runner -ProjectRoot $project -OutputDirectory $destination 3>&1)
            $LASTEXITCODE | Should -Be 1
            @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })[0].Message | Should -Match "$Phase failed"
            (Get-Content "$destination/coverage.xml" -Raw).Trim() | Should -BeExactly '<report name="unit" />'
            Test-Path "$destination/fixture-nunit.xml" | Should -BeTrue
            Should -Invoke Test-NovaBuild -Exactly -Times $IntegrationCalls
        }
    }

    It 'skips build validation when requested and tolerates missing artifacts' {
        $result = @(& $runner -ProjectRoot $project -OutputDirectory $destination -SkipBuildValidation)
        $result -join ',' | Should -BeExactly 'build,unit'
        Should -Invoke Test-NovaBuild -Times 0
        Test-Path "$destination/coverage.xml" | Should -BeFalse
    }

    It 'retains artifacts when output is the source artifacts directory' {
        Set-Content "$project/artifacts/coverage.xml" '<report />'
        & $runner -ProjectRoot $project -OutputDirectory "$project/artifacts" -SkipBuildValidation
        (Get-Content "$project/artifacts/coverage.xml" -Raw).Trim() | Should -BeExactly '<report />'
    }
}
