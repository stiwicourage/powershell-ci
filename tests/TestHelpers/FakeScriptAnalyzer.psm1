$script:fixture = Get-Content (Join-Path $PSScriptRoot 'fixture.json') -Raw | ConvertFrom-Json

<#
.SYNOPSIS
Returns configured findings for the isolated analyzer process fixture.
#>
function Invoke-ScriptAnalyzer {
    param([string]$Path, [string[]]$ExcludeRule)
    if ($script:fixture.ThrowOnAnalyze) {
        throw 'Fake analyzer failure.'
    }
    foreach ($finding in $script:fixture.Findings) {
        if ($finding.RuleName -notin $ExcludeRule) {
            ConvertTo-FakeAnalyzerFinding -Finding $finding -Path $Path
        }
    }
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
