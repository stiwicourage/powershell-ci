[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$OutputPath = 'artifacts/coverage.xml'
)

$ErrorActionPreference = 'Stop'

# Tests exercise the install actions, which append to the runner's file commands and would otherwise leak into later steps.
foreach ($name in 'GITHUB_ENV', 'GITHUB_OUTPUT', 'GITHUB_PATH') {
    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
}

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $ProjectRoot 'tests'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Minimal'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    Join-Path $ProjectRoot 'actions'
    Join-Path $ProjectRoot 'scripts'
)
$config.CodeCoverage.RecursePaths = $true
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = Join-Path $ProjectRoot $OutputPath

Invoke-Pester -Configuration $config
