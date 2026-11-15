BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:source = Join-Path $root 'actions/install-ps-modules/CiDependencyRoot.ps1'
    . $source
    . (Join-Path $root 'actions/cleanup-ps-modules/Remove-CiModules.ps1') -ModuleRoot unused
}

Describe 'Fresh-step isolated environment and independent ownership' {
    BeforeEach {
        $script:owner = New-CiDependencyRoot -Path (Join-Path $TestDrive "powershell-ci-modules-$([guid]::NewGuid().ToString('N'))")
        $script:originalPath = $env:PSModulePath
    }

    AfterEach { $env:PSModulePath = $script:originalPath }

    It 'restores the exact discovery path inside a fresh process before consumers' {
        $command = '. "{0}"; Initialize-CiDependencyEnvironment -ModuleRoot "{1}" -OwnerToken "{2}"; $env:PSModulePath' -f $source, $owner.Path, $owner.Token
        $result = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -Command $command
        $LASTEXITCODE | Should -Be 0
        $result | Should -BeExactly (Get-CiIsolatedModulePath -ModuleRoot $owner.Path)
    }

    It 'refuses cleanup when the marker token differs from the independently retained token' {
        $record = @{ Path = $owner.Path; Token = '00000000000000000000000000000000' }
        $record | ConvertTo-Json | Set-Content "$($owner.Path)/.powershell-ci-dependencies.json"
        { Remove-CiOwnedModuleRoot -Path $owner.Path -OwnerToken $owner.Token } | Should -Throw '*ownership changed*'
        Test-Path $owner.Path | Should -BeTrue
    }

    It 'refuses cleanup without an independently retained owner token' {
        { Remove-CiOwnedModuleRoot -Path $owner.Path -OwnerToken '' } | Should -Throw '*owner token*'
        Test-Path $owner.Path | Should -BeTrue
    }

    It 'removes the owned root only after validating the independently retained token' {
        Remove-CiOwnedModuleRoot -Path $owner.Path -OwnerToken $owner.Token
        Test-Path $owner.Path | Should -BeFalse
    }

    It 'rejects a changed marker before changing discovery' {
        $record = @{ Path = $owner.Path; Token = '00000000000000000000000000000000' }
        $record | ConvertTo-Json | Set-Content "$($owner.Path)/.powershell-ci-dependencies.json"
        { Initialize-CiDependencyEnvironment -ModuleRoot $owner.Path -OwnerToken $owner.Token } | Should -Throw '*ownership changed*'
        $env:PSModulePath | Should -BeExactly $originalPath
    }

    It 'rejects an ambient module already imported before an isolated consumer' {
        Mock Get-Module { @{ Name = 'Ambient'; ModuleBase = '/ambient/Module' } }
        { Initialize-CiDependencyEnvironment -ModuleRoot $owner.Path -OwnerToken $owner.Token } | Should -Throw '*outside isolation*'
    }
}
