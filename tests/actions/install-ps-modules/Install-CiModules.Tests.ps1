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

Describe 'Requirement validation' {
    It 'rejects a module name that is not a plain module identifier' {
        { Get-CiModuleRequirement -Modules 'Bad;Name' } | Should -Throw "*Invalid CI module name 'Bad;Name'*"
    }

    It 'rejects a minimum version above the maximum version' {
        $project = Join-Path $TestDrive 'inverted.json'
        '{"Manifest":{"RequiredModules":[{"ModuleName":"Tool","ModuleVersion":"3.0","MaximumVersion":"2.0"}]}}' | Set-Content $project
        { Get-CiModuleRequirement -ProjectFile $project } | Should -Throw "*Conflicting version range for 'Tool'*"
    }
}

Describe 'Gallery registration' {
    BeforeEach {
        Mock Get-PSRepository { @{ SourceLocation = 'https://www.powershellgallery.com/api/v2/'; InstallationPolicy = 'Untrusted' } }
        Mock Register-PSRepository {}
        Mock Unregister-PSRepository {}
    }

    It 'registers the default PSGallery with a stopping error preference' {
        Register-CiDefaultGallery
        Should -Invoke Register-PSRepository -Exactly -Times 1 -ParameterFilter { $Default -and $ErrorAction -eq 'Stop' }
    }

    It 'removes the temporary registration when it is still untrusted and unchanged' {
        $snapshot = Get-CiGallerySnapshot
        Close-CiGallery -Registered $snapshot
        Should -Invoke Unregister-PSRepository -Exactly -Times 1 -ParameterFilter { $Name -eq 'PSGallery' }
    }

    It 'leaves a pre-existing registration alone' {
        Close-CiGallery -Registered $false
        Should -Invoke Unregister-PSRepository -Times 0
    }

    It 'rethrows a restoration failure when the download itself succeeded' {
        Mock Close-CiGallery { throw 'restore failed' }
        { Close-CiGalleryAfterSave -Registered $true } | Should -Throw '*restore failed*'
    }
}

Describe 'Legacy installation' {
    BeforeEach {
        Mock Get-PSRepository { $null }
        Mock Register-PSRepository {}
        Mock Set-PSRepository {}
    }

    It 'refuses an unregistered repository other than PSGallery' {
        { Initialize-CiLegacyRepository -Repository 'Internal' } | Should -Throw "*'Internal' is not registered*"
        Should -Invoke Register-PSRepository -Times 0
    }

    It 'registers PSGallery when missing and trusts it' {
        Initialize-CiLegacyRepository -Repository 'PSGallery'
        Should -Invoke Register-PSRepository -Exactly -Times 1 -ParameterFilter { $Default }
        Should -Invoke Set-PSRepository -Exactly -Times 1 -ParameterFilter { $Name -eq 'PSGallery' -and $InstallationPolicy -eq 'Trusted' }
    }

    It 'trusts a registered repository without registering it again' {
        Mock Get-PSRepository { @{ Name = 'Internal' } }
        Initialize-CiLegacyRepository -Repository 'Internal'
        Should -Invoke Register-PSRepository -Times 0
        Should -Invoke Set-PSRepository -Exactly -Times 1 -ParameterFilter { $Name -eq 'Internal' }
    }

    It 'installs explicit and project modules once each, whether named by string or by object' {
        $project = Join-Path $TestDrive 'legacy.json'
        '{"Manifest":{"RequiredModules":["FromString",{"ModuleName":"FromObject"},{"ModuleName":"Explicit"}]}}' | Set-Content $project
        Mock Initialize-CiLegacyRepository {}
        Mock Install-Module {}
        Mock Get-InstalledModule { @([pscustomobject]@{ Name = $Name; Version = [version]'1.0'; Repository = 'PSGallery' }, [pscustomobject]@{ Name = $Name; Version = [version]'2.0'; Repository = 'PSGallery' }) }
        $output = @(Install-CiLegacyModule -Modules Explicit -ProjectFile $project -Repository PSGallery -AllowPrerelease $false)
        Should -Invoke Install-Module -Exactly -Times 3
        Should -Invoke Install-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'Explicit' -and $Scope -eq 'CurrentUser' -and -not $AllowPrerelease }
        Should -Invoke Install-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'FromString' }
        Should -Invoke Install-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'FromObject' }
        $output | Should -Contain "Installed 'FromObject' 2.0 from 'PSGallery'."
    }
}

Describe 'Isolated closure validation and entry point' {
    BeforeAll {
        function Initialize-FakeProcess {
            param([string]$Directory, [int]$ExitCode)
            $path = Join-Path $Directory 'fake-pwsh'
            "#!/bin/sh`nprintf '%s\n' `"`$@`" > '$path.args'`nexit $ExitCode`n" | Set-Content -LiteralPath $path -NoNewline
            [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
            return $path
        }
    }

    BeforeEach {
        $script:savedEnvironment = @{}
        foreach ($name in 'RUNNER_TEMP', 'GITHUB_ENV', 'GITHUB_OUTPUT', 'PSModulePath') {
            $script:savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $script:owner = New-CiDependencyRoot -Path (Join-Path $TestDrive "powershell-ci-modules-$([guid]::NewGuid().ToString('N'))")
    }

    AfterEach {
        foreach ($name in $script:savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $script:savedEnvironment[$name])
        }
    }

    It 'writes the requirements and passes the owner to a fresh probe process' -Skip:$IsWindows {
        $fake = Initialize-FakeProcess -Directory $TestDrive -ExitCode 0
        Mock Get-Process { [pscustomobject]@{ Path = $fake } }
        Assert-CiSavedModuleClosure -Owner $owner -Requirements @(@{ Name = 'Pester'; RequiredVersion = '5.7.1' })
        (Get-Content (Join-Path $owner.Path '.requirements.json') -Raw | ConvertFrom-Json).Name | Should -Be 'Pester'
        $arguments = Get-Content "$fake.args"
        $arguments | Should -Contain '-ModuleRoot'
        $arguments | Should -Contain $owner.Path
        $arguments | Should -Contain $owner.Token
        $arguments | Should -Contain (Join-Path (Split-Path -Parent $source) 'CiDependencyProbe.ps1')
    }

    It 'fails when the fresh probe process rejects the closure' -Skip:$IsWindows {
        $fake = Initialize-FakeProcess -Directory $TestDrive -ExitCode 3
        Mock Get-Process { [pscustomobject]@{ Path = $fake } }
        { Assert-CiSavedModuleClosure -Owner $owner -Requirements @() } | Should -Throw '*closure validation failed*'
    }

    It 'places the owned root under RUNNER_TEMP when it is set' {
        $env:RUNNER_TEMP = Join-Path $TestDrive 'runner-temp'
        Mock New-CiDependencyRoot { $owner }
        Mock Save-CiRequiredModule {}
        Mock Assert-CiSavedModuleClosure {}
        Mock Publish-CiDependencyEnvironment {}
        Invoke-CiIsolatedInstall -Requirements @() -AllowPrerelease $true | Out-Null
        Should -Invoke New-CiDependencyRoot -Exactly -Times 1 -ParameterFilter {
            $Path -like (Join-Path $env:RUNNER_TEMP 'powershell-ci-modules-*')
        }
    }

    It 'installs in legacy mode by default when run as a script' {
        Mock Get-PSRepository { @{ Name = 'PSGallery' } }
        Mock Set-PSRepository {}
        Mock Install-Module {}
        Mock Get-InstalledModule { [pscustomobject]@{ Name = $Name; Version = [version]'1.0'; Repository = 'PSGallery' } }
        $output = @(& $source -Modules Fixture -ProjectFile '' -AllowPrerelease $false)
        Should -Invoke Install-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'Fixture' -and $Repository -eq 'PSGallery' }
        $output | Should -Contain "Installed 'Fixture' 1.0 from 'PSGallery'."
    }

    It 'rejects isolated mode for a repository other than PSGallery' {
        { & $source -DependencyMode isolated -Repository Internal } | Should -Throw '*Isolated mode requires PSGallery*'
    }

    It 'provisions, validates and publishes an isolated closure when run as a script' -Skip:$IsWindows {
        $fake = Initialize-FakeProcess -Directory $TestDrive -ExitCode 0
        $env:RUNNER_TEMP = Join-Path $TestDrive 'isolated-temp'
        $null = New-Item -ItemType Directory -Path $env:RUNNER_TEMP
        $env:GITHUB_ENV = Join-Path $TestDrive 'github-env'
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'github-output'
        Mock Get-Process { [pscustomobject]@{ Path = $fake } }
        Mock Get-PSRepository { @{ SourceLocation = 'https://www.powershellgallery.com/api/v2'; InstallationPolicy = 'Untrusted' } }
        Mock Save-Module {}
        & $source -DependencyMode isolated -Modules Fixture -ProjectFile '' -PesterRequiredVersion 5.7.1
        Should -Invoke Save-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'Fixture' -and $Path -like "$env:RUNNER_TEMP*" }
        Should -Invoke Save-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'Pester' -and $RequiredVersion -eq '5.7.1' }
        $moduleRoot = (Get-Content $env:GITHUB_OUTPUT | Where-Object { $_ -like 'module-root=*' }) -replace '^module-root=', ''
        $moduleRoot | Should -BeLike "$env:RUNNER_TEMP*powershell-ci-modules-*"
        Get-Content $env:GITHUB_ENV | Should -Contain "POWERSHELL_CI_MODULE_ROOT=$moduleRoot"
    }
}
