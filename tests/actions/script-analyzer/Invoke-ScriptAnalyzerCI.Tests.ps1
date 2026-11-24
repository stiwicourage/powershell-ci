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

    Describe 'Severity filter' {
        BeforeEach {
            $script:oldSeverity = $script:ScriptAnalyzerSeverity
            Mock Invoke-ScriptAnalyzer { @() }
        }

        AfterEach {
            $script:ScriptAnalyzerSeverity = $oldSeverity
        }

        It 'forwards configured severities to the analyzer' {
            $script:ScriptAnalyzerSeverity = @('Error', 'Warning')

            Invoke-ScriptAnalyzerWithTransientRetry -Path 'sample.ps1' | Should -BeNullOrEmpty

            Should -Invoke Invoke-ScriptAnalyzer -Exactly -Times 1 -ParameterFilter {
                ($Severity -join ',') -eq 'Error,Warning'
            }
        }

        It 'analyzes every severity when no severity is configured' {
            $script:ScriptAnalyzerSeverity = @()

            Invoke-ScriptAnalyzerWithTransientRetry -Path 'sample.ps1' | Should -BeNullOrEmpty

            Should -Invoke Invoke-ScriptAnalyzer -Exactly -Times 1 -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('Severity')
            }
        }
    }

    It 'drops real analyzer findings outside the configured severities' {
        $oldSeverity = $script:ScriptAnalyzerSeverity
        $path = Join-Path $TestDrive 'WarningOnly.ps1'
        Set-Content -LiteralPath $path -Value 'function Bad-AnalyzerFixture { }'
        try {
            $script:ScriptAnalyzerSeverity = @('Error')
            @(Invoke-ScriptAnalyzerWithTransientRetry -Path $path) | Should -BeNullOrEmpty
        } finally {
            $script:ScriptAnalyzerSeverity = $oldSeverity
        }
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

    It 'returns exit code 0 when findings fall outside the requested severities' {
        $finding = @{ Severity = 'Information'; RuleName = 'Rule.Info'; RelativePath = 'src/Sample.ps1'; Line = 1; Message = 'Info finding.' }
        $harness = Get-ScriptAnalyzerHarness -Findings @([pscustomobject]$finding)
        $commandPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ps1')
        Write-ScriptAnalyzerFixtureCommand -Path $commandPath -Harness $harness -ExtraArgument '-Severity Error, Warning'

        $process = Invoke-PwshProcess -ArgumentList @('-NoLogo', '-NoProfile', '-File', $commandPath)

        $process.ExitCode | Should -Be 0 -Because ($process.StandardOutput + $process.StandardError)
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

Describe 'Invoke-ScriptAnalyzerCI in-process contracts' {
    BeforeEach {
        $script:savedRoot = $env:POWERSHELL_CI_MODULE_ROOT
        $script:savedVersion = $script:RequiredPSScriptAnalyzerVersion
        $script:savedLocation = (Get-Location).Path
        $env:POWERSHELL_CI_MODULE_ROOT = $null
    }

    AfterEach {
        $env:POWERSHELL_CI_MODULE_ROOT = $savedRoot
        $script:RequiredPSScriptAnalyzerVersion = $savedVersion
        Set-Location -LiteralPath $savedLocation
    }

    Describe 'Analyzer module import' {
        It 'imports PSScriptAnalyzer by name when no isolated root is active' {
            Mock Import-Module {}
            Mock Get-Module { [pscustomobject]@{ Version = [version]'1.25.0' } } -ParameterFilter { $Name -eq 'PSScriptAnalyzer' }
            Import-ScriptAnalyzerModule | Should -Be ([version]'1.25.0')
            Should -Invoke Import-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'PSScriptAnalyzer' }
        }

        It 'wraps an import failure with the missing-analyzer message' {
            Mock Import-CiAnalyzerDependency { throw 'no such module' }
            { Import-ScriptAnalyzerModule } | Should -Throw '*could not be imported. no such module*'
        }

        It 'fails when the import succeeded but the module is not loaded' {
            Mock Import-CiAnalyzerDependency {}
            Mock Get-Module { $null }
            { Import-ScriptAnalyzerModule } | Should -Throw '*did not load the module*'
        }
    }

    Describe 'Analyzer version pin' {
        It 'accepts any version when none is pinned' {
            $script:RequiredPSScriptAnalyzerVersion = $null
            { Confirm-ScriptAnalyzerVersion -AnalyzerVersion ([version]'9.9.9') } | Should -Not -Throw
        }

        It 'accepts the pinned version' {
            $script:RequiredPSScriptAnalyzerVersion = [version]'1.25.0'
            { Confirm-ScriptAnalyzerVersion -AnalyzerVersion ([version]'1.25.0') } | Should -Not -Throw
        }

        It 'rejects a different version than the pin' {
            $script:RequiredPSScriptAnalyzerVersion = [version]'1.25.0'
            { Confirm-ScriptAnalyzerVersion -AnalyzerVersion ([version]'1.26.0') } | Should -Throw '*1.26.0 is installed, but version 1.25.0 is required*'
        }
    }

    Describe 'Input discovery and results' {
        It 'returns the full path of a single file input' {
            $file = Join-Path $TestDrive 'Single.ps1'
            Set-Content -LiteralPath $file -Value 'Get-Date'
            @(Get-ScriptAnalyzerInputPathList -Path $file -RepositoryRoot $TestDrive) | Should -Be @([IO.Path]::GetFullPath($file))
        }

        It 'returns no input for a missing path' {
            @(Get-ScriptAnalyzerInputPathList -Path (Join-Path $TestDrive 'absent') -RepositoryRoot $TestDrive) | Should -BeNullOrEmpty
        }

        It 'analyzes every path and concatenates the results' {
            Mock Invoke-ScriptAnalyzerWithTransientRetry { @("finding for $Path") }
            @(Get-ScriptAnalyzerResultList -AnalysisPathList @('a.ps1', 'b.ps1')) | Should -Be @('finding for a.ps1', 'finding for b.ps1')
        }

        It 'reports the repository root chosen at startup' {
            Get-ScriptAnalyzerRepositoryRoot | Should -BeExactly $script:ScriptAnalyzerProjectRoot
        }

        It 'refuses to continue when no files were found' {
            { Assert-ScriptAnalyzerInput -PathList @() -RepositoryRoot '/repo' } | Should -Throw "*No PowerShell files were found to analyze under '/repo'*"
        }
    }

    Describe 'Report output' {
        It 'writes the report text to the requested path' {
            $path = Join-Path $TestDrive 'report.txt'
            Write-ScriptAnalyzerReport -Path $path -FindingList @() -AnalyzedFileCount 3
            (Get-Content -LiteralPath $path -Raw) | Should -Match 'Analyzed files: 3'
        }

        It 'resolves a relative report directory against the repository root' {
            $path = Write-CiAnalyzerReport -Directory 'out/reports' -Root $TestDrive -Findings @() -Count 1
            $path | Should -BeExactly (Join-Path $TestDrive 'out/reports/scriptanalyzer.txt')
            Test-Path -LiteralPath $path | Should -BeTrue
        }
    }

    Describe 'Script entry point' {
        BeforeEach {
            $script:repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path "$repo/src" -Force
            Set-Content -LiteralPath "$repo/src/Sample.ps1" -Value "function Get-Sample { 'ok' }"
            Mock Import-Module {}
            Mock Get-Module { [pscustomobject]@{ Version = [version]'1.25.0' } } -ParameterFilter { $Name -eq 'PSScriptAnalyzer' }
            Mock Invoke-ScriptAnalyzer { @() }
        }

        It 'uses the working directory and default analysis paths and reports success' {
            Set-Location -LiteralPath $repo
            $output = @(& $scriptPath -OutputDirectory (Join-Path $TestDrive 'default-out') -RequiredVersion 1.25.0)
            $output[-1] | Should -BeLike 'PSScriptAnalyzer: 0 findings across 1 file(s) with PSScriptAnalyzer 1.25.0.'
            $LASTEXITCODE | Should -Be 0
            Should -Invoke Invoke-ScriptAnalyzer -Exactly -Times 1 -ParameterFilter { ($ExcludeRule -join ',') -eq 'PSAvoidUsingWriteHost' }
        }

        It 'raises the finding failure instead of reporting success' {
            Mock Invoke-ScriptAnalyzer { Get-FakeScriptAnalyzerResult -PropertyOverrides @{ RelativePath = 'src/Sample.ps1' } }
            $out = Join-Path $TestDrive 'failure-out'
            { & $scriptPath -ProjectRoot $repo -OutputDirectory $out -ErrorAction Stop } | Should -Throw '*reported 1 finding(s)*'
            Test-Path -LiteralPath (Join-Path $out 'scriptanalyzer.txt') | Should -BeTrue
        }
    }
}
