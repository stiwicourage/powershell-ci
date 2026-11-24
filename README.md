# powershell-ci

[![Tag](https://img.shields.io/github/v/tag/stiwicourage/powershell-ci)](https://github.com/stiwicourage/powershell-ci/tags)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/17041/badge)](https://www.bestpractices.dev/projects/17041)

Shared GitHub Actions for the PowerShell projects (NovaModuleTools, GerberCore, Gerber, KeepAChangelog, SemanticRelease, PSModuleUpdate, Gerber.AzureDevOps). The goal is one place to fix CI so projects stop drifting apart.

## Contents

- [What is in this repository](#what-is-in-this-repository)
- [Reference](#reference)
- [Contributing and support](#contributing-and-support)
- [Using it](#using-it)
- [Using it securely](#using-it-securely)
- [What stays in each project](#what-stays-in-each-project)
- [Opt-in isolated dependencies](#opt-in-isolated-dependencies)
- [Releasing](#releasing)
- [Verify a release](#verify-a-release)

## What is in this repository

### Reusable workflows

| Path | Purpose |
| --- | --- |
| `.github/workflows/tests.yml` | Reusable test, coverage and CodeScene workflow |
| `.github/workflows/publish.yml` | Reusable Nova build, release and prerelease publish workflow |
| `.github/workflows/dependency-review.yml` | Reusable dependency review |
| `.github/workflows/codeql.yml` | Reusable CodeQL analysis |
| `.github/workflows/powershell-analyzer.yml` | Reusable PSScriptAnalyzer with SARIF upload |

### Composite actions

| Path | Purpose |
| --- | --- |
| `actions/check-coverage` | CodeScene coverage gates |
| `actions/check-unreleased-entries` | Fail when a changelog file has no entries under `[Unreleased]`, which would stop the release |
| `actions/codescene-analysis` | Upload coverage and trigger a CodeScene analysis (bundles the scripts) |
| `actions/install-ps-modules` | Install PowerShell modules, registering PSGallery when the runner lacks it |
| `actions/script-analyzer` | Run PSScriptAnalyzer over the project; local wrappers call the same script via a sibling `powershell-ci` checkout or `POWERSHELL_CI_PATH` |
| `actions/nova-test` | Build, run `Invoke-NovaTest` and optionally `Test-NovaBuild`, and collect NUnit and coverage artifacts |
| `actions/create-verified-commit` | Verified release/prerelease commit |
| `actions/update-git-ref` | Move a branch to a commit |
| `actions/create-annotated-tag` | Annotated release tag |
| `actions/create-github-release` | GitHub release for a tag, with text from a notes file or `Version <tag> has been released.`, and optional `assets` |
| `actions/ensure-psresource-repository` | Register the PSResource repository |

### Other files

| Path | Purpose |
| --- | --- |
| `examples/` | Thin caller workflows and the Dependabot config to copy into a project |
| `scripts/Move-ReleaseNotes.ps1` | Release helper that moves `[Unreleased]` in `CHANGELOG.md` and `RELEASE_NOTE.md` into the released version |
| `CHANGELOG.md` / `RELEASE_NOTE.md` | Full change history / caller-facing release notes (Keep a Changelog) |

The actions were copied unchanged from NovaModuleTools; they were byte-identical in all six projects that had them.

## Reference

The inputs, defaults and outputs of every reusable workflow are declared in the `on.workflow_call` block of its file in `.github/workflows/`, and those of every action in `actions/<name>/action.yml`; each input has a `description`. The sections below explain the behavior that needs more than a description.

## Contributing and support

- Contribution process and requirements: [CONTRIBUTING.md](CONTRIBUTING.md)
- Report bugs and request features: [issues](https://github.com/stiwicourage/powershell-ci/issues/new/choose)
- Report vulnerabilities privately: [SECURITY.md](SECURITY.md)
- Community expectations: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- License: [MIT](LICENSE)

## Using it

A project keeps only a thin caller workflow that owns triggers, permissions and inputs. See `examples/`. Reference a released tag:

```yaml
jobs:
  tests:
    uses: stiwicourage/powershell-ci/.github/workflows/tests.yml@0.4.0
    secrets: inherit
```

Callers must grant the permissions the reusable workflow needs (`publish.yml` needs `contents: write` and `actions: write`).

### Dependabot

Every consumer project also copies `examples/dependabot.yml` to `.github/dependabot.yml`, so Dependabot proposes new powershell-ci tags as one grouped weekly pull request. The config excludes powershell-ci from Dependabot's default 3-day cooldown, so a new tag is proposed on the next run. Pin released tags, not `@develop`, so Dependabot can update them. The full onboarding checklist is in `.github/instructions/consumer-onboarding.instructions.md`.

### Changelog check

`tests.yml` fails pull requests into the release branch (`release-branch`, default `main`) when a file in `changelog-files` has no entries under `[Unreleased]`, so the problem is found before the release instead of when it runs.

### What a publish does

On the release branch `publish.yml` moves `[Unreleased]` in `CHANGELOG.md` and, when present, `RELEASE_NOTE.md` into the released version, creates the release commit and annotated tag, and then creates a GitHub release for that tag. The GitHub release text is the released `RELEASE_NOTE.md` section; projects without `RELEASE_NOTE.md` (or with an empty section) get `Version <version> has been released.`

## Using it securely

Read [Using powershell-ci securely](docs/USING-SECURELY.md): pin tags or SHAs, grant least-privilege permissions and pass credentials only as secrets. Start with [Getting started](docs/GETTING-STARTED.md). Verify a release as described in [Verify a release](#verify-a-release).

## What stays in each project

The workflows install modules with the bundled `actions/install-ps-modules` (`install-modules` input; set `install-command` only to override it).

### Tests

- The default `test-command` is empty, which runs the shared `script-analyzer` gate (`script-analyzer-enabled`) and then the shared `nova-test` action (`Invoke-NovaBuild`, `Invoke-NovaTest` and, unless `build-validation: false`, `Test-NovaBuild`).
- Set `test-command` only to replace that action.
- For publish the default `test-command` is `Invoke-NovaTest`; override it for project-specific checks, such as `Test-NovaBuild`.
- CodeScene upload and analysis use the bundled `actions/codescene-analysis`; set `codescene-analysis-command` only to override it with a project script.

### Project-owned files

- Project-specific scripts, for example `Invoke-SemanticReleaseCI.ps1` or PSModuleUpdate's lane/gate scripts, remain in their repositories.
- Platform matrices such as GerberCore's native-credential matrix are also project-owned.

### Test isolation

`test-isolation` controls where the shared `nova-test` action runs the Nova test commands.

- `session` (default) runs `Invoke-NovaTest` and `Test-NovaBuild` in the runner session, as before.
- `process` runs each command in its own fresh PowerShell process with the same dependency root, Pester version, NovaModuleTools and freshly built module. Use it when the project under test is a module that the test tooling also loads, such as NovaModuleTools itself.

A failing unit run stops before `Test-NovaBuild`.

### Known follow-up

`Invoke-NovaModuleToolsCI.ps1` and the CodeScene helper scripts still differ between projects. Consolidating them into this repository is the next step; until then they are the main source of drift.

## Opt-in isolated dependencies

Existing callers retain `dependency-mode: legacy`, CurrentUser installation, repository behavior, custom commands and all previous inputs. No global installation is performed when `dependency-mode: isolated` is selected.

| Reusable input | Default | Behavior |
| --- | --- | --- |
| `dependency-mode` (tests/publish) | `legacy` | `isolated` saves dependencies into an owned temporary root |
| `pester-required-version` (tests/publish) | empty | Exact isolated Pester version; tests import it before Nova |

### Which modules are installed

The installer combines module names with string/object `Manifest.RequiredModules` from `project.json`.

- Isolated mode preserves `RequiredVersion`, `ModuleVersion` (minimum), `MinimumVersion` and `MaximumVersion`, intersects repeated constraints and rejects conflicts before downloading.
- It always requires PSResourceGet 1.2.0; consumers should request their exact Pester version, for example 5.7.1.
- Add project-specific build tools, such as `Microsoft.PowerShell.PlatyPS`, through `install-modules` or the project requirements rather than changing shared defaults.

### Module discovery

`actions/install-ps-modules` exposes `module-root` and `module-path`, empty in legacy mode. In isolated mode it writes the validated module discovery path to `GITHUB_ENV`.

- Fresh `pwsh` processes prepend ambient discovery directories at startup, so the shared PowerShell steps/actions reapply an ownership-validated bootstrap before consuming modules.
- Custom child processes must also dot-source `$env:POWERSHELL_CI_BOOTSTRAP` and call `Initialize-CiDependencyEnvironment` before imports. The installer does this in its fresh-process import probe before publishing outputs.
- Discovery then contains only owned modules and native `PSHOME/Modules`.
- Native PowerShellGet 2.2.5 and PackageManagement 1.4.8.1 are required; runners missing them fail closed.
- Dependency import paths and runtime versions are recorded in the owned root. Nova tests with an exact Pester request also write `artifacts/runtime-evidence.json` (or the selected output directory).

### Repository, ownership and cleanup

- Isolated mode requires the official PSGallery v2 endpoint.
- Existing registrations and trust are not changed. A temporary default registration is removed only while its source and Untrusted policy still match.
- Download/import failures remove the newly owned root. Temporary parents are resolved to physical paths before creating the marker.
- Cleanup compares the marker with an independently retained token; altered ownership fails closed.
- The reusable workflows run ownership-validated `actions/cleanup-ps-modules` under `always()`, after artifacts/consumers.

### Custom commands

Custom `install-command` remains supported in legacy mode but cannot be combined with isolated mode: a custom installer cannot establish the shared ownership contract. Existing test/build overrides remain supported. Source coverage, thresholds and exclusions remain the consumer project's responsibility.

### Script analyzer

The existing shared analyzer remains authoritative: it fails on every returned finding, including Information, and excludes only `PSAvoidUsingWriteHost` by default. Its existing `analysis-paths`, `exclude-rules` and `required-version` inputs remain unchanged.

- The optional `severity` action input (reusable tests input `script-analyzer-severity`) limits the gate to the listed severities, for example `Error Warning ParseError`; empty keeps failing on every severity. Consumer projects should leave it empty and fix findings instead; the input exists for temporary, explicitly accepted exceptions.
- In isolated tests, the existing `script-analyzer-required-version` also pins the saved analyzer dependency. The analyzer imports that owned version by its exact path, even when a newer saved version exists; no CurrentUser fallback is used.

### Nova orchestration

Nova orchestration preserves `build,unit,integration` output, forwards exclusions to both test phases, and snapshots unit coverage so integration cannot overwrite the collected JaCoCo report, including when the output is `artifacts` itself.

### Pinned actions

The reusable `tests.yml` and `publish.yml` check out their own commit (`job.workflow_repository` at `job.workflow_sha`) into `.powershell-ci` and run the actions from there (`./.powershell-ci/actions/<name>`). A caller that pins `@0.4.0` therefore always runs the 0.4.0 actions; there are no internal `@develop` or tag references to maintain. The checkout is added to the project's `.git/info/exclude` so it never ends up in release commits.

## Releasing

Versions follow Semantic Versioning with immutable tags **without a `v` prefix** (`0.1.0`, `0.2.0`, ...). While the workflows are being validated they are `0.x`. To cut a release:

1. Merge to `main` using Conventional Commits (`feat:`, `fix:`, `feat!:`).
2. `.github/workflows/release.yml` runs on every push to `main` (or manually).
   - It uses [SemanticRelease](https://github.com/stiwicourage/SemanticRelease) to infer the next version from the commits since the last tag and writes it to `version.json`. It stops if there are no new commits or the tag exists.
   - `scripts/Move-ReleaseNotes.ps1` then uses [KeepAChangelog](https://www.powershellgallery.com/packages/KeepAChangelog) to move `[Unreleased]` in `CHANGELOG.md` and `RELEASE_NOTE.md` into a dated `[<version>]` section; the release stops if either section is empty.
   - Otherwise it creates a verified `chore(release): <version>` commit on `main`, tags that commit with the released `CHANGELOG.md` section as the tag message and creates the GitHub release with the released `RELEASE_NOTE.md` section as its text.
3. The same workflow then resets `develop` to the release commit and sets `version.json` to the next preview version (for example `0.1.1-preview`). Like the Nova publish flow, this force-updates `develop`, so keep unmerged work on feature branches.

Before the release commit, `scripts/Set-InternalActionRefs.ps1` pins every `stiwicourage/powershell-ci/...` reference in `examples/` to the version being released, so the examples always show the newest tag without a follow-up pull request.

Contributors add every caller-visible change under `[Unreleased]` in `CHANGELOG.md` (full history) and `RELEASE_NOTE.md` (caller summary) in the same pull request; see `.github/instructions/release-policy.instructions.md`.

The repository's own checks live in `.github/workflows/ci.yml` (Pester on all three operating systems, actionlint, Keep a Changelog validation of both files and, for pull requests into `main`, entries under `[Unreleased]`); the other workflows are reusable (`workflow_call`) and only run when a project calls them.

Callers pin the tag, for example `@0.4.0`; Dependabot's `github-actions` ecosystem then proposes new tags. Create `1.0.0` only once the inputs and behavior are considered stable.

## Verify a release

Every GitHub release of powershell-ci contains `powershell-ci-<version>.zip` and a keyless Sigstore bundle signed by the release workflow:

```bash
cosign verify-blob \
  --bundle powershell-ci-<version>.zip.sigstore.json \
  --certificate-identity-regexp '^https://github.com/stiwicourage/powershell-ci/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  powershell-ci-<version>.zip
```
