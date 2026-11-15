param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$OutputDirectory = './artifacts',
    [string[]]$ExcludeTag = @(),
    [switch]$SkipBuildValidation,
    [string]$PesterRequiredVersion = ''
)

Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'CiRuntimeEvidence.ps1')
. (Join-Path $PSScriptRoot '../install-ps-modules/CiDependencyRoot.ps1')
Initialize-CiDependencyEnvironment

function Get-CiNUnitArtifactPath {
    param(
        [Parameter(Mandatory)][string]$ArtifactsDirectory,
        [Parameter(Mandatory)][string]$ProjectName
    )

    return (Join-Path $ArtifactsDirectory "$($ProjectName.ToLowerInvariant())-nunit.xml")
}

function Copy-CiArtifactIfPresent {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    Initialize-CiArtifactDirectory -DestinationPath $DestinationPath
    if ($resolvedSourcePath -eq [System.IO.Path]::GetFullPath($DestinationPath)) {
        return
    }

    Copy-Item -LiteralPath $resolvedSourcePath -Destination ([System.IO.Path]::GetFullPath($DestinationPath)) -Force
}

function Initialize-CiArtifactDirectory {
    param([string]$DestinationPath)
    $directory = Split-Path -Parent $DestinationPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Copy-CiArtifactsIfPresent {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ArtifactsDirectory,
        [Parameter(Mandatory)][string]$ProjectName,
        [switch]$SkipCoverage
    )

    $sourceArtifactsDirectory = Join-Path $ProjectRoot 'artifacts'
    Copy-CiArtifactIfPresent `
        -SourcePath (Join-Path $sourceArtifactsDirectory 'TestResults.xml') `
        -DestinationPath (Get-CiNUnitArtifactPath -ArtifactsDirectory $ArtifactsDirectory -ProjectName $ProjectName)
    if (-not $SkipCoverage) {
        Copy-CiUnitCoverage -ProjectRoot $ProjectRoot -ArtifactsDirectory $ArtifactsDirectory
    }
}

function Copy-CiUnitCoverage {
    param([string]$ProjectRoot, [string]$ArtifactsDirectory)
    $source = Join-Path $ProjectRoot 'artifacts/coverage.xml'
    Copy-CiArtifactIfPresent -SourcePath $source -DestinationPath (Join-Path $ArtifactsDirectory 'coverage.xml')
}

$repoRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
Set-Location $repoRoot
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Import-CiPester -RequiredVersion $PesterRequiredVersion
Import-Module NovaModuleTools -ErrorAction Stop

Invoke-NovaBuild

$projectInfo = Get-NovaProjectInfo
$builtModulePath = $projectInfo.OutputModuleDir
Remove-Module $projectInfo.ProjectName -ErrorAction SilentlyContinue
Import-Module $builtModulePath -Force
$projectInfo = Get-NovaProjectInfo
if ($PesterRequiredVersion) {
    Assert-CiPesterVersion -RequiredVersion $PesterRequiredVersion
    if ($env:POWERSHELL_CI_MODULE_ROOT) {
        Assert-CiDependencyOrigin -ModuleRoot $env:POWERSHELL_CI_MODULE_ROOT
    }
    Write-CiRuntimeEvidence -OutputDirectory $OutputDirectory
}

function Get-CiTestTagArgument {
    param([string[]]$ExcludeTag)
    $tagArguments = @{}
    if (@($ExcludeTag).Count -gt 0) {
        $tagArguments.ExcludeTagFilter = $ExcludeTag
    }

    return $tagArguments
}

function Invoke-CiTestPhase {
    param([hashtable]$TagArguments, [switch]$SkipBuildValidation, [object]$ProjectInfo, [string]$OutputDirectory)
    $unitCompleted = $false
    $coverage = $null
    try {
        Invoke-NovaTest @TagArguments
        $coverage = Get-CiUnitCoverageSnapshot -ProjectRoot $ProjectInfo.ProjectRoot
        $unitCompleted = $true
        Invoke-CiBuildValidation -TagArguments $TagArguments -SkipBuildValidation:$SkipBuildValidation
    } finally {
        Copy-CiArtifactsIfPresent -ProjectRoot $ProjectInfo.ProjectRoot -ArtifactsDirectory $OutputDirectory -ProjectName $ProjectInfo.ProjectName -SkipCoverage:$unitCompleted
        Write-CiUnitCoverageSnapshot -Snapshot $coverage -ArtifactsDirectory $OutputDirectory
    }
}

function Get-CiUnitCoverageSnapshot {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'artifacts/coverage.xml'
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    return [pscustomobject]@{ Bytes = [IO.File]::ReadAllBytes($path) }
}

function Write-CiUnitCoverageSnapshot {
    param([object]$Snapshot, [string]$ArtifactsDirectory)
    if ($null -eq $Snapshot) {
        return
    }
    $path = [IO.Path]::GetFullPath((Join-Path $ArtifactsDirectory 'coverage.xml'))
    Initialize-CiArtifactDirectory -DestinationPath $path
    [IO.File]::WriteAllBytes($path, $Snapshot.Bytes)
}

function Invoke-CiBuildValidation {
    param([hashtable]$TagArguments, [switch]$SkipBuildValidation)
    if (-not $SkipBuildValidation) {
        Test-NovaBuild @TagArguments
    }
}

$testFailed = $false
try {
    $tagArguments = Get-CiTestTagArgument -ExcludeTag $ExcludeTag
    Invoke-CiTestPhase -TagArguments $tagArguments -SkipBuildValidation:$SkipBuildValidation -ProjectInfo $projectInfo -OutputDirectory $OutputDirectory
} catch {
    $testFailed = $true
    Write-Warning "Nova tests failed: $( $_.Exception.Message )"
}

if ($testFailed) {
    exit 1
}
