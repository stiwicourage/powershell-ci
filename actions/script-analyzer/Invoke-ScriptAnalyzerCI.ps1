param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$OutputDirectory = './artifacts',
    [string[]]$AnalysisPath = @('src', 'scripts', 'tests', 'run.ps1'),
    [string]$RequiredVersion = '',
    [string[]]$ExcludeRule = @('PSAvoidUsingWriteHost'),
    [string[]]$Severity = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../install-ps-modules/CiDependencyRoot.ps1')
Initialize-CiDependencyEnvironment

$script:ScriptAnalyzerProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$script:ScriptAnalyzerPathList = $AnalysisPath
$script:RequiredPSScriptAnalyzerVersion = if ($RequiredVersion) { [version]$RequiredVersion } else { $null }
$script:ScriptAnalyzerExcludedRules = $ExcludeRule
$script:ScriptAnalyzerSeverity = $Severity

function Get-ScriptAnalyzerRepositoryRoot {
    [OutputType([string])]
    [CmdletBinding()]
    param()

    return $script:ScriptAnalyzerProjectRoot
}

function Test-IsGeneratedAnalysisPath {
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $relativePath = [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($RepositoryRoot),
        [System.IO.Path]::GetFullPath($Path)
    ).Replace('\', '/')

    return $relativePath -match '(^|.*/)(dist|artifacts)(/|$)'
}

function Get-ScriptAnalyzerInputPathList {
    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [string[]]@()
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [string[]]@([System.IO.Path]::GetFullPath($Path))
    }

    return [string[]]@(Get-ScriptAnalyzerDirectoryInput -Path $Path -RepositoryRoot $RepositoryRoot)
}

function Get-ScriptAnalyzerDirectoryInput {
    param([string]$Path, [string]$RepositoryRoot)
    return @(
        Get-ChildItem -LiteralPath $Path -Recurse -File |
            Where-Object Extension -In @('.ps1', '.psm1', '.psd1') |
            Where-Object { -not (Test-IsGeneratedAnalysisPath -Path $_.FullName -RepositoryRoot $RepositoryRoot) } |
            ForEach-Object FullName
    )
}

function Get-ScriptAnalyzerAnalysisPathList {
    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    return [string[]]@(
        foreach ($analysisPath in $script:ScriptAnalyzerPathList) {
            Get-ScriptAnalyzerInputPathList `
                -Path (Join-Path $RepositoryRoot $analysisPath) `
                -RepositoryRoot $RepositoryRoot
        }
    )
}

function Import-ScriptAnalyzerModule {
    [OutputType([version])]
    [CmdletBinding()]
    param()

    try {
        Import-CiAnalyzerDependency
    } catch {
        throw "PSScriptAnalyzer is required but could not be imported. $($_.Exception.Message)"
    }

    $analyzerModule = Get-Module PSScriptAnalyzer
    if ($null -eq $analyzerModule) {
        throw 'PSScriptAnalyzer is required but Import-Module did not load the module.'
    }

    return [version]$analyzerModule.Version
}

function Import-CiAnalyzerDependency {
    if (-not $env:POWERSHELL_CI_MODULE_ROOT) {
        Import-Module PSScriptAnalyzer -ErrorAction Stop
        return
    }
    . (Join-Path $PSScriptRoot '../install-ps-modules/CiDependencyProbe.ps1') -ModuleRoot $env:POWERSHELL_CI_MODULE_ROOT
    $requirement = @{ Name = 'PSScriptAnalyzer'; RequiredVersion = [string]$script:RequiredPSScriptAnalyzerVersion }
    $path = Resolve-CiSavedModule -ModuleRoot $env:POWERSHELL_CI_MODULE_ROOT -Requirement $requirement
    $parameters = @{ Name = $path; ErrorAction = 'Stop' }
    Copy-CiProviderVersionConstraint -Requirement $requirement -Parameters $parameters
    Import-Module @parameters
}

function Confirm-ScriptAnalyzerVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][version]$AnalyzerVersion
    )

    if ($null -eq $script:RequiredPSScriptAnalyzerVersion -or $AnalyzerVersion -eq $script:RequiredPSScriptAnalyzerVersion) {
        return
    }

    throw "PSScriptAnalyzer version $AnalyzerVersion is installed, but version $script:RequiredPSScriptAnalyzerVersion is required."
}

function Get-ScriptAnalyzerResultList {
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$AnalysisPathList
    )

    return [object[]]@(
        foreach ($analysisPath in $AnalysisPathList) {
            Invoke-ScriptAnalyzerWithTransientRetry -Path $analysisPath
        }
    )
}

function Invoke-ScriptAnalyzerWithTransientRetry {
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parameters = Get-ScriptAnalyzerInvocationParameter -Path $Path
    try {
        return @(Invoke-ScriptAnalyzer @parameters)
    } catch [System.NullReferenceException] {
        return @(Invoke-ScriptAnalyzer @parameters)
    }
}

function Get-ScriptAnalyzerInvocationParameter {
    param([string]$Path)
    $parameters = @{ Path = $Path; ExcludeRule = $script:ScriptAnalyzerExcludedRules }
    if (@($script:ScriptAnalyzerSeverity).Count -gt 0) {
        $parameters.Severity = $script:ScriptAnalyzerSeverity
    }
    return $parameters
}

function ConvertTo-ScriptAnalyzerFindingRecordList {
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [Parameter(Mandatory)][object[]]$ResultList,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    return [object[]]@(
        foreach ($result in @($ResultList)) {
            ConvertTo-ScriptAnalyzerFindingRecord -Result $result -RepositoryRoot $RepositoryRoot
        }
    )
}

function ConvertTo-ScriptAnalyzerFindingRecord {
    param([object]$Result, [string]$RepositoryRoot)
    return [pscustomobject][ordered]@{
        Severity     = [string]$Result.Severity
        RuleName     = [string]$Result.RuleName
        RelativePath = [System.IO.Path]::GetRelativePath($RepositoryRoot, $Result.ScriptPath).Replace('\', '/')
        Line         = [int]$Result.Line
        Message      = [string]$Result.Message
    }
}

function Get-ScriptAnalyzerReportSection {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [AllowEmptyCollection()]
        [Parameter(Mandatory)][object[]]$ItemList,
        [Parameter(Mandatory)][scriptblock]$Formatter
    )

    if ($ItemList.Count -eq 0) {
        return "$Title`: none."
    }

    $lineList = Get-ScriptAnalyzerReportLine -ItemList $ItemList -Formatter $Formatter

    return "$Title`:$([Environment]::NewLine)$($lineList -join [Environment]::NewLine)"
}

function Get-ScriptAnalyzerReportLine {
    param([object[]]$ItemList, [scriptblock]$Formatter)
    foreach ($item in $ItemList) {
        & $Formatter $item
    }
}

function Get-ScriptAnalyzerReportText {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)][object[]]$FindingList,
        [Parameter(Mandatory)][int]$AnalyzedFileCount
    )

    return @(
        "Analyzed files: $AnalyzedFileCount"
        "Total findings: $($FindingList.Count)"
        Get-ScriptAnalyzerSummarySection -FindingList $FindingList
        Get-ScriptAnalyzerDetailSection -FindingList $FindingList
    ) -join ([Environment]::NewLine * 2)
}

function Get-ScriptAnalyzerSummarySection {
    param([object[]]$FindingList)
    foreach ($entry in @(@('Severity', 'severity'), @('RuleName', 'rule'), @('RelativePath', 'file'))) {
        $summary = @(Get-ScriptAnalyzerSummary -FindingList $FindingList -Property $entry[0])
        Get-ScriptAnalyzerReportSection -Title "Findings by $($entry[1])" -ItemList $summary `
            -Formatter { param($item) '- {0}: {1}' -f $item.Name, $item.Count }
    }
}

function Get-ScriptAnalyzerSummary {
    param([object[]]$FindingList, [string]$Property)
    $groups = @($FindingList | Group-Object $Property)
    if ($Property -eq 'Severity') {
        return $groups | Sort-Object Name
    }
    return $groups | Sort-Object @{ Expression = { $_.Count }; Descending = $true }, Name
}

function Get-ScriptAnalyzerDetailSection {
    param([object[]]$FindingList)
    $details = @($FindingList | Sort-Object RelativePath, Line, RuleName)
    Get-ScriptAnalyzerReportSection -Title 'Detailed findings' -ItemList $details -Formatter {
        param($item)
        '- [{0}] {1}:{2} {3} - {4}' -f $item.Severity, $item.RelativePath, $item.Line, $item.RuleName, $item.Message
    }
}

function Write-ScriptAnalyzerReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()]
        [AllowEmptyCollection()]
        [Parameter(Mandatory)][object[]]$FindingList,
        [Parameter(Mandatory)][int]$AnalyzedFileCount
    )

    $reportText = Get-ScriptAnalyzerReportText -FindingList $FindingList -AnalyzedFileCount $AnalyzedFileCount
    $reportText | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-ScriptAnalyzerCI {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputDirectory
    )

    $repositoryRoot = Get-ScriptAnalyzerRepositoryRoot
    $analyzerVersion = Get-ConfirmedScriptAnalyzerVersion
    $analysisPathList = Get-ScriptAnalyzerAnalysisPathList -RepositoryRoot $repositoryRoot
    Assert-ScriptAnalyzerInput -PathList $analysisPathList -RepositoryRoot $repositoryRoot
    $findingList = @(Get-CiAnalyzerFinding -PathList $analysisPathList -RepositoryRoot $repositoryRoot)
    $reportPath = Write-CiAnalyzerReport -Directory $OutputDirectory -Root $repositoryRoot -Findings $findingList -Count $analysisPathList.Count
    Assert-ScriptAnalyzerFinding -FindingList $findingList -ReportPath $reportPath
    return "PSScriptAnalyzer: 0 findings across $($analysisPathList.Count) file(s) with PSScriptAnalyzer $analyzerVersion."
}

function Get-ConfirmedScriptAnalyzerVersion {
    $version = Import-ScriptAnalyzerModule
    Confirm-ScriptAnalyzerVersion -AnalyzerVersion $version
    return $version
}

function Assert-ScriptAnalyzerInput {
    param([AllowEmptyCollection()][string[]]$PathList, [string]$RepositoryRoot)
    if ($PathList.Count -eq 0) {
        throw "No PowerShell files were found to analyze under '$RepositoryRoot'."
    }
}

function Get-CiAnalyzerFinding {
    param([string[]]$PathList, [string]$RepositoryRoot)
    $results = @(Get-ScriptAnalyzerResultList -AnalysisPathList $PathList)
    return ConvertTo-ScriptAnalyzerFindingRecordList -ResultList $results -RepositoryRoot $RepositoryRoot
}

function Write-CiAnalyzerReport {
    param([string]$Directory, [string]$Root, [object[]]$Findings, [int]$Count)
    $resolved = if ([System.IO.Path]::IsPathRooted($Directory)) { $Directory } else { Join-Path $Root $Directory }
    $null = New-Item -ItemType Directory -Path $resolved -Force
    $path = Join-Path $resolved 'scriptanalyzer.txt'
    Write-ScriptAnalyzerReport -Path $path -FindingList $Findings -AnalyzedFileCount $Count
    return $path
}

function Assert-ScriptAnalyzerFinding {
    param([object[]]$FindingList, [string]$ReportPath)
    if ($FindingList.Count -gt 0) {
        throw "PSScriptAnalyzer reported $($FindingList.Count) finding(s). See '$ReportPath' for details."
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $message = Invoke-ScriptAnalyzerCI -OutputDirectory $OutputDirectory
        Write-Output $message
        exit 0
    } catch {
        Write-Error -ErrorRecord $_
        exit 1
    }
}
