BeforeAll {
    $script:root = Split-Path -Parent $PSScriptRoot
    $script:textExtensions = @('.md', '.ps1', '.psm1', '.psd1', '.json', '.txt', '.yml', '.yaml', '.gitignore')
    function Test-SingleTrailingNewline {
        param([string]$Path)
        $content = [System.IO.File]::ReadAllText($Path)
        return $content.Length -eq 0 -or ($content -match '\n\z' -and $content -notmatch '\n\r?\n\z')
    }
}

Describe 'Repository text files' {
    It 'end with exactly one trailing newline and no blank lines at the bottom' {
        $files = @(git -C $root ls-files | Where-Object {
                $textExtensions -contains [System.IO.Path]::GetExtension($_) -and (Test-Path -LiteralPath (Join-Path $root $_))
            })
        $violations = @($files | Where-Object { -not (Test-SingleTrailingNewline -Path (Join-Path $root $_)) })

        $files | Should -Not -BeNullOrEmpty
        $violations | Should -BeNullOrEmpty -Because "violations: $($violations -join ', ')"
    }
}
