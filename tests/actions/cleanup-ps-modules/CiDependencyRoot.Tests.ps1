BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $source = Join-Path $root 'actions/install-ps-modules/CiDependencyRoot.ps1'
    if (Test-Path $source) { . $source }
    function Initialize-OwnedModuleFixture {
        param([string]$Path)
        $module = Join-Path $Path 'FixtureRoot'
        $null = New-Item -ItemType Directory -Path $module
        "@{ RootModule = 'FixtureRoot.psm1'; ModuleVersion = '1.0.0' }" | Set-Content "$module/FixtureRoot.psd1"
        "function Get-FixtureRoot { `$PSScriptRoot }" | Set-Content "$module/FixtureRoot.psm1"
        return (Join-Path $module 'FixtureRoot.psm1')
    }
}

Describe 'Owned isolated dependency roots' {
    It 'records a physical root when the selected temporary parent is a filesystem link' {
        $physical = Join-Path $TestDrive 'physical-parent'
        $null = New-Item -ItemType Directory -Path $physical
        $link = Join-Path $TestDrive 'linked-parent'
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $link -Target $physical
        $owner = New-CiDependencyRoot -Path (Join-Path $link 'powershell-ci-modules-linked')
        $owner.Path | Should -BeExactly (Join-Path $physical 'powershell-ci-modules-linked')
        Remove-CiDependencyRoot -Owner $owner
        Test-Path $owner.Path | Should -BeFalse
    }

    It 'creates a marker and isolates discovery to owned modules plus PSHOME' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-valid')
        (Get-CiDependencyOwner -Path $owner.Path).Token | Should -BeExactly $owner.Token
        Get-CiIsolatedModulePath -ModuleRoot $owner.Path | Should -BeExactly ($owner.Path + [IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules'))
    }

    It 'removes only the valid owned root' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-clean')
        Remove-CiDependencyRoot -Owner $owner
        Test-Path $owner.Path | Should -BeFalse
    }

    It 'refuses tampered ownership and leaves the directory intact' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-tampered')
        $changed = @{ Path = $owner.Path; Token = '00000000000000000000000000000000' }
        $changed | ConvertTo-Json | Set-Content (Join-Path $owner.Path '.powershell-ci-dependencies.json')
        { Remove-CiDependencyRoot -Owner $owner } | Should -Throw '*ownership changed*'
        Test-Path $owner.Path | Should -BeTrue
    }

    It 'rejects an unowned root before any consumer runs' {
        $path = Join-Path $TestDrive 'powershell-ci-modules-unowned'
        $null = New-Item -ItemType Directory -Path $path
        { Get-CiIsolatedModulePath -ModuleRoot $path } | Should -Throw
    }

    It 'does not remove resources under WhatIf' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-whatif')
        Remove-CiDependencyRoot -Owner $owner -WhatIf
        Test-Path $owner.Path | Should -BeTrue
    }

    It 'does not create an owned root under WhatIf' {
        $path = Join-Path $TestDrive 'powershell-ci-modules-create-whatif'
        New-CiDependencyRoot -Path $path -WhatIf | Should -BeNullOrEmpty
        Test-Path $path | Should -BeFalse
    }

    It 'imports the exact owned path in a fresh PowerShell process' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-fresh')
        $expected = Initialize-OwnedModuleFixture -Path $owner.Path
        $isolated = Get-CiIsolatedModulePath -ModuleRoot $owner.Path
        $command = '$env:PSModulePath = "{0}"; Import-Module FixtureRoot -ErrorAction Stop; (Get-Module FixtureRoot).Path' -f $isolated
        $result = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -Command $command
        $LASTEXITCODE | Should -Be 0
        $result | Should -BeExactly $expected
    }

    It 'rejects a changed marker path before discovery' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-wrongpath')
        $record = @{ Path = $TestDrive; Token = $owner.Token }
        $record | ConvertTo-Json | Set-Content "$($owner.Path)/.powershell-ci-dependencies.json"
        { Get-CiIsolatedModulePath -ModuleRoot $owner.Path } | Should -Throw '*Invalid dependency ownership*'
    }

    It 'validates ownership before cleanup in a fresh PowerShell process' {
        $owner = New-CiDependencyRoot -Path (Join-Path $TestDrive 'powershell-ci-modules-childclean')
        $command = '. "{0}"; $owner = Get-CiDependencyOwner -Path "{1}"; Remove-CiDependencyRoot -Owner $owner' -f $source, $owner.Path
        & (Get-Process -Id $PID).Path -NoLogo -NoProfile -Command $command
        $LASTEXITCODE | Should -Be 0
        Test-Path $owner.Path | Should -BeFalse
    }
}
