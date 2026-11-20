param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ProjectName,
    [Parameter(Mandatory)][string]$BuiltModulePath,
    [Parameter(Mandatory)][ValidateSet('Invoke-NovaTest', 'Test-NovaBuild')][string]$CommandName,
    [string]$ExcludeTagList = '',
    [string]$PesterRequiredVersion = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CiRuntimeEvidence.ps1')
. (Join-Path $PSScriptRoot '../install-ps-modules/CiDependencyRoot.ps1')
Initialize-CiDependencyEnvironment

Set-Location -LiteralPath $ProjectRoot
Import-CiPester -RequiredVersion $PesterRequiredVersion
Import-Module NovaModuleTools -ErrorAction Stop
Remove-Module $ProjectName -ErrorAction SilentlyContinue
Import-Module $BuiltModulePath -Force -ErrorAction Stop
if ($PesterRequiredVersion) {
    Assert-CiPesterVersion -RequiredVersion $PesterRequiredVersion
}

$tagArguments = @{}
$excludeTag = @($ExcludeTagList -split ',' | Where-Object { $_ })
if ($excludeTag.Count -gt 0) {
    $tagArguments.ExcludeTagFilter = $excludeTag
}

& $CommandName @tagArguments
