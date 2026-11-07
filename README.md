# powershell-ci

Shared GitHub Actions for the PowerShell projects (NovaModuleTools, GerberCore,
Gerber, KeepAChangelog, SemanticRelease, PSModuleUpdate, Gerber.AzureDevOps).
The goal is one place to fix CI so projects stop drifting apart.

## Contents

| Path | Purpose |
| --- | --- |
| `actions/check-coverage` | CodeScene coverage gates |
| `actions/codescene-analysis` | Upload coverage and trigger a CodeScene analysis (bundles the scripts) |
| `actions/install-ps-modules` | Install PowerShell modules, registering PSGallery when the runner lacks it |
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
inputs. See `examples/`. Reference a released tag (or `@develop` while testing):

```yaml
jobs:
  tests:
    uses: stiwicourage/powershell-ci/.github/workflows/tests.yml@develop
    secrets: inherit
```

Callers must grant the permissions the reusable workflow needs
(`publish.yml` needs `contents: write` and `actions: write`).

## What stays in each project

The workflows install modules with the bundled `actions/install-ps-modules`
(`install-modules` input; set `install-command` only to override it). The
default `test-command` is `Invoke-NovaBuild; Invoke-NovaTest` for tests and
`Invoke-NovaTest` for publish; override it for project-specific checks, such as
a ScriptAnalyzer script or `Test-NovaBuild`. CodeScene upload and analysis
use the bundled `actions/codescene-analysis`; set `codescene-analysis-command`
only to override it with a project script. Project-specific scripts, for
example `Invoke-SemanticReleaseCI.ps1` or PSModuleUpdate's lane/gate scripts,
remain in their repositories. Platform matrices such as GerberCore's
native-credential matrix are also project-owned.

## Known follow-up

`Invoke-NovaModuleToolsCI.ps1` and the
CodeScene helper scripts still differ between projects. Consolidating them into
this repository is the next step; until then they are the main source of drift.

## Releasing

Versions follow Semantic Versioning with immutable tags **without a `v`
prefix** (`0.1.0`, `0.2.0`, ...). While the workflows are being validated they
are `0.x` and callers reference `@develop`. The workflows reference the
actions as `stiwicourage/powershell-ci/actions/<name>@<ref>`. To cut a release:

1. Run `./scripts/Set-InternalActionRefs.ps1 -Ref 0.1.0` to pin those
   references from `@develop` to the new tag.
2. Commit, then create the tag `0.1.0` on that commit.
3. Run `./scripts/Set-InternalActionRefs.ps1 -Ref develop` and commit to return
   `develop` to the moving reference.

Callers pin the tag, for example `@0.1.0`; Dependabot's `github-actions`
ecosystem then proposes new tags. Create `1.0.0` only once the inputs and
behavior are considered stable.
