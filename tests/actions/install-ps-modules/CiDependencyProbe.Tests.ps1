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
