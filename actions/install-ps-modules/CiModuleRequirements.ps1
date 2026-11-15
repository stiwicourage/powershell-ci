function Get-CiProjectRequirement {
    param([string]$ProjectFile)
    if (-not $ProjectFile -or -not (Test-Path -LiteralPath $ProjectFile)) {
        return @()
    }
    $project = Get-Content -LiteralPath $ProjectFile -Raw | ConvertFrom-Json -AsHashtable
    return @($project.Manifest.RequiredModules | Where-Object { $_ })
}

function ConvertTo-CiModuleRequirement {
    param([object]$Specification)
    if ($Specification -is [string]) {
        return @{ Name = $Specification }
    }
    $requirement = @{ Name = $Specification.ModuleName }
    Copy-CiVersionConstraint -Source $Specification -Target $requirement
    return $requirement
}

function Copy-CiVersionConstraint {
    param([hashtable]$Source, [hashtable]$Target)
    foreach ($key in @('RequiredVersion', 'MinimumVersion', 'MaximumVersion')) {
        if ($Source[$key]) {
            $Target[$key] = [string]$Source[$key]
        }
    }
    if ($Source.ModuleVersion) {
        $Target.MinimumVersion = [string]$Source.ModuleVersion
    }
}

function Copy-CiProviderVersionConstraint {
    param([hashtable]$Requirement, [hashtable]$Parameters)
    if ($Requirement.RequiredVersion) {
        $Parameters.RequiredVersion = $Requirement.RequiredVersion
        return
    }
    Copy-CiVersionConstraint -Source $Requirement -Target $Parameters
}

function Get-CiModuleRequirement {
    param([string[]]$Modules = @(), [string]$ProjectFile = '', [string]$PesterRequiredVersion = '', [string]$ScriptAnalyzerRequiredVersion = '')
    $specifications = @($Modules) + @(Get-CiProjectRequirement -ProjectFile $ProjectFile)
    $specifications += @(Get-CiToolRequirement -PesterRequiredVersion $PesterRequiredVersion -ScriptAnalyzerRequiredVersion $ScriptAnalyzerRequiredVersion)
    $requirements = @{}
    foreach ($specification in $specifications) {
        Add-CiModuleRequirement -Requirements $requirements -Specification $specification
    }
    return @($requirements.Values | Sort-Object Name)
}

function Get-CiToolRequirement {
    param([string]$PesterRequiredVersion, [string]$ScriptAnalyzerRequiredVersion)
    $tools = @(@{ ModuleName = 'Microsoft.PowerShell.PSResourceGet'; RequiredVersion = '1.2.0' })
    if ($PesterRequiredVersion) {
        $tools += @{ ModuleName = 'Pester'; RequiredVersion = $PesterRequiredVersion }
    }
    if ($ScriptAnalyzerRequiredVersion) {
        $tools += @{ ModuleName = 'PSScriptAnalyzer'; RequiredVersion = $ScriptAnalyzerRequiredVersion }
    }
    return $tools
}

function Add-CiModuleRequirement {
    param([hashtable]$Requirements, [object]$Specification)
    $incoming = ConvertTo-CiModuleRequirement -Specification $Specification
    Assert-CiModuleName -Name $incoming.Name
    if (-not $Requirements.ContainsKey($incoming.Name)) {
        $Requirements[$incoming.Name] = @{ Name = $incoming.Name }
    }
    $existing = $Requirements[$incoming.Name]
    Merge-CiExactVersion -Existing $existing -Incoming $incoming
    Merge-CiVersionRange -Existing $existing -Incoming $incoming
    Assert-CiVersionRange -Requirement $existing
}

function Assert-CiModuleName {
    param([string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid CI module name '$Name'."
    }
}

function Merge-CiExactVersion {
    param([hashtable]$Existing, [hashtable]$Incoming)
    if (-not $Incoming.RequiredVersion) {
        return
    }
    if ($Existing.RequiredVersion -and $Existing.RequiredVersion -ne $Incoming.RequiredVersion) {
        throw "Conflicting exact versions for '$($Existing.Name)'."
    }
    $Existing.RequiredVersion = $Incoming.RequiredVersion
}

function Merge-CiVersionRange {
    param([hashtable]$Existing, [hashtable]$Incoming)
    foreach ($key in @('MinimumVersion', 'MaximumVersion')) {
        if (-not $Incoming[$key]) {
            continue
        }
        $values = @($Existing[$key], $Incoming[$key]) | Where-Object { $_ }
        $ordered = @($values | Sort-Object { [version]$_ })
        $index = if ($key -eq 'MinimumVersion') { -1 } else { 0 }
        $Existing[$key] = $ordered[$index]
    }
}

function Assert-CiVersionRange {
    param([hashtable]$Requirement)
    $minimum = Get-CiVersionBound -Requirement $Requirement -Key MinimumVersion -Default '0.0'
    $maximum = Get-CiVersionBound -Requirement $Requirement -Key MaximumVersion -Default '65535.65535.65535.65535'
    if ($minimum -gt $maximum) {
        throw "Conflicting version range for '$($Requirement.Name)'."
    }
    if (-not $Requirement.RequiredVersion) {
        return
    }
    $exact = [version]($Requirement.RequiredVersion -split '-')[0]
    if ($exact -lt $minimum -or $exact -gt $maximum) {
        throw "Exact version for '$($Requirement.Name)' is outside the required range."
    }
}

function Get-CiVersionBound {
    param([hashtable]$Requirement, [string]$Key, [string]$Default)
    if ($Requirement[$Key]) {
        return [version]$Requirement[$Key]
    }
    return [version]$Default
}
