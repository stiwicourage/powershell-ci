BeforeAll {
    $script:root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'actions/install-ps-modules/Install-CiModules.ps1')
}

Describe 'Released workflow callers retain legacy installation defaults' {
    It 'rejects an unregistered custom legacy repository without registering Gallery instead' {
        Mock Get-PSRepository { $null }
        { Initialize-CiLegacyRepository -Repository FixtureUnregistered } | Should -Throw '*not registered*'
    }

    It 'retains installer defaults expected by both released workflow generations' {
        $action = Get-Content (Join-Path $root 'actions/install-ps-modules/action.yml') -Raw
        $action | Should -Match 'default: PSGallery'
        $action | Should -Match 'default: project.json'
        $action | Should -Match "default: 'true'"
        $action | Should -Match 'default: legacy'
        $action | Should -Match "pester-required-version:[\s\S]+default: ''"
    }

    It 'installs unique legacy names with CurrentUser and no exact Pester pin' {
        Mock Initialize-CiLegacyRepository {}
        Mock Install-Module {}
        Mock Get-InstalledModule { @{ Name = 'Pester'; Version = '6.0.0'; Repository = 'PSGallery' } }
        Install-CiLegacyModule -Modules @('Pester', 'Pester') -ProjectFile '' -Repository PSGallery -AllowPrerelease $true
        Should -Invoke Install-Module -Exactly -Times 1 -ParameterFilter {
            $Name -eq 'Pester' -and $Scope -eq 'CurrentUser' -and -not $RequiredVersion -and $AllowPrerelease
        }
        Should -Invoke Initialize-CiLegacyRepository -Exactly -Times 1 -ParameterFilter { $Repository -eq 'PSGallery' }
        Get-Content (Join-Path $root 'actions/install-ps-modules/Install-CiModules.ps1') -Raw |
            Should -Match 'Set-PSRepository -Name \$Repository -InstallationPolicy Trusted'
    }
}
