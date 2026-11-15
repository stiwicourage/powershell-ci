BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    . (Join-Path $root 'actions/install-ps-modules/Install-CiModules.ps1')
}

Describe 'Unchanged temporary Gallery registration' {
    BeforeEach {
        $script:gallery = @{
            SourceLocation = 'https://www.powershellgallery.com/api/v2'
            PublishLocation = 'https://www.powershellgallery.com/api/v2/package/'
            PackageManagementProvider = 'NuGet'
            InstallationPolicy = 'Untrusted'
        }
        Mock Get-PSRepository { $gallery }
        Mock Register-CiDefaultGallery {}
        Mock Unregister-PSRepository {}
        Mock Get-PSRepository { $null } -ParameterFilter { $ErrorAction -eq 'SilentlyContinue' }
    }

    It 'refuses to remove a temporary registration whose <Property> changed' -ForEach @(
        @{ Property = 'PublishLocation' }
        @{ Property = 'PackageManagementProvider' }
    ) {
        $registered = Open-CiGallery
        $gallery[$Property] = 'substituted-registration-value'
        { Close-CiGallery -Registered $registered } | Should -Throw '*changed*'
        Should -Invoke Unregister-PSRepository -Times 0
    }

    It 'retains the download failure when restoring Gallery state also fails' {
        Mock Save-Module { throw 'primary download failure' }
        Mock Close-CiGallery { throw 'secondary registration failure' }
        { Save-CiRequiredModule -Requirements @(@{ Name = 'Fixture' }) -ModuleRoot $TestDrive -AllowPrerelease $false } |
            Should -Throw '*primary download failure*secondary registration failure*'
    }
}
