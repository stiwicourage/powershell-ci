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

Describe 'Nova CI runner pinned and process-isolated variants in process' {
    BeforeAll {
        . (Join-Path $root 'actions/install-ps-modules/CiDependencyRoot.ps1')

        function Initialize-InProcessModuleFixture {
            param([string]$Path, [string]$Name, [string]$Body)
            $null = New-Item -ItemType Directory -Path $Path -Force
            $Body | Set-Content (Join-Path $Path "$Name.psm1")
            "@{ RootModule = '$Name.psm1'; ModuleVersion = '1.0.0' }" | Set-Content (Join-Path $Path "$Name.psd1")
        }
    }

    BeforeEach {
        $script:originalLocation = (Get-Location).Path
        $script:savedEnvironment = @{}
        foreach ($name in 'PSModulePath', 'POWERSHELL_CI_MODULE_ROOT', 'POWERSHELL_CI_OWNER_TOKEN') {
            $script:savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $env:POWERSHELL_CI_MODULE_ROOT = $null
        $script:project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path "$project/artifacts" -Force
        $script:destination = Join-Path $project 'published'
        Mock Import-Module {}
        Mock Remove-Module {}
        Mock Invoke-NovaBuild { 'build' }
        Mock Invoke-NovaTest { 'unit' }
        Mock Test-NovaBuild { 'integration' }
        Mock Get-NovaProjectInfo {
            @{ ProjectRoot = $project; ProjectName = 'Fixture'; OutputModuleDir = 'unused' }
        }
    }

    AfterEach {
        Set-Location -LiteralPath $script:originalLocation
        foreach ($name in $script:savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $script:savedEnvironment[$name])
        }
    }

    It 'verifies the retained Pester version and writes runtime evidence when a version is requested' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pester'; Version = [version]'5.7.1'; Path = 'p'; ModuleBase = 'b' } }
        & $runner -ProjectRoot $project -OutputDirectory $destination -PesterRequiredVersion 5.7.1 -SkipBuildValidation
        Should -Invoke Import-Module -ParameterFilter { $Name -eq 'Pester' -and $RequiredVersion -eq '5.7.1' }
        $evidence = Get-Content "$destination/runtime-evidence.json" -Raw | ConvertFrom-Json
        $evidence.Modules.Name | Should -Contain 'Pester'
    }

    It 'fails the run when the requested Pester version was not retained' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pester'; Version = [version]'6.0.0'; Path = 'p'; ModuleBase = 'b' } }
        { & $runner -ProjectRoot $project -OutputDirectory $destination -PesterRequiredVersion 5.7.1 } |
            Should -Throw '*Nova did not retain requested Pester 5.7.1*'
    }

    It 'rechecks dependency origin against the owned root before importing the built module' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive "powershell-ci-modules-$([guid]::NewGuid().ToString('N'))")
        $env:POWERSHELL_CI_MODULE_ROOT = $owner.Path
        $env:POWERSHELL_CI_OWNER_TOKEN = $owner.Token
        Mock Get-Module { [pscustomobject]@{ Name = 'Pester'; Version = [version]'5.7.1'; Path = 'p'; ModuleBase = (Join-Path $owner.Path 'Pester/5.7.1') } }
        { & $runner -ProjectRoot $project -OutputDirectory $destination -PesterRequiredVersion 5.7.1 -SkipBuildValidation } | Should -Not -Throw
        Should -Invoke Invoke-NovaTest -Exactly -Times 1
        Test-Path "$destination/runtime-evidence.json" | Should -BeTrue
    }

    Describe 'Process isolation' {
        BeforeEach {
            $script:moduleRoot = Join-Path $TestDrive "modules-$([guid]::NewGuid().ToString('N'))"
            $nova = @'
function Invoke-NovaTest { param([string[]]$ExcludeTagFilter) "unit|$($ExcludeTagFilter -join ',')" | Set-Content './artifacts/unit.txt' }
function Test-NovaBuild {
    param([string[]]$ExcludeTagFilter)
    if (Test-Path './fail-integration') { throw 'integration failed' }
    "integration|$($ExcludeTagFilter -join ',')" | Set-Content './artifacts/integration.txt'
}
'@
            Initialize-InProcessModuleFixture -Path "$moduleRoot/NovaModuleTools" -Name NovaModuleTools -Body $nova
            Initialize-InProcessModuleFixture -Path "$project/dist/Fixture" -Name Fixture -Body 'function Get-FixtureValue { 1 }'
            $env:PSModulePath = $moduleRoot + [IO.Path]::PathSeparator + $env:PSModulePath
            Mock Get-NovaProjectInfo {
                @{ ProjectRoot = $project; ProjectName = 'Fixture'; OutputModuleDir = "$project/dist/Fixture" }
            }
        }

        It 'runs both phases in fresh processes and forwards the exclusions' {
            & $runner -ProjectRoot $project -OutputDirectory $destination -TestIsolation process -ExcludeTag Live, Slow
            (Get-Content "$project/artifacts/unit.txt" -Raw).Trim() | Should -BeExactly 'unit|Live,Slow'
            (Get-Content "$project/artifacts/integration.txt" -Raw).Trim() | Should -BeExactly 'integration|Live,Slow'
            Should -Invoke Invoke-NovaTest -Times 0
            Should -Invoke Test-NovaBuild -Times 0
        }

        It 'fails the run with the child exit code when a fresh-process phase fails' {
            New-Item -ItemType File -Path "$project/fail-integration" | Out-Null
            $result = @(& $runner -ProjectRoot $project -OutputDirectory $destination -TestIsolation process 2>&1 3>&1)
            $LASTEXITCODE | Should -Be 1
            ($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Message |
                Should -Match 'Test-NovaBuild failed in a fresh PowerShell process \(exit code 1\)'
        }
    }
}
