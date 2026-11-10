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
| `actions/script-analyzer` | Run PSScriptAnalyzer over the project; local wrappers call the same script via a sibling `powershell-ci` checkout or `POWERSHELL_CI_PATH` |
| `actions/nova-test` | Build, run `Invoke-NovaTest` and optionally `Test-NovaBuild`, and collect NUnit and coverage artifacts |
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
default `test-command` is empty, which runs the shared `script-analyzer` gate
(`script-analyzer-enabled`) and then the shared `nova-test` action
(`Invoke-NovaBuild`, `Invoke-NovaTest` and, unless `build-validation: false`,
`Test-NovaBuild`). Set `test-command` only to replace that action. For publish
the default `test-command` is `Invoke-NovaTest`; override it for project-specific
checks, such as `Test-NovaBuild`. CodeScene upload and analysis
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

1. Move the finished entries in `CHANGELOG.md` under a version heading such
   as `## [0.1.0] - 2026-11-10` and merge to `main`.
2. `.github/workflows/release.yml` runs on every push to `main` (or manually).
   It reads the newest version heading from `CHANGELOG.md` and stops if that
   tag already exists. Otherwise it pins the internal references with
   `scripts/Set-InternalActionRefs.ps1`, creates a verified
   `chore(release): <version>` commit on `main`, tags that commit and creates
   the GitHub release from the changelog section.
3. Merge `main` back to `develop`. Run
   `./scripts/Set-InternalActionRefs.ps1 -Ref develop` and commit to return
   `develop` to the moving reference.

The repository's own checks live in `.github/workflows/ci.yml` (Pester on all
three operating systems and actionlint); the other workflows are reusable
(`workflow_call`) and only run when a project calls them.

Callers pin the tag, for example `@0.1.0`; Dependabot's `github-actions`
ecosystem then proposes new tags. Create `1.0.0` only once the inputs and
behavior are considered stable.
