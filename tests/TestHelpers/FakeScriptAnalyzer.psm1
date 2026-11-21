$script:fixture = Get-Content (Join-Path $PSScriptRoot 'fixture.json') -Raw | ConvertFrom-Json

<#
.SYNOPSIS
Returns configured findings for the isolated analyzer process fixture.
#>
function Invoke-ScriptAnalyzer {
    param([string]$Path, [string[]]$ExcludeRule, [string[]]$Severity)
    if ($script:fixture.ThrowOnAnalyze) {
        throw 'Fake analyzer failure.'
    }
    foreach ($finding in $script:fixture.Findings) {
        if (Test-FakeAnalyzerFindingSelected -Finding $finding -ExcludeRule $ExcludeRule -Severity $Severity) {
            ConvertTo-FakeAnalyzerFinding -Finding $finding -Path $Path
        }
    }
}

function Test-FakeAnalyzerFindingSelected {
    param([object]$Finding, [string[]]$ExcludeRule, [string[]]$Severity)
    if ($Finding.RuleName -in $ExcludeRule) {
        return $false
    }
    return -not $Severity -or $Finding.Severity -in $Severity
}

function ConvertTo-FakeAnalyzerFinding {
    param([object]$Finding, [string]$Path)
    $scriptPath = Join-Path $env:SCRIPTANALYZER_FAKE_REPOSITORY_ROOT $Finding.RelativePath
    if ($scriptPath -ne [IO.Path]::GetFullPath($Path)) {
        return
    }
    return [pscustomobject]@{
        Severity = $Finding.Severity
        RuleName = $Finding.RuleName
        ScriptPath = $scriptPath
        Line = [int]$Finding.Line
        Message = $Finding.Message
    }
}

Export-ModuleMember -Function Invoke-ScriptAnalyzer
