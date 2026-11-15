[CmdletBinding()]
param(
    [string[]]$Modules = @(),
    [string]$ProjectFile = 'project.json',
    [string]$Repository = 'PSGallery',
    [bool]$AllowPrerelease = $true,
    [ValidateSet('legacy', 'isolated')][string]$DependencyMode = 'legacy',
    [string]$PesterRequiredVersion = '',
    [string]$ScriptAnalyzerRequiredVersion = ''
)

. (Join-Path $PSScriptRoot 'CiDependencyRoot.ps1')
. (Join-Path $PSScriptRoot 'CiModuleRequirements.ps1')

function Open-CiGallery {
    $repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($repository) {
        $null = Assert-CiGallery
        return $false
    }
    Register-CiDefaultGallery
    return Get-CiGallerySnapshot
}

function Register-CiDefaultGallery {
    Register-PSRepository -Default -ErrorAction Stop
}

function Assert-CiGallery {
    $repository = Get-PSRepository -Name PSGallery -ErrorAction Stop
    if ($repository.SourceLocation.TrimEnd('/') -cne 'https://www.powershellgallery.com/api/v2') {
        throw 'CI dependencies require the official PSGallery repository.'
    }
    return $repository
}

function Close-CiGallery {
    param([object]$Registered)
    if (-not $Registered) {
        return
    }
    $repository = Assert-CiGallery
    if ($repository.InstallationPolicy -cne 'Untrusted') {
        throw 'The temporary PSGallery registration changed; refusing to remove it.'
    }
    Assert-CiGallerySnapshot -Registered $Registered
    Unregister-PSRepository -Name PSGallery -ErrorAction Stop
}

function Get-CiGallerySnapshot {
    $repository = Assert-CiGallery
    $snapshot = @{}
    foreach ($property in @('SourceLocation', 'PublishLocation', 'ScriptSourceLocation', 'ScriptPublishLocation', 'InstallationPolicy', 'PackageManagementProvider')) {
        $snapshot[$property] = $repository.$property
    }
    return $snapshot
}

function Assert-CiGallerySnapshot {
    param([object]$Registered)
    if ($Registered -isnot [hashtable]) {
        return
    }
    $actual = Get-CiGallerySnapshot
    foreach ($property in $Registered.Keys) {
        if ($Registered[$property] -cne $actual[$property]) {
            throw 'The temporary PSGallery registration changed; refusing to remove it.'
        }
    }
}

function Save-CiRequiredModule {
    param([object[]]$Requirements, [string]$ModuleRoot, [bool]$AllowPrerelease)
    $registered = Open-CiGallery
    $failure = $null
    try {
        $null = Assert-CiGallery
        Save-CiModuleBatch -Requirements $Requirements -ModuleRoot $ModuleRoot -AllowPrerelease $AllowPrerelease
    } catch {
        $failure = $_
        throw
    } finally {
        Close-CiGalleryAfterSave -Registered $registered -Failure $failure
    }
}

function Save-CiModuleBatch {
    param([object[]]$Requirements, [string]$ModuleRoot, [bool]$AllowPrerelease)
    foreach ($requirement in $Requirements) {
        $parameters = Get-CiSaveParameter -Requirement $requirement -ModuleRoot $ModuleRoot -AllowPrerelease $AllowPrerelease
        $null = Save-Module @parameters
    }
}

function Close-CiGalleryAfterSave {
    param([object]$Registered, [System.Management.Automation.ErrorRecord]$Failure)
    try {
        Close-CiGallery -Registered $Registered
    } catch {
        if ($Failure) {
            throw [AggregateException]::new('Download and Gallery restoration both failed.', @($Failure.Exception, $_.Exception))
        }
        throw
    }
}

function Get-CiSaveParameter {
    param([hashtable]$Requirement, [string]$ModuleRoot, [bool]$AllowPrerelease)
    $parameters = @{
        Name = $Requirement.Name
        Path = $ModuleRoot
        Repository = 'PSGallery'
        Force = $true
        ErrorAction = 'Stop'
        AllowPrerelease = $AllowPrerelease
    }
    Copy-CiProviderVersionConstraint -Requirement $Requirement -Parameters $parameters
    return $parameters
}

function Invoke-CiIsolatedInstall {
    param([object[]]$Requirements, [bool]$AllowPrerelease)
    $base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
    $owner = New-CiDependencyRoot -Path (Join-Path $base "powershell-ci-modules-$([guid]::NewGuid().ToString('N'))")
    try {
        Save-CiRequiredModule -Requirements $Requirements -ModuleRoot $owner.Path -AllowPrerelease $AllowPrerelease
        Assert-CiSavedModuleClosure -Owner $owner -Requirements $Requirements
        Publish-CiDependencyEnvironment -Owner $owner
        return $owner
    } catch {
        Undo-CiFailedInstall -Owner $owner -Failure $_
    }
}

function Undo-CiFailedInstall {
    param([hashtable]$Owner, [System.Management.Automation.ErrorRecord]$Failure)
    try {
        Remove-CiDependencyRoot -Owner $Owner
    } catch {
        throw [AggregateException]::new('Provisioning and cleanup both failed.', @($Failure.Exception, $_.Exception))
    }
    throw $Failure
}

function Assert-CiSavedModuleClosure {
    param([hashtable]$Owner, [object[]]$Requirements)
    $path = Join-Path $Owner.Path '.requirements.json'
    ConvertTo-Json -InputObject @($Requirements) -Depth 5 | Set-Content -LiteralPath $path
    $probe = Join-Path $PSScriptRoot 'CiDependencyProbe.ps1'
    & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $probe -ModuleRoot $Owner.Path -OwnerToken $Owner.Token
    if ($LASTEXITCODE -ne 0) {
        throw 'Isolated dependency closure validation failed.'
    }
}

function Publish-CiDependencyEnvironment {
    param([hashtable]$Owner)
    $modulePath = Get-CiIsolatedModulePath -ModuleRoot $Owner.Path
    if ($env:GITHUB_ENV) {
        Add-Content -LiteralPath $env:GITHUB_ENV -Value @(
            "PSModulePath=$modulePath"
            "POWERSHELL_CI_MODULE_ROOT=$($Owner.Path)"
            "POWERSHELL_CI_OWNER_TOKEN=$($Owner.Token)"
            "POWERSHELL_CI_BOOTSTRAP=$(Join-Path $PSScriptRoot 'CiDependencyRoot.ps1')"
        )
    }
    if ($env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @("module-root=$($Owner.Path)", "module-path=$modulePath")
    }
}

function Initialize-CiLegacyRepository {
    param([string]$Repository)
    if (-not (Get-PSRepository -Name $Repository -ErrorAction SilentlyContinue)) {
        if ($Repository -ne 'PSGallery') {
            throw "PowerShell repository '$Repository' is not registered."
        }
        Register-PSRepository -Default
    }
    Set-PSRepository -Name $Repository -InstallationPolicy Trusted
}

function Install-CiLegacyModule {
    param([string[]]$Modules, [string]$ProjectFile, [string]$Repository, [bool]$AllowPrerelease)
    Initialize-CiLegacyRepository -Repository $Repository
    $names = @($Modules) + @(Get-CiProjectRequirement -ProjectFile $ProjectFile | ForEach-Object {
        if ($_ -is [string]) { $_ } else { $_.ModuleName }
    })
    foreach ($name in $names | Where-Object { $_ } | Select-Object -Unique) {
        Write-Output "Installing PowerShell module '$name'..."
        Install-Module -Name $name -Repository $Repository -Scope CurrentUser -Force -ErrorAction Stop -AllowPrerelease:$AllowPrerelease
        $installed = Get-InstalledModule -Name $name | Sort-Object Version -Descending | Select-Object -First 1
        Write-Output "Installed '$($installed.Name)' $($installed.Version) from '$($installed.Repository)'."
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($DependencyMode -eq 'legacy') {
        Install-CiLegacyModule -Modules $Modules -ProjectFile $ProjectFile -Repository $Repository -AllowPrerelease $AllowPrerelease
    } else {
        if ($Repository -ne 'PSGallery') { throw 'Isolated mode requires PSGallery.' }
        $requirements = @(Get-CiModuleRequirement -Modules $Modules -ProjectFile $ProjectFile -PesterRequiredVersion $PesterRequiredVersion -ScriptAnalyzerRequiredVersion $ScriptAnalyzerRequiredVersion)
        $null = Invoke-CiIsolatedInstall -Requirements $requirements -AllowPrerelease $AllowPrerelease
    }
}
