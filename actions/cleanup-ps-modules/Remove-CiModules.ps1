[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$ModuleRoot, [string]$OwnerToken = $env:POWERSHELL_CI_OWNER_TOKEN)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../install-ps-modules/CiDependencyRoot.ps1')

function Remove-CiOwnedModuleRoot {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [string]$OwnerToken = $env:POWERSHELL_CI_OWNER_TOKEN)
    $owner = Get-CiDependencyOwner -Path $Path
    Assert-CiDependencyToken -Owner $owner -OwnerToken $OwnerToken
    if ($PSCmdlet.ShouldProcess($Path, 'Cleanup owned CI modules')) {
        Remove-CiDependencyRoot -Owner $owner -Confirm:$false
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Remove-CiOwnedModuleRoot -Path $ModuleRoot -OwnerToken $OwnerToken -WhatIf:$WhatIfPreference
}
