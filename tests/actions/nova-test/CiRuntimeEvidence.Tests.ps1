BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $source = Join-Path $root 'actions/nova-test/CiRuntimeEvidence.ps1'
    if (Test-Path $source) { . $source }
}

Describe 'Opt-in exact Pester and actual runtime evidence' {
    It 'preserves ambient Pester unless a version is requested' {
        Mock Import-Module {}
        Mock Remove-Module {}
        Import-CiPester -RequiredVersion ''
        Should -Invoke Import-Module -Times 0
        Should -Invoke Remove-Module -Times 0
    }

    It 'imports only the requested Pester version' {
        Mock Import-Module {}
        Mock Remove-Module {}
        Import-CiPester -RequiredVersion 5.7.1
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'Pester' -and $RequiredVersion -eq '5.7.1' }
    }

    It 'records actual imported module paths and PowerShell version' {
        Write-CiRuntimeEvidence -OutputDirectory $TestDrive
        $evidence = Get-Content "$TestDrive/runtime-evidence.json" -Raw | ConvertFrom-Json
        $evidence.PowerShell | Should -Be ([string]$PSVersionTable.PSVersion)
        @($evidence.Modules | Where-Object Name -EQ Pester)[0].Path | Should -Be (Get-Module Pester).Path
    }

    It 'refuses a runtime witness when Nova replaced the requested Pester version' {
        Mock Get-Module { @{ Name = 'Pester'; Version = [version]'6.0.0' } }
        { Assert-CiPesterVersion -RequiredVersion 5.7.1 } | Should -Throw '*requested Pester*'
    }
}
