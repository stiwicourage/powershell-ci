BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $source = Join-Path $root 'actions/install-ps-modules/Install-CiModules.ps1'
    if (Test-Path $source) { . $source }
}

Describe 'Isolated dependency selection' {
    It 'pins the existing analyzer requirement instead of accepting a newer Gallery version' {
        $requirements = @(Get-CiModuleRequirement -Modules PSScriptAnalyzer -ProjectFile '' -ScriptAnalyzerRequiredVersion 1.25.0)
        ($requirements | Where-Object Name -EQ PSScriptAnalyzer).RequiredVersion | Should -BeExactly '1.25.0'
    }

    It 'accepts a project with no required modules without inventing a null module' {
        $project = Join-Path $TestDrive 'empty.json'
        '{"Manifest":{}}' | Set-Content $project
        $requirements = @(Get-CiModuleRequirement -ProjectFile $project)
        $requirements.Count | Should -Be 1
        $requirements[0].Name | Should -Be 'Microsoft.PowerShell.PSResourceGet'
    }

    It 'preserves project exact versions and applies the requested Pester version' {
        $project = Join-Path $TestDrive 'exact.json'
        '{"Manifest":{"RequiredModules":[{"ModuleName":"Tool","RequiredVersion":"2.3.4"}]}}' | Set-Content $project
        $requirements = @(Get-CiModuleRequirement -Modules Tool -ProjectFile $project -PesterRequiredVersion 5.7.1)
        ($requirements | Where-Object Name -EQ Tool).RequiredVersion | Should -Be '2.3.4'
        ($requirements | Where-Object Name -EQ Pester).RequiredVersion | Should -Be '5.7.1'
        ($requirements | Where-Object Name -EQ Microsoft.PowerShell.PSResourceGet).RequiredVersion | Should -Be '1.2.0'
    }

    Describe 'Owned provisioning failures and exact download arguments' {
        BeforeEach {
            $script:owned = New-CiDependencyRoot -Path (Join-Path $TestDrive "powershell-ci-modules-$([guid]::NewGuid().ToString('N'))")
            Mock New-CiDependencyRoot { $owned }
            Mock Save-CiRequiredModule {}
            Mock Assert-CiSavedModuleClosure {}
            Mock Publish-CiDependencyEnvironment {}
        }

        It 'saves exact versions only to the owned destination without Scope' {
            $parameters = Get-CiSaveParameter -Requirement @{ Name = 'Pester'; RequiredVersion = '5.7.1' } -ModuleRoot $owned.Path -AllowPrerelease $true
            $parameters.RequiredVersion | Should -BeExactly '5.7.1'
            $parameters.Path | Should -BeExactly $owned.Path
            $parameters.Repository | Should -BeExactly 'PSGallery'
            $parameters.ContainsKey('Scope') | Should -BeFalse
        }

        It 'uses an exact provider pin after validating the project version range' {
            $requirement = @{ Name = 'Pester'; RequiredVersion = '5.7.1'; MinimumVersion = '5.7'; MaximumVersion = '6.0' }
            $parameters = Get-CiSaveParameter -Requirement $requirement -ModuleRoot $owned.Path -AllowPrerelease $true
            $parameters.RequiredVersion | Should -BeExactly '5.7.1'
            $parameters.ContainsKey('MinimumVersion') | Should -BeFalse
            $parameters.ContainsKey('MaximumVersion') | Should -BeFalse
        }

        It 'publishes ownership only after saving and successful closure validation' {
            $script:events = @()
            Mock Save-CiRequiredModule { $script:events += 'save' }
            Mock Assert-CiSavedModuleClosure { $script:events += 'probe' }
            Mock Publish-CiDependencyEnvironment { $script:events += 'publish' }
            $actual = Invoke-CiIsolatedInstall -Requirements @() -AllowPrerelease $true
            $actual.Path | Should -BeExactly $owned.Path
            $events -join ',' | Should -BeExactly 'save,probe,publish'
            Test-Path $owned.Path | Should -BeTrue
        }

        It 'cleans its root on save failure and does not publish environment outputs' {
            Mock Save-CiRequiredModule { throw 'download failed' }
            { Invoke-CiIsolatedInstall -Requirements @() -AllowPrerelease $true } | Should -Throw '*download failed*'
            Test-Path $owned.Path | Should -BeFalse
            Should -Invoke Publish-CiDependencyEnvironment -Times 0
        }

        It 'cleans its root on fresh-process validation failure' {
            Mock Assert-CiSavedModuleClosure { throw 'probe failed' }
            { Invoke-CiIsolatedInstall -Requirements @() -AllowPrerelease $true } | Should -Throw '*probe failed*'
            Test-Path $owned.Path | Should -BeFalse
        }

        It 'retains both primary and cleanup failures rather than replacing the primary failure' {
            Mock Save-CiRequiredModule { throw 'primary download failure' }
            Mock Remove-CiDependencyRoot { throw 'secondary cleanup failure' }
            { Invoke-CiIsolatedInstall -Requirements @() -AllowPrerelease $true } | Should -Throw '*primary download failure*secondary cleanup failure*'
        }
    }

    It 'intersects minimum and maximum constraints without latest fallback' {
        $project = Join-Path $TestDrive 'range.json'
        '{"Manifest":{"RequiredModules":[{"ModuleName":"Tool","ModuleVersion":"2.0","MaximumVersion":"3.0"},{"ModuleName":"Tool","ModuleVersion":"2.5"}]}}' | Set-Content $project
        $requirements = @(Get-CiModuleRequirement -Modules Tool -ProjectFile $project)
        $tool = $requirements | Where-Object Name -EQ Tool
        $tool.MinimumVersion | Should -Be '2.5'
        $tool.MaximumVersion | Should -Be '3.0'
    }

    It 'rejects conflicting exact versions before downloading' {
        $project = Join-Path $TestDrive 'conflict.json'
        '{"Manifest":{"RequiredModules":[{"ModuleName":"Pester","RequiredVersion":"6.0.0"}]}}' | Set-Content $project
        { Get-CiModuleRequirement -ProjectFile $project -PesterRequiredVersion 5.7.1 } | Should -Throw '*Conflicting*'
    }

    It 'rejects an exact version outside a required range' {
        $project = Join-Path $TestDrive 'outside.json'
        '{"Manifest":{"RequiredModules":[{"ModuleName":"Pester","ModuleVersion":"6.0"}]}}' | Set-Content $project
        { Get-CiModuleRequirement -ProjectFile $project -PesterRequiredVersion 5.7.1 } | Should -Throw '*outside*'
    }

    It 'does not change existing Gallery trust or source' {
        Mock Get-PSRepository { @{ SourceLocation = 'https://www.powershellgallery.com/api/v2'; InstallationPolicy = 'Untrusted' } }
        Mock Set-PSRepository {}
        Open-CiGallery | Should -BeFalse
        Should -Invoke Set-PSRepository -Times 0
    }

    It 'rejects a substituted Gallery endpoint' {
        Mock Get-PSRepository { @{ SourceLocation = 'https://example.invalid'; InstallationPolicy = 'Trusted' } }
        { Assert-CiGallery } | Should -Throw '*official PSGallery*'
    }

    It 'does not remove a changed temporary registration' {
        Mock Get-PSRepository { @{ SourceLocation = 'https://www.powershellgallery.com/api/v2'; InstallationPolicy = 'Trusted' } }
        Mock Unregister-PSRepository {}
        { Close-CiGallery -Registered $true } | Should -Throw '*changed*'
        Should -Invoke Unregister-PSRepository -Times 0
    }
}
