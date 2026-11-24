BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:processScript = Join-Path $root 'actions/nova-test/Invoke-NovaTestProcess.ps1'
    function Invoke-NovaTest { param([string[]]$ExcludeTagFilter) throw "Unmocked unit collaborator: $ExcludeTagFilter" }
    function Test-NovaBuild { param([string[]]$ExcludeTagFilter) throw "Unmocked integration collaborator: $ExcludeTagFilter" }
}

Describe 'Invoke-NovaTestProcess' {
    BeforeEach {
        $script:originalLocation = (Get-Location).Path
        $script:savedModuleRoot = $env:POWERSHELL_CI_MODULE_ROOT
        $env:POWERSHELL_CI_MODULE_ROOT = $null
        $script:project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $project -Force
        Mock Import-Module {}
        Mock Remove-Module {}
        Mock Invoke-NovaTest { 'unit' }
        Mock Test-NovaBuild { 'integration' }
    }

    AfterEach {
        Set-Location -LiteralPath $script:originalLocation
        $env:POWERSHELL_CI_MODULE_ROOT = $script:savedModuleRoot
    }

    It 'imports Nova and the built module from the project root, then runs the command without exclusions' {
        $result = & $processScript -ProjectRoot $project -ProjectName Fixture -BuiltModulePath '/built/Fixture' -CommandName Invoke-NovaTest
        $result | Should -BeExactly 'unit'
        (Get-Location).Path | Should -BeExactly (Resolve-Path -LiteralPath $project).Path
        Should -Invoke Import-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'NovaModuleTools' }
        Should -Invoke Import-Module -Exactly -Times 1 -ParameterFilter { $Name -eq '/built/Fixture' -and $Force }
        Should -Invoke Remove-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'Fixture' }
        Should -Invoke Invoke-NovaTest -Exactly -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('ExcludeTagFilter') }
    }

    It 'splits the comma separated exclusions and ignores empty entries' {
        $result = & $processScript -ProjectRoot $project -ProjectName Fixture -BuiltModulePath '/built/Fixture' -CommandName Test-NovaBuild -ExcludeTagList 'Live,,Slow'
        $result | Should -BeExactly 'integration'
        Should -Invoke Test-NovaBuild -Exactly -Times 1 -ParameterFilter { ($ExcludeTagFilter -join '|') -eq 'Live|Slow' }
    }

    It 'imports the requested Pester version and accepts it once retained' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pester'; Version = [version]'5.7.1' } } -ParameterFilter { $Name -eq 'Pester' }
        & $processScript -ProjectRoot $project -ProjectName Fixture -BuiltModulePath '/built/Fixture' -CommandName Invoke-NovaTest -PesterRequiredVersion 5.7.1
        Should -Invoke Import-Module -Exactly -Times 1 -ParameterFilter { $Name -eq 'Pester' -and $RequiredVersion -eq '5.7.1' }
        Should -Invoke Invoke-NovaTest -Exactly -Times 1
    }

    It 'does not run tests when the built module replaced the requested Pester version' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pester'; Version = [version]'6.0.0' } } -ParameterFilter { $Name -eq 'Pester' }
        { & $processScript -ProjectRoot $project -ProjectName Fixture -BuiltModulePath '/built/Fixture' -CommandName Invoke-NovaTest -PesterRequiredVersion 5.7.1 } |
            Should -Throw '*did not retain requested Pester 5.7.1*'
        Should -Invoke Invoke-NovaTest -Times 0
    }

    It 'rejects a command other than the two Nova test commands' {
        { & $processScript -ProjectRoot $project -ProjectName Fixture -BuiltModulePath '/built/Fixture' -CommandName Invoke-Expression } |
            Should -Throw '*ValidateSet*'
    }
}
