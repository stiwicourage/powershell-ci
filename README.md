# powershell-ci

Shared GitHub Actions for the PowerShell projects (NovaModuleTools, GerberCore,
Gerber, KeepAChangelog, SemanticRelease, PSModuleUpdate, Gerber.AzureDevOps).
The goal is one place to fix CI so projects stop drifting apart.

## Contents

| Path | Purpose |
| --- | --- |
| `actions/check-coverage` | CodeScene coverage gates |
| `actions/create-verified-commit` | Verified release/prerelease commit |
| `actions/update-git-ref` | Move a branch to a commit |
| `actions/create-annotated-tag` | Annotated release tag |
| `actions/ensure-psresource-repository` | Register the PSResource repository |
| `.github/workflows/tests.yml` | Reusable test, coverage and CodeScene workflow |
| `.github/workflows/publish.yml` | Reusable Nova build, release and prerelease publish workflow |
| `.github/workflows/dependency-review.yml` | Reusable dependency review |
| `.github/workflows/codeql.yml` | Reusable CodeQL analysis |
| `.github/workflows/powershell-analyzer.yml` | Reusable PSScriptAnalyzer with SARIF upload |
| `examples/` | Thin caller workflows to copy into a project |

The actions were copied unchanged from NovaModuleTools; they were byte-identical
in all six projects that had them.

## Using it

A project keeps only a thin caller workflow that owns triggers, permissions and
inputs. See `examples/`. Reference a released tag:

```yaml
jobs:
  tests:
    uses: stiwicourage/powershell-ci/.github/workflows/tests.yml@v1
    secrets: inherit
```

Callers must grant the permissions the reusable workflow needs
(`publish.yml` needs `contents: write` and `actions: write`).

## What stays in each project

The workflows run project-owned scripts through the `install-command`,
`test-command` and `codescene-analysis-command` inputs, so the defaults match the
current Nova layout (`./scripts/build/ci/...`). Project-specific scripts, for
example `Invoke-SemanticReleaseCI.ps1` or PSModuleUpdate's lane/gate scripts,
remain in their repositories. Platform matrices such as GerberCore's
native-credential matrix are also project-owned.

## Known follow-up

`Install-CiPowerShellModules.ps1`, `Invoke-NovaModuleToolsCI.ps1` and the
CodeScene helper scripts still differ between projects. Consolidating them into
this repository is the next step; until then they are the main source of drift.

## Releasing

Callers pin `@v1`. Because the workflows reference the actions as
`stiwicourage/powershell-ci/actions/<name>@v1`, create the `v1` tag (and move it
for compatible fixes) before the first caller uses a workflow. Use immutable
`v1.x.y` tags for exact pinning.
