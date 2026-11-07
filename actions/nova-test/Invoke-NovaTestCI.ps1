param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$OutputDirectory = './artifacts',
    [string[]]$ExcludeTag = @(),
    [switch]$SkipBuildValidation
)

Set-StrictMode -Version Latest

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
    $destinationDirectory = Split-Path -Parent $DestinationPath
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    $resolvedDestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
    if ($resolvedSourcePath -eq $resolvedDestinationPath) {
        return
    }

    Copy-Item -LiteralPath $resolvedSourcePath -Destination $resolvedDestinationPath -Force
}

function Copy-CiArtifactsIfPresent {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ArtifactsDirectory,
        [Parameter(Mandatory)][string]$ProjectName
    )

    $sourceArtifactsDirectory = Join-Path $ProjectRoot 'artifacts'
    Copy-CiArtifactIfPresent `
        -SourcePath (Join-Path $sourceArtifactsDirectory 'TestResults.xml') `
        -DestinationPath (Get-CiNUnitArtifactPath -ArtifactsDirectory $ArtifactsDirectory -ProjectName $ProjectName)
    Copy-CiArtifactIfPresent `
        -SourcePath (Join-Path $sourceArtifactsDirectory 'coverage.xml') `
        -DestinationPath (Join-Path $ArtifactsDirectory 'coverage.xml')
}

$repoRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
Set-Location $repoRoot
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Import-Module NovaModuleTools -ErrorAction Stop

Invoke-NovaBuild

$projectInfo = Get-NovaProjectInfo
$builtModulePath = $projectInfo.OutputModuleDir
Remove-Module $projectInfo.ProjectName -ErrorAction SilentlyContinue
Import-Module $builtModulePath -Force
$projectInfo = Get-NovaProjectInfo

$testFailed = $false
try {
    $tagArguments = @{}
    if (@($ExcludeTag).Count -gt 0) {
        $tagArguments.ExcludeTagFilter = $ExcludeTag
    }

    Invoke-NovaTest @tagArguments
    if (-not $SkipBuildValidation) {
        Test-NovaBuild @tagArguments
    }
}
catch {
    $testFailed = $true
    Write-Warning "Nova tests failed: $( $_.Exception.Message )"
}
finally {
    Copy-CiArtifactsIfPresent -ProjectRoot $projectInfo.ProjectRoot -ArtifactsDirectory $OutputDirectory -ProjectName $projectInfo.ProjectName
}

if ($testFailed) {
    exit 1
}
