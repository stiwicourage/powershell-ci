function New-CiDependencyRoot {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        throw "Dependency root already exists: '$Path'."
    }
    Assert-CiDependencyRootName -Path $Path
    $Path = Resolve-CiDependencyRootPath -Path $Path
    if (-not $PSCmdlet.ShouldProcess($Path, 'Create owned CI dependency root')) {
        return
    }
    $directory = New-Item -ItemType Directory -Path $Path -ErrorAction Stop
    return Write-CiDependencyOwner -Path $directory.FullName
}

function Resolve-CiDependencyRootPath {
    param([string]$Path)
    $absolute = [IO.Path]::GetFullPath($Path)
    $directory = Get-Item -LiteralPath (Split-Path -Parent $absolute) -Force -ErrorAction Stop
    $parent = Resolve-CiDependencyDirectory -Directory $directory
    return Join-Path $parent (Split-Path -Leaf $absolute)
}

function Resolve-CiDependencyDirectory {
    param([IO.DirectoryInfo]$Directory)
    if (-not $Directory.Parent) {
        return $Directory.FullName
    }
    $parent = Resolve-CiDependencyDirectory -Directory $Directory.Parent
    $item = Get-Item -LiteralPath (Join-Path $parent $Directory.Name) -Force -ErrorAction Stop
    if ($item.LinkType) {
        return Resolve-CiDependencyDirectory -Directory $item.ResolveLinkTarget($true)
    }
    return $item.FullName
}

function Assert-CiDependencyRootName {
    param([string]$Path)
    if ((Split-Path -Leaf $Path) -notlike 'powershell-ci-modules-*') {
        throw 'Invalid dependency root name; expected powershell-ci-modules- prefix.'
    }
}

function Write-CiDependencyOwner {
    param([string]$Path)
    $owner = @{ Path = $Path; Token = [guid]::NewGuid().ToString('N') }
    $owner | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Path '.powershell-ci-dependencies.json')
    return $owner
}

function Assert-CiDependencyLink {
    param([string]$Path)
    $directory = Get-Item -LiteralPath $Path -ErrorAction Stop
    while ($directory) {
        if ($directory.LinkType) {
            throw 'A dependency root cannot traverse a filesystem link.'
        }
        $directory = $directory.Parent
    }
}

function Get-CiDependencyOwner {
    param([Parameter(Mandatory)][string]$Path)
    Assert-CiDependencyRootName -Path $Path
    Assert-CiDependencyLink -Path $Path
    $directory = Get-Item -LiteralPath $Path -ErrorAction Stop
    $marker = Join-Path $directory.FullName '.powershell-ci-dependencies.json'
    $owner = Get-Content -LiteralPath $marker -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    if ($owner.Path -cne $directory.FullName -or $owner.Token -notmatch '^[a-f0-9]{32}$') {
        throw 'Invalid dependency ownership record.'
    }
    return $owner
}

function Remove-CiDependencyRoot {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable]$Owner)
    $actual = Get-CiDependencyOwner -Path $Owner.Path
    if ($actual.Token -cne $Owner.Token) {
        throw 'Dependency ownership changed; refusing cleanup.'
    }
    if ($PSCmdlet.ShouldProcess($Owner.Path, 'Remove owned disposable CI dependencies')) {
        Remove-Item -LiteralPath $Owner.Path -Recurse -Force -ErrorAction Stop
    }
}

function Get-CiIsolatedModulePath {
    param([Parameter(Mandatory)][string]$ModuleRoot)
    $null = Get-CiDependencyOwner -Path $ModuleRoot
    return $ModuleRoot + [IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules')
}

function Assert-CiDependencyToken {
    param([hashtable]$Owner, [string]$OwnerToken)
    if (-not $OwnerToken) {
        throw 'An independently retained owner token is required.'
    }
    if ($Owner.Token -cne $OwnerToken) {
        throw 'Dependency ownership changed; refusing consumer execution or cleanup.'
    }
}

function Initialize-CiDependencyEnvironment {
    param(
        [string]$ModuleRoot = $env:POWERSHELL_CI_MODULE_ROOT,
        [string]$OwnerToken = $env:POWERSHELL_CI_OWNER_TOKEN
    )
    if (-not $ModuleRoot) {
        return
    }
    $owner = Get-CiDependencyOwner -Path $ModuleRoot
    Assert-CiDependencyToken -Owner $owner -OwnerToken $OwnerToken
    $env:PSModulePath = Get-CiIsolatedModulePath -ModuleRoot $ModuleRoot
    Assert-CiDependencyOrigin -ModuleRoot $ModuleRoot
}

function Assert-CiDependencyOrigin {
    param([string]$ModuleRoot)
    foreach ($module in Get-Module) {
        Assert-CiNativeProviderOrigin -Module $module
        $owned = $module.ModuleBase.StartsWith($ModuleRoot + [IO.Path]::DirectorySeparatorChar)
        $native = Test-CiNativeModulePath -Path $module.ModuleBase
        if (-not ($owned -or $native)) {
            throw "Dependency resolved outside isolation: $($module.Name)."
        }

    }
}

function Test-CiNativeModulePath {
    param([string]$Path)
    return $Path -eq $PSHOME -or $Path.StartsWith($PSHOME + [IO.Path]::DirectorySeparatorChar)
}

function Assert-CiNativeProviderOrigin {
    param([object]$Module)
    $versions = @{ PowerShellGet = '2.2.5'; PackageManagement = '1.4.8.1' }
    if (-not $versions.ContainsKey($Module.Name)) {
        return
    }
    $native = $Module.ModuleBase.StartsWith($PSHOME + [IO.Path]::DirectorySeparatorChar)
    if (-not $native -or [string]$Module.Version -ne $versions[$Module.Name]) {
        throw "Required native provider '$($Module.Name)' was shadowed or has the wrong version."
    }
}
