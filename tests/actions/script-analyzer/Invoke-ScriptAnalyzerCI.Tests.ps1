$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $projectRoot 'actions/script-analyzer/Invoke-ScriptAnalyzerCI.ps1'
$env:SCRIPTANALYZER_TEST_PROJECT_ROOT = $projectRoot
$env:SCRIPTANALYZER_TEST_SCRIPT_PATH = $scriptPath

BeforeAll {
    $projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $scriptPath = Join-Path $projectRoot 'actions/script-analyzer/Invoke-ScriptAnalyzerCI.ps1'
    . $scriptPath
    Import-Module (Join-Path $projectRoot 'tests/TestHelpers/ScriptAnalyzerTestSupport.psm1') -Force
}

Describe 'Invoke-ScriptAnalyzerCI helpers' {
    Describe 'Transient retry scenarios' {
        BeforeEach {
            $script:analyzerCallCount = 0
            Mock Invoke-ScriptAnalyzer {
                $script:analyzerCallCount++
                if ($script:analyzerCallCount -le $FailureCount) {
                    throw [System.NullReferenceException]::new('transient analyzer failure')
                }
                return @()
            }
        }

        It 'excludes only host-output diagnostics after <FailureCount> transient failures' -ForEach @(
            @{ FailureCount = 0 }
            @{ FailureCount = 1 }
        ) {
            Invoke-ScriptAnalyzerWithTransientRetry -Path 'sample.ps1' | Should -BeNullOrEmpty
            Should -Invoke Invoke-ScriptAnalyzer -Exactly -Times ($FailureCount + 1) -ParameterFilter {
                ($ExcludeRule -join ',') -eq 'PSAvoidUsingWriteHost'
            }
        }

        It 'retries one transient analyzer null-reference failure' -ForEach @{ FailureCount = 1 } {
            $result = @(Invoke-ScriptAnalyzerWithTransientRetry -Path 'sample.ps1')
            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-ScriptAnalyzer -Times 2
        }
    }

    It 'allows intentional host output without excluding other real analyzer diagnostics' {
        $path = Join-Path $TestDrive 'HostOutput.ps1'
        Set-Content -LiteralPath $path -Value @(
            "Write-Host 'Intentional terminal output.'"
            'function Bad-AnalyzerFixture { }'
        )

        $result = @(Invoke-ScriptAnalyzerWithTransientRetry -Path $path)

        @($result | Where-Object RuleName -EQ 'PSAvoidUsingWriteHost') | Should -BeNullOrEmpty
        $result.RuleName | Should -Contain 'PSUseApprovedVerbs'
    }

    It 'does not retry non-transient analyzer failures' {
        Mock Invoke-ScriptAnalyzer {
            throw [System.InvalidOperationException]::new('persistent analyzer failure')
        }

        {
            Invoke-ScriptAnalyzerWithTransientRetry -Path 'sample.ps1'
        } | Should -Throw '*persistent analyzer failure*'

        Should -Invoke Invoke-ScriptAnalyzer -Times 1
    }

    It 'includes tests and excludes generated directories from the analyzer scope' {
        $repositoryRoot = Join-Path $TestDrive 'repo'
        $script:ScriptAnalyzerPathList = @('src', 'scripts', 'tests', 'run.ps1')
        Initialize-ScriptAnalyzerPathFixture -Path $repositoryRoot

        $pathList = @(Get-ScriptAnalyzerAnalysisPathList -RepositoryRoot $repositoryRoot)
        $relativePathList = @(
            $pathList | ForEach-Object {
                [System.IO.Path]::GetRelativePath($repositoryRoot, $_).Replace('\', '/')
            }
        )

        $relativePathList | Should -Contain 'src/One.ps1'
        $relativePathList | Should -Contain 'tests/One.Tests.ps1'
        $relativePathList | Should -Not -Contain 'artifacts/Generated.ps1'
        $relativePathList | Should -Not -Contain 'dist/Generated.ps1'
    }

    It 'converts ScriptAnalyzer results to repository-relative finding records' {
        $resultList = Get-FakeScriptAnalyzerResult -PropertyOverrides @{
                Severity     = 'Warning'
                RuleName     = 'Rule.One'
                RelativePath = 'src/one.ps1'
                Line         = 9
                Message      = 'Repeated finding.'
        }

        $findingList = ConvertTo-ScriptAnalyzerFindingRecordList -ResultList $resultList -RepositoryRoot $projectRoot

        $findingList[0].Severity | Should -Be 'Warning'
        $findingList[0].RuleName | Should -Be 'Rule.One'
        $findingList[0].RelativePath | Should -Be 'src/one.ps1'
        $findingList[0].Line | Should -Be 9
    }

    It 'formats an empty report section without a binding error' {
        $section = Get-ScriptAnalyzerReportSection `
            -Title 'Findings by severity' `
            -ItemList @() `
            -Formatter { param($item) $item }

        $section | Should -Be 'Findings by severity: none.'
    }

    It 'renders sorted severity rule file and detailed sections without changing report fields' {
        $results = @(
            Get-FakeScriptAnalyzerResult -PropertyOverrides @{ RelativePath = 'src/z.ps1'; RuleName = 'Rule.Z'; Line = 7 }
            Get-FakeScriptAnalyzerResult -PropertyOverrides @{ RelativePath = 'src/a.ps1'; RuleName = 'Rule.A'; Severity = 'Error'; Line = 2 }
        )
        $findings = @(ConvertTo-ScriptAnalyzerFindingRecordList -ResultList $results -RepositoryRoot $projectRoot)
        $report = Get-ScriptAnalyzerReportText -FindingList $findings -AnalyzedFileCount 2
        $report | Should -Match 'Analyzed files: 2'
        $report | Should -Match 'Total findings: 2'
        $report | Should -Match 'Findings by severity:\s+- Error: 1\s+- Warning: 1'
        $report | Should -Match 'Findings by rule:\s+- Rule.A: 1\s+- Rule.Z: 1'
        $report | Should -Match 'Findings by file:\s+- src/a.ps1: 1\s+- src/z.ps1: 1'
        $report | Should -Match 'Detailed findings:\s+- \[Error\] src/a.ps1:2 Rule.A - Test finding.\s+- \[Warning\] src/z.ps1:7 Rule.Z - Test finding.'
    }

    It 'does not reference the removed baseline mechanism' {
        $scriptText = Get-Content -LiteralPath $scriptPath -Raw

        $scriptText | Should -Not -Match 'PSScriptAnalyzerBaseline'
        $scriptText | Should -Not -Match 'UpdateBaseline'
    }
}

Describe 'Invoke-ScriptAnalyzerCI' {
    BeforeEach {
        Mock Import-ScriptAnalyzerModule { [version]'1.25.0' }
        Mock Confirm-ScriptAnalyzerVersion {}
        Mock Get-ScriptAnalyzerRepositoryRoot { $projectRoot }
        Mock Get-ScriptAnalyzerAnalysisPathList { @('src/one.ps1', 'tests/one.Tests.ps1') }
        Mock New-Item {}
        Mock Write-ScriptAnalyzerReport {}
    }

    It 'returns success when no findings exist' {
        Mock Get-ScriptAnalyzerResultList { @() }

        $result = Invoke-ScriptAnalyzerCI -OutputDirectory './artifacts'

        $result | Should -BeLike 'PSScriptAnalyzer: 0 findings*'
    }

    It 'fails when any finding exists for <Severity>' -ForEach @(
        @{ Severity = 'Error' }
        @{ Severity = 'Warning' }
        @{ Severity = 'Information' }
    ) {
        Mock Get-ScriptAnalyzerResultList { @(Get-ScriptAnalyzerSeverityFixture -Severity $Severity) }

        {
            Invoke-ScriptAnalyzerCI -OutputDirectory './artifacts'
        } | Should -Throw '*PSScriptAnalyzer reported 1 finding(s).*'
    }

    It 'fails when multiple findings exist' {
        Mock Get-ScriptAnalyzerResultList {
            @(
                Get-FakeScriptAnalyzerResult -PropertyOverrides @{ Severity = 'Warning'; RuleName = 'Rule.One' }
                Get-FakeScriptAnalyzerResult -PropertyOverrides @{
                    Severity = 'Information'
                    RuleName = 'Rule.Two'
                    Line     = 8
                }
            )
        }

        {
            Invoke-ScriptAnalyzerCI -OutputDirectory './artifacts'
        } | Should -Throw '*PSScriptAnalyzer reported 2 finding(s).*'
    }

    It 'fails when analyzer execution throws' {
        Mock Get-ScriptAnalyzerResultList { throw 'Analyzer execution failed.' }

        {
            Invoke-ScriptAnalyzerCI -OutputDirectory './artifacts'
        } | Should -Throw '*Analyzer execution failed.*'
    }

    It 'fails with a clear error when the analyzer module is missing' {
        Mock Import-ScriptAnalyzerModule { throw 'PSScriptAnalyzer 1.25.0 is required but could not be imported. Missing module.' }

        {
            Invoke-ScriptAnalyzerCI -OutputDirectory './artifacts'
        } | Should -Throw '*required but could not be imported*'
    }
}

Describe 'Invoke-ScriptAnalyzerCI script process behavior' {
    It 'returns exit code 0 when no findings exist' {
        $commandPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ps1')
        @(
            '& "{0}" -ProjectRoot "{1}" -OutputDirectory "{2}"' -f $scriptPath, $projectRoot, (Join-Path $TestDrive 'artifacts')
            'exit $LASTEXITCODE'
        ) | Set-Content -LiteralPath $commandPath

        $process = Invoke-PwshProcess -ArgumentList @('-NoLogo', '-NoProfile', '-File', $commandPath)
        $result = @($process.StandardOutput -split [Environment]::NewLine | Where-Object { $_ -ne '' })

        $process.ExitCode | Should -Be 0 -Because ($process.StandardOutput + $process.StandardError)
        @($result)[-1] | Should -BeLike 'PSScriptAnalyzer: 0 findings*'
        $process.StandardError | Should -BeNullOrEmpty
    }

    Describe 'Existing analyzer version pin in an owned root' {
        BeforeEach {
            $script:oldModuleRoot = $env:POWERSHELL_CI_MODULE_ROOT
            $script:oldAnalyzerVersion = $script:RequiredPSScriptAnalyzerVersion
            $script:analyzerOwner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-analyzer')
            $script:expectedAnalyzer = Initialize-ScriptAnalyzerVersionFixture -ModuleRoot $analyzerOwner.Path -Version 1.25.0
            $script:higherAnalyzer = Initialize-ScriptAnalyzerVersionFixture -ModuleRoot $analyzerOwner.Path -Version 1.26.0
            $script:availableAnalyzers = @(Get-Module -ListAvailable -Name @($expectedAnalyzer, $higherAnalyzer))
            $env:POWERSHELL_CI_MODULE_ROOT = $analyzerOwner.Path
            $script:RequiredPSScriptAnalyzerVersion = [version]'1.25.0'
            Mock Import-Module {}
            Mock Get-Module { $availableAnalyzers | Where-Object Path -EQ ([string]$Name) }
            Mock Get-Module { @{ Version = [version]'1.25.0'; Path = $expectedAnalyzer } } -ParameterFilter { $Name -eq 'PSScriptAnalyzer' -and -not $ListAvailable }
        }

        AfterEach {
            $env:POWERSHELL_CI_MODULE_ROOT = $oldModuleRoot
            $script:RequiredPSScriptAnalyzerVersion = $oldAnalyzerVersion
        }

        It 'imports owned 1.25.0 even when owned 1.26.0 is available' {
            Import-ScriptAnalyzerModule | Should -Be ([version]'1.25.0')
            Should -Invoke Import-Module -Exactly -Times 1 -ParameterFilter {
                $Name -eq $expectedAnalyzer -and $RequiredVersion -eq '1.25.0'
            }
        }
    }

    It 'returns exit code 1 when findings exist' {
        $finding = @{ Severity = 'Information'; RuleName = 'Rule.Info'; RelativePath = 'src/Sample.ps1'; Line = 1; Message = 'Info finding.' }
        $harness = Get-ScriptAnalyzerHarness -Findings @([pscustomobject]$finding)
        $commandPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ps1')
        Write-ScriptAnalyzerFixtureCommand -Path $commandPath -Harness $harness

        $process = Invoke-PwshProcess -ArgumentList @('-NoLogo', '-NoProfile', '-File', $commandPath)

        $process.ExitCode | Should -Be 1
        $process.StandardError | Should -Match 'PSScriptAnalyzer reported'
        Get-Content (Join-Path $harness.RepositoryRoot 'artifacts/scriptanalyzer.txt') -Raw | Should -Match 'Rule.Info'
    }

    It 'returns exit code 1 when the analyzer dependency is missing' {
        $repoRoot = Join-Path $TestDrive 'missing-module-repo'
        $null = New-Item -ItemType Directory -Path (Join-Path $repoRoot 'src') -Force
        Set-Content -LiteralPath (Join-Path $repoRoot 'src/Sample.ps1') -Value "function Get-Sample { 'ok' }"
        $emptyModuleRoot = Join-Path $TestDrive 'empty-modules'
        $null = New-Item -ItemType Directory -Path $emptyModuleRoot -Force
        $commandPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ps1')
        $harness = @{ ModuleRoot = $emptyModuleRoot; RepositoryRoot = $repoRoot; ScriptPath = $scriptPath }
        Write-ScriptAnalyzerFixtureCommand -Path $commandPath -Harness $harness

        $process = Invoke-PwshProcess -ArgumentList @('-NoLogo', '-NoProfile', '-File', $commandPath)
        $output = $process.StandardError

        $process.ExitCode | Should -Be 1
        $output | Should -Match 'required but could not be imported'
    }
}
