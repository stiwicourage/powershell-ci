BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'actions/install-ps-modules/CiDependencyProbe.ps1') -ModuleRoot unused
    function Initialize-ProbeModule {
        param([string]$Path, [string]$Version)
        $directory = Join-Path $Path "Pester/$Version"
        $null = New-Item -ItemType Directory -Path $directory -Force
        '' | Set-Content "$directory/Pester.psm1"
        "@{ RootModule = 'Pester.psm1'; ModuleVersion = '$Version' }" | Set-Content "$directory/Pester.psd1"
    }
}

Describe 'Exact isolated module closure' {
    It 'chooses the exact saved version even when a newer module exists' {
        Initialize-ProbeModule -Path $TestDrive -Version 5.7.1
        Initialize-ProbeModule -Path $TestDrive -Version 5.9.1
        $path = Resolve-CiSavedModule -ModuleRoot $TestDrive -Requirement @{ Name = 'Pester'; RequiredVersion = '5.7.1' }
        $path | Should -BeExactly (Join-Path $TestDrive 'Pester/5.7.1/Pester.psd1')
    }

    It 'does not fall back to ambient Pester if the exact saved version is missing' {
        { Resolve-CiSavedModule -ModuleRoot $TestDrive -Requirement @{ Name = 'Pester'; RequiredVersion = '4.0.0' } } | Should -Throw '*No saved module*'
    }

    It 'reads a stable manifest version with no PrivateData under StrictMode' {
        Initialize-ProbeModule -Path $TestDrive -Version 5.7.1
        $module = Get-Module -ListAvailable -Name (Join-Path $TestDrive 'Pester/5.7.1/Pester.psd1')
        Set-StrictMode -Version Latest
        Get-CiFullModuleVersion -Module $module | Should -BeExactly '5.7.1'
    }

    It 'imports the exact constrained path without mutually exclusive version arguments' {
        Initialize-ProbeModule -Path $TestDrive -Version 5.7.1
        Mock Import-Module {}
        Import-CiRequiredModule -ModuleRoot $TestDrive -Requirement @{ Name = 'Pester'; RequiredVersion = '5.7.1'; MinimumVersion = '5.7'; MaximumVersion = '6.0' }
        Should -Invoke Import-Module -Exactly -Times 1 -ParameterFilter {
            $Name -eq (Join-Path $TestDrive 'Pester/5.7.1/Pester.psd1') -and $RequiredVersion -eq '5.7.1' -and -not $MinimumVersion -and -not $MaximumVersion
        }
    }

    It 'rejects imported modules outside the owned root and PSHOME' {
        Mock Get-Module { @{ Name = 'Ambient'; ModuleBase = '/ambient/modules/Ambient' } }
        { Assert-CiDependencyOrigin -ModuleRoot $TestDrive } | Should -Throw '*outside isolation*'
    }

    It 'rejects a saved provider that shadows native PSHOME PowerShellGet' {
        Mock Get-Module { @{ Name = 'PowerShellGet'; Version = [version]'2.2.5'; ModuleBase = "$TestDrive/PowerShellGet/2.2.5" } }
        { Assert-CiDependencyOrigin -ModuleRoot $TestDrive } | Should -Throw '*native provider*'
    }
}

Describe 'Native provider import' {
    It 'imports the native provider of the exact version from PSHOME' {
        $native = [pscustomobject]@{ Name = 'PowerShellGet'; Version = [version]'2.2.5'; ModuleBase = (Join-Path $PSHOME 'Modules/PowerShellGet'); Path = "$PSHOME/Modules/PowerShellGet/PowerShellGet.psd1" }
        $ambient = [pscustomobject]@{ Name = 'PowerShellGet'; Version = [version]'2.2.5'; ModuleBase = '/ambient/PowerShellGet'; Path = '/ambient/PowerShellGet.psd1' }
        Mock Get-Module { @($ambient, $native) }
        Mock Remove-Module {}
        Mock Import-Module {}
        Import-CiNativeProvider -Name PowerShellGet -Version 2.2.5
        Should -Invoke Remove-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'PowerShellGet' -and $Force }
        Should -Invoke Import-Module -Exactly -Times 1 -ParameterFilter { $Name -eq $native.Path }
    }

    It 'refuses to import a provider that exists only outside PSHOME' {
        Mock Get-Module { [pscustomobject]@{ Name = 'PowerShellGet'; Version = [version]'2.2.5'; ModuleBase = '/ambient/PowerShellGet'; Path = 'x' } }
        Mock Import-Module {}
        { Import-CiNativeProvider -Name PowerShellGet -Version 2.2.5 } | Should -Throw "*native provider 'PowerShellGet' 2.2.5 is unavailable in PSHOME*"
        Should -Invoke Import-Module -Times 0
    }
}

Describe 'Prerelease-aware module versions' {
    It 'appends the manifest prerelease label to the version' {
        $module = [pscustomobject]@{ Version = [version]'2.0.0'; PrivateData = @{ PSData = @{ Prerelease = 'beta1' } } }
        Get-CiFullModuleVersion -Module $module | Should -BeExactly '2.0.0-beta1'
    }

    It 'treats <Scenario> as a stable version' -ForEach @(
        @{ Scenario = 'missing private data'; PrivateData = $null }
        @{ Scenario = 'private data without PSData'; PrivateData = @{ Other = 1 } }
        @{ Scenario = 'an empty prerelease label'; PrivateData = @{ PSData = @{ Prerelease = '' } } }
    ) {
        Get-CiFullModuleVersion -Module ([pscustomobject]@{ Version = [version]'2.0.0'; PrivateData = $PrivateData }) | Should -BeExactly '2.0.0'
    }

    It 'matches a required version that includes the prerelease label' {
        $module = [pscustomobject]@{ Version = [version]'2.0.0'; PrivateData = @{ PSData = @{ Prerelease = 'beta1' } } }
        Test-CiSavedVersion -Module $module -Requirement @{ RequiredVersion = '2.0.0-beta1' } | Should -BeTrue
        Test-CiSavedVersion -Module $module -Requirement @{ RequiredVersion = '2.0.0' } | Should -BeFalse
    }

    It 'enforces minimum and maximum bounds' {
        $module = [pscustomobject]@{ Version = [version]'2.0.0'; PrivateData = $null }
        Test-CiSavedVersion -Module $module -Requirement @{ MinimumVersion = '1.0'; MaximumVersion = '3.0' } | Should -BeTrue
        Test-CiSavedVersion -Module $module -Requirement @{ MinimumVersion = '2.1' } | Should -BeFalse
        Test-CiSavedVersion -Module $module -Requirement @{ MaximumVersion = '1.9' } | Should -BeFalse
    }
}

Describe 'Dependency probe' {
    BeforeEach {
        $script:savedModulePath = $env:PSModulePath
        $script:owner = New-CiDependencyRoot -Path (Join-Path $TestDrive "powershell-ci-modules-$([guid]::NewGuid().ToString('N'))")
    }

    AfterEach { $env:PSModulePath = $script:savedModulePath }

    It 'records the PowerShell version and loaded modules as a witness' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Fixture'; Version = [version]'1.2.3'; Path = 'p'; ModuleBase = 'b' } }
        Write-CiDependencyWitness -ModuleRoot $owner.Path
        $witness = Get-Content (Join-Path $owner.Path '.runtime-evidence.json') -Raw | ConvertFrom-Json
        $witness.PowerShell | Should -BeExactly ([string]$PSVersionTable.PSVersion)
        $witness.Modules.Name | Should -Contain 'Fixture'
        @($witness.Modules | Where-Object Name -EQ Fixture)[0].Version | Should -BeExactly '1.2.3'
    }

    It 'imports Pester first, PSResourceGet second and the rest alphabetically' {
        $requirements = @(@{ Name = 'Zeta' }, @{ Name = 'Microsoft.PowerShell.PSResourceGet' }, @{ Name = 'Alpha' }, @{ Name = 'Pester' })
        ConvertTo-Json -InputObject $requirements | Set-Content (Join-Path $owner.Path '.requirements.json')
        $script:imported = @()
        Mock Initialize-CiDependencyEnvironment {}
        Mock Import-CiNativeProvider { $script:imported += "native:$Name" }
        Mock Import-CiRequiredModule { $script:imported += $Requirement.Name }
        Mock Assert-CiDependencyOrigin { $script:imported += 'origin' }
        Mock Write-CiDependencyWitness { $script:imported += 'witness' }
        Invoke-CiDependencyProbe -ModuleRoot $owner.Path -OwnerToken $owner.Token
        $script:imported -join ',' | Should -BeExactly 'native:PackageManagement,native:PowerShellGet,Pester,Microsoft.PowerShell.PSResourceGet,Alpha,Zeta,origin,witness'
    }

    It 'validates the owned root and writes a witness when run as a script' {
        ConvertTo-Json -InputObject @() | Set-Content (Join-Path $owner.Path '.requirements.json')
        Mock Import-Module {}
        Mock Get-Module { @() }
        Mock Get-Module {
            @(
                [pscustomobject]@{ Name = 'PackageManagement'; Version = [version]'1.4.8.1'; ModuleBase = (Join-Path $PSHOME 'Modules/PackageManagement'); Path = 'pm' }
                [pscustomobject]@{ Name = 'PowerShellGet'; Version = [version]'2.2.5'; ModuleBase = (Join-Path $PSHOME 'Modules/PowerShellGet'); Path = 'psg' }
            ) | Where-Object Name -EQ $Name
        } -ParameterFilter { $ListAvailable }
        & (Join-Path $root 'actions/install-ps-modules/CiDependencyProbe.ps1') -ModuleRoot $owner.Path -OwnerToken $owner.Token
        Test-Path (Join-Path $owner.Path '.runtime-evidence.json') | Should -BeTrue
        $env:PSModulePath | Should -BeExactly ($owner.Path + [IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules'))
    }

    It 'refuses to run without the independently retained owner token' {
        Mock Import-Module {}
        { & (Join-Path $root 'actions/install-ps-modules/CiDependencyProbe.ps1') -ModuleRoot $owner.Path -OwnerToken '' } |
            Should -Throw '*owner token is required*'
    }
}
