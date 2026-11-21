<#
.SYNOPSIS
Creates a fake ScriptAnalyzer result for wrapper tests.
#>
function Get-FakeScriptAnalyzerResult {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param(
        [hashtable]$PropertyOverrides = @{}
    )

    $propertyMap = Get-FakeScriptAnalyzerPropertyMap -Overrides $PropertyOverrides
    return [pscustomobject]@{
        Severity   = $propertyMap.Severity
        RuleName   = $propertyMap.RuleName
        ScriptPath = Join-Path $env:SCRIPTANALYZER_TEST_PROJECT_ROOT $propertyMap.RelativePath
        Line       = $propertyMap.Line
        Message    = $propertyMap.Message
    }
}

function Get-FakeScriptAnalyzerPropertyMap {
    param([hashtable]$Overrides)
    $properties = @{
        Severity = 'Warning'
        RuleName = 'Rule.Default'
        RelativePath = 'src/test.ps1'
        Line = 3
        Message = 'Test finding.'
    }
    foreach ($name in $Overrides.Keys) {
        $properties[$name] = $Overrides[$name]
    }
    return $properties
}

<#
.SYNOPSIS
Builds a temporary repository and fake PSScriptAnalyzer module for wrapper tests.
#>
function Get-ScriptAnalyzerHarness {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param(
        [object[]]$Findings = @(),
        [switch]$ThrowOnAnalyze
    )

    $harness = Initialize-ScriptAnalyzerHarnessDirectory -ModuleRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
    $moduleDirectory = Join-Path $harness.ModuleRoot 'PSScriptAnalyzer/1.25.0'
    Write-FakeScriptAnalyzerModule -Path $moduleDirectory -Findings $Findings -ThrowOnAnalyze:$ThrowOnAnalyze
    return $harness
}

function Initialize-ScriptAnalyzerHarnessDirectory {
    param([string]$ModuleRoot)
    $repoRoot = Join-Path $ModuleRoot 'repo'
    $directories = @('repo/src', 'repo/tests', 'PSScriptAnalyzer/1.25.0')
    foreach ($directory in $directories) {
        $null = New-Item -ItemType Directory -Path (Join-Path $ModuleRoot $directory) -Force
    }
    Set-Content -LiteralPath (Join-Path $repoRoot 'src/Sample.ps1') -Value "function Get-Sample { 'ok' }"
    Set-Content -LiteralPath (Join-Path $repoRoot 'tests/Sample.Tests.ps1') -Value 'Describe "Sample" { It "works" { $true | Should -BeTrue } }'
    return [pscustomobject]@{
        ModuleRoot = $ModuleRoot
        RepositoryRoot = $repoRoot
        ScriptPath = $env:SCRIPTANALYZER_TEST_SCRIPT_PATH
    }
}

function Write-FakeScriptAnalyzerModule {
    param([string]$Path, [object[]]$Findings, [switch]$ThrowOnAnalyze)
    $fixture = @{ Findings = @($Findings); ThrowOnAnalyze = [bool]$ThrowOnAnalyze }
    $fixture | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Path 'fixture.json')
    Copy-Item (Join-Path $PSScriptRoot 'FakeScriptAnalyzer.psm1') (Join-Path $Path 'PSScriptAnalyzer.psm1')
    "@{ RootModule = 'PSScriptAnalyzer.psm1'; ModuleVersion = '1.25.0'; GUID = '11111111-1111-1111-1111-111111111111' }" |
        Set-Content -LiteralPath (Join-Path $Path 'PSScriptAnalyzer.psd1')
}

<#
.SYNOPSIS
Runs pwsh as a child process and captures its exit code and output.
#>
function Invoke-PwshProcess {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param(
        [string[]]$ArgumentList
    )

    $startInfo = Get-PwshProcessStartInfo -ArgumentList $ArgumentList
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()

    return Get-PwshProcessResult -Process $process
}

function Get-PwshProcessStartInfo {
    param([string[]]$ArgumentList)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'pwsh'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
        $null = $startInfo.ArgumentList.Add($argument)
    }
    return $startInfo
}

function Get-PwshProcessResult {
    param([System.Diagnostics.Process]$Process)
    $standardOutput = $Process.StandardOutput.ReadToEnd()
    $standardError = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()
    return [pscustomobject]@{
        ExitCode       = $Process.ExitCode
        StandardOutput = $standardOutput
        StandardError  = $standardError
    }
}

<#
.SYNOPSIS
Creates source and generated-file fixtures for path-selection assertions.
#>
function Initialize-ScriptAnalyzerPathFixture {
    param([string]$Path)
    foreach ($directory in @('src', 'tests', 'scripts', 'artifacts', 'dist')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $Path $directory) -Force
    }
    Set-Content (Join-Path $Path 'src/One.ps1') 'function Get-One { }'
    Set-Content (Join-Path $Path 'tests/One.Tests.ps1') 'Describe "One" { }'
    Set-Content (Join-Path $Path 'artifacts/Generated.ps1') 'function Get-Generated { }'
    Set-Content (Join-Path $Path 'dist/Generated.ps1') 'function Get-DistGenerated { }'
}

<#
.SYNOPSIS
Creates a complete finding for severity-policy assertions.
#>
function Get-ScriptAnalyzerSeverityFixture {
    param([string]$Severity)
    return Get-FakeScriptAnalyzerResult -PropertyOverrides @{
        Severity = $Severity
        RuleName = "Rule.$Severity"
        RelativePath = 'src/test.ps1'
        Line = 4
        Message = "$Severity finding."
    }
}

<#
.SYNOPSIS
Writes the isolated analyzer child-process command used by process tests.
#>
function Write-ScriptAnalyzerFixtureCommand {
    param([string]$Path, [object]$Harness, [string]$ExtraArgument = '')
    @(
        '$env:PSModulePath = "{0}"' -f $Harness.ModuleRoot
        '$env:SCRIPTANALYZER_FAKE_REPOSITORY_ROOT = "{0}"' -f $Harness.RepositoryRoot
        '& "{0}" -ProjectRoot "{1}" -OutputDirectory "./artifacts" {2}' -f $Harness.ScriptPath, $Harness.RepositoryRoot, $ExtraArgument
        'exit $LASTEXITCODE'
    ) | Set-Content -LiteralPath $Path
}

<#
.SYNOPSIS
Creates an analyzer module-version fixture for exact owned-path selection.
#>
function Initialize-ScriptAnalyzerVersionFixture {
    param([string]$ModuleRoot, [string]$Version)
    $directory = Join-Path $ModuleRoot "PSScriptAnalyzer/$Version"
    $null = New-Item -ItemType Directory -Path $directory -Force
    '' | Set-Content (Join-Path $directory 'PSScriptAnalyzer.psm1')
    "@{ RootModule = 'PSScriptAnalyzer.psm1'; ModuleVersion = '$Version' }" |
        Set-Content (Join-Path $directory 'PSScriptAnalyzer.psd1')
    return Join-Path $directory 'PSScriptAnalyzer.psd1'
}

Export-ModuleMember -Function Get-FakeScriptAnalyzerResult, Get-ScriptAnalyzerHarness, Invoke-PwshProcess,
    Initialize-ScriptAnalyzerPathFixture, Get-ScriptAnalyzerSeverityFixture, Write-ScriptAnalyzerFixtureCommand,
    Initialize-ScriptAnalyzerVersionFixture
