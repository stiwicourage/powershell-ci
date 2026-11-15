function Import-CiPester {
    param([string]$RequiredVersion)
    if (-not $RequiredVersion) {
        return
    }
    Remove-Module Pester -Force -ErrorAction SilentlyContinue
    Import-Module Pester -RequiredVersion $RequiredVersion -ErrorAction Stop
}

function Write-CiRuntimeEvidence {
    param([string]$OutputDirectory)
    $evidence = @{
        PowerShell = [string]$PSVersionTable.PSVersion
        Modules = @(Get-Module | Select-Object Name, @{ Name = 'Version'; Expression = { [string]$_.Version } }, Path, ModuleBase)
    }

    $path = Join-Path $OutputDirectory 'runtime-evidence.json'
    $evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
}

function Assert-CiPesterVersion {
    param([string]$RequiredVersion)
    $pester = Get-Module Pester
    if (-not $pester -or [string]$pester.Version -ne $RequiredVersion) {
        throw "Nova did not retain requested Pester $RequiredVersion."
    }
}
