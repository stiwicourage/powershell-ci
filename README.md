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

`test-isolation` controls where the shared `nova-test` action runs the Nova
test commands. The default `session` runs `Invoke-NovaTest` and
`Test-NovaBuild` in the runner session, as before. `process` runs each command
in its own fresh PowerShell process with the same dependency root, Pester
version, NovaModuleTools and freshly built module. Use `process` when the
project under test is a module that the test tooling also loads, such as
NovaModuleTools itself. A failing unit run stops before `Test-NovaBuild`.

## Known follow-up

`Invoke-NovaModuleToolsCI.ps1` and the
CodeScene helper scripts still differ between projects. Consolidating them into
this repository is the next step; until then they are the main source of drift.

## Opt-in isolated dependencies

Existing callers retain `dependency-mode: legacy`, CurrentUser installation,
repository behavior, custom commands and all previous inputs. No global
installation is performed when `dependency-mode: isolated` is selected.

| Reusable input | Default | Behavior |
| --- | --- | --- |
| `dependency-mode` (tests/publish) | `legacy` | `isolated` saves dependencies into an owned temporary root |
| `pester-required-version` (tests/publish) | empty | Exact isolated Pester version; tests import it before Nova |

The installer combines module names with string/object `Manifest.RequiredModules`
from `project.json`. Isolated mode preserves `RequiredVersion`, `ModuleVersion`
(minimum), `MinimumVersion` and `MaximumVersion`, intersects repeated constraints
and rejects conflicts before downloading. It always requires PSResourceGet
1.2.0; consumers should request their exact Pester version, for example 5.7.1.
Add project-specific build tools, such as `Microsoft.PowerShell.PlatyPS`, through
`install-modules` or the project requirements rather than changing shared defaults.

`actions/install-ps-modules` exposes `module-root` and `module-path`, empty in
legacy mode. In isolated mode it writes the validated module discovery path to
`GITHUB_ENV`. Fresh `pwsh` processes prepend ambient discovery directories at
startup, so the shared PowerShell steps/actions reapply an ownership-validated
bootstrap before consuming modules. Custom child processes must also dot-source
`$env:POWERSHELL_CI_BOOTSTRAP` and call `Initialize-CiDependencyEnvironment`
before imports. The installer does this in its fresh-process import probe before
publishing outputs. Discovery then contains only owned modules and native
`PSHOME/Modules`. Native PowerShellGet 2.2.5 and
PackageManagement 1.4.8.1 are required; runners missing them fail closed.
Dependency import paths and runtime versions are recorded in the owned root.
Nova tests with an exact Pester request also write
`artifacts/runtime-evidence.json` (or the selected output directory).

Isolated mode requires the official PSGallery v2 endpoint. Existing registrations
and trust are not changed. A temporary default registration is removed only
while its source and Untrusted policy still match. Download/import failures
remove the newly owned root. Temporary parents are resolved to physical paths
before creating the marker. Cleanup compares the marker with an independently
retained token; altered ownership fails closed. The reusable workflows run ownership-validated
`actions/cleanup-ps-modules` under `always()`, after artifacts/consumers.

Custom `install-command` remains supported in legacy mode but cannot be combined
with isolated mode: a custom installer cannot establish the shared ownership
contract. Existing test/build overrides remain supported. Source coverage,
thresholds and exclusions remain the consumer project's responsibility.

The existing shared analyzer remains authoritative: it fails on every returned
finding, including Information, and excludes only `PSAvoidUsingWriteHost` by
default. Its existing `analysis-paths`, `exclude-rules` and `required-version`
inputs remain unchanged. The optional `severity` action input (reusable tests
input `script-analyzer-severity`) limits the gate to the listed severities, for
example `Error Warning ParseError`; empty keeps failing on every severity.
In isolated tests, the existing `script-analyzer-required-version` also pins the
saved analyzer dependency. The analyzer imports that owned version by its exact
path, even when a newer saved version exists; no CurrentUser fallback is used.

Nova orchestration preserves `build,unit,integration` output, forwards exclusions
to both test phases, and snapshots unit coverage so integration cannot overwrite
the collected JaCoCo report, including when the output is `artifacts` itself.

During coordinated testing references remain `@develop`. This does not freeze
transitive actions in previously released workflows. A real release and stable
internal/caller references require a separate user-owned release checkpoint.
`scripts/Set-InternalActionRefs.ps1` is the existing reference-update helper;
this migration neither invokes it nor changes `version.json`.

## Releasing

Versions follow Semantic Versioning with immutable tags **without a `v`
prefix** (`0.1.0`, `0.2.0`, ...). While the workflows are being validated they
are `0.x` and callers reference `@develop`. The workflows reference the
actions as `stiwicourage/powershell-ci/actions/<name>@<ref>`. To cut a release:

1. Merge to `main` using Conventional Commits (`feat:`, `fix:`, `feat!:`).
2. `.github/workflows/release.yml` runs on every push to `main` (or manually).
   It uses [SemanticRelease](https://github.com/stiwicourage/SemanticRelease)
   to infer the next version from the commits since the last tag and writes it
   to `version.json`. It stops if there are no new commits or the tag exists.
   Otherwise it creates a verified `chore(release): <version>` commit on
   `main`, tags that commit and creates the GitHub release with generated
   notes.
3. The same workflow then resets `develop` to the release commit and sets
   `version.json` to the next preview version (for example `0.1.1-preview`).
   Like the Nova publish flow, this force-updates `develop`, so keep unmerged
   work on feature branches.

The default `GITHUB_TOKEN` cannot change files under `.github/workflows/`, so
the release does not rewrite the internal `@develop` references to the release
tag. Callers that need an immutable reference should pin the release tag or
commit SHA of the workflow they call.

The repository's own checks live in `.github/workflows/ci.yml` (Pester on all
three operating systems and actionlint); the other workflows are reusable
(`workflow_call`) and only run when a project calls them.

Callers pin the tag, for example `@0.1.0`; Dependabot's `github-actions`
ecosystem then proposes new tags. Create `1.0.0` only once the inputs and
behavior are considered stable.
