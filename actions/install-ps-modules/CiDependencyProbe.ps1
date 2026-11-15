[CmdletBinding()]
param([Parameter(Mandatory)][string]$ModuleRoot, [string]$OwnerToken = $env:POWERSHELL_CI_OWNER_TOKEN)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CiDependencyRoot.ps1')
. (Join-Path $PSScriptRoot 'CiModuleRequirements.ps1')

function Import-CiNativeProvider {
    param([string]$Name, [version]$Version)
    $module = Get-Module -ListAvailable -Name $Name | Where-Object {
        $_.Version -eq $Version -and $_.ModuleBase.StartsWith($PSHOME + [IO.Path]::DirectorySeparatorChar)
    } | Select-Object -First 1
    if (-not $module) {
        throw "Required native provider '$Name' $Version is unavailable in PSHOME."
    }
    Remove-Module -Name $Name -Force -ErrorAction SilentlyContinue
    Import-Module $module.Path -ErrorAction Stop
}

function Import-CiRequiredModule {
    param([hashtable]$Requirement, [string]$ModuleRoot)
    $arguments = @{ Name = (Resolve-CiSavedModule -ModuleRoot $ModuleRoot -Requirement $Requirement); ErrorAction = 'Stop' }
    Copy-CiProviderVersionConstraint -Requirement $Requirement -Parameters $arguments
    Import-Module @arguments
}

function Resolve-CiSavedModule {
    param([string]$ModuleRoot, [hashtable]$Requirement)
    $directory = Join-Path $ModuleRoot $Requirement.Name
    $manifests = @(Get-ChildItem -LiteralPath $directory -Filter "$($Requirement.Name).psd1" -Recurse -File -ErrorAction SilentlyContinue)
    $modules = @(foreach ($manifest in $manifests) { Get-Module -ListAvailable -Name $manifest.FullName })
    $selected = $modules | Where-Object { Test-CiSavedVersion -Module $_ -Requirement $Requirement } |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $selected) {
        throw "No saved module satisfies the required version of '$($Requirement.Name)'."
    }
    return $selected.Path
}

function Test-CiSavedVersion {
    param([object]$Module, [hashtable]$Requirement)
    foreach ($key in @('RequiredVersion', 'MinimumVersion', 'MaximumVersion')) {
        if ($Requirement[$key]) {
            if (-not (Test-CiModuleConstraint -Module $Module -Key $key -Value $Requirement[$key])) {
                return $false
            }
        }
    }
    return $true
}

function Test-CiModuleConstraint {
    param([object]$Module, [string]$Key, [string]$Value)
    switch ($Key) {
        'RequiredVersion' { return (Get-CiFullModuleVersion -Module $Module) -eq $Value }
        'MinimumVersion' { return $Module.Version -ge [version]$Value }
        'MaximumVersion' { return $Module.Version -le [version]$Value }
    }
}

function Get-CiFullModuleVersion {
    param([object]$Module)
    $version = [string]$Module.Version
    $prerelease = Get-CiModulePrerelease -PrivateData $Module.PrivateData
    if ($prerelease) {
        return "$version-$prerelease"
    }
    return $version
}

function Get-CiModulePrerelease {
    param([object]$PrivateData)
    if ($PrivateData -isnot [System.Collections.IDictionary]) {
        return ''
    }
    $psData = $PrivateData['PSData']
    if ($psData -isnot [System.Collections.IDictionary]) {
        return ''
    }
    return [string]$psData['Prerelease']
}

function Write-CiDependencyWitness {
    param([string]$ModuleRoot)
    $witness = @{
        PowerShell = [string]$PSVersionTable.PSVersion
        Modules = @(Get-Module | Select-Object Name, @{ Name = 'Version'; Expression = { [string]$_.Version } }, Path, ModuleBase)
    }
    $witness | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ModuleRoot '.runtime-evidence.json')
}

function Invoke-CiDependencyProbe {
    param([string]$ModuleRoot, [string]$OwnerToken)
    Initialize-CiDependencyEnvironment -ModuleRoot $ModuleRoot -OwnerToken $OwnerToken
    Import-CiNativeProvider -Name PackageManagement -Version 1.4.8.1
    Import-CiNativeProvider -Name PowerShellGet -Version 2.2.5
    $requirements = Get-Content (Join-Path $ModuleRoot '.requirements.json') -Raw | ConvertFrom-Json -AsHashtable
    $ordered = $requirements | Sort-Object { Get-CiImportPriority -Name $_.Name }, Name
    foreach ($requirement in $ordered) {
        Import-CiRequiredModule -Requirement $requirement -ModuleRoot $ModuleRoot
    }
    Assert-CiDependencyOrigin -ModuleRoot $ModuleRoot
    Write-CiDependencyWitness -ModuleRoot $ModuleRoot
}

function Get-CiImportPriority {
    param([string]$Name)
    if ($Name -eq 'Pester') { return 0 }
    if ($Name -eq 'Microsoft.PowerShell.PSResourceGet') { return 1 }
    return 2
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-CiDependencyProbe -ModuleRoot $ModuleRoot -OwnerToken $OwnerToken
}
