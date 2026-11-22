# Changelog

All notable changes to this project will be documented in this file and **UNRELEASED** changes will be included in the next **stable** release!

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A repository test that fails when a tracked text file does not end with exactly one newline.

### Changed

- `examples/dependabot.yml` now excludes `stiwicourage/powershell-ci*` from Dependabot's default 3-day cooldown, so new powershell-ci tags are proposed on the next scheduled run instead of after 3 days.
- The consumer onboarding instructions and the README now tell consumer projects not to narrow the ScriptAnalyzer gate with `script-analyzer-severity` or a local severity filter, and to fix findings instead.

### Deprecated

### Removed

### Fixed

- `publish.yml` and `release.yml` no longer leave an extra blank line at the end of `CHANGELOG.md` and `RELEASE_NOTE.md` in the release commit. KeepAChangelog 0.3.0 and earlier write one, so the workflows now trim the files to exactly one trailing newline after moving `[Unreleased]`.
- Removed the extra blank line at the end of `CHANGELOG.md` and `RELEASE_NOTE.md` left by the 0.5.0 release.

### Security

## [0.5.0] - 2026-11-21

### Added

- `RELEASE_NOTE.md` with consumer-facing release notes for every released version.
- Contributor and agent guidance for changelog and release-note maintenance: `.github/copilot-instructions.md`, `AGENTS.md`, the `release-policy` instructions, the `release-and-changelog` skill, the `prepare-release` prompt and a pull request template.
- The repository CI now validates `CHANGELOG.md` and `RELEASE_NOTE.md` with `Test-KeepAChangelogFile` on every pull request and `develop` push.
- The reusable `publish.yml` workflow now creates a GitHub release for every stable release tag it creates.
    - The release text is the released version's `RELEASE_NOTE.md` section. When the project has no `RELEASE_NOTE.md`, or the section is empty, the text is `Version <version> has been released.`
    - Callers need no new inputs; the existing `contents: write` permission is enough.
- `examples/dependabot.yml`, a Dependabot config that consumer projects copy to `.github/dependabot.yml`. It checks the `github-actions` ecosystem weekly and groups all `stiwicourage/powershell-ci` references into one `chore` pull request.
- `consumer-onboarding` instructions that make pinned release tags and the Dependabot config part of every new consumer setup. `README.md` and the agent index point to them.
- New `create-github-release` action that creates a GitHub release for an existing tag from a notes file, with the same default text and prerelease detection for versions containing `-`. `release.yml` uses it too.

### Changed

- GitHub releases of `powershell-ci` now use the released version's `RELEASE_NOTE.md` section as the release text instead of GitHub's generated notes.
- The annotated release tag message now contains the released version's `CHANGELOG.md` section instead of only the version number.
- `release.yml` now stops before creating any release commit, tag or GitHub release when `CHANGELOG.md` or `RELEASE_NOTE.md` has no entries under `[Unreleased]`.
- `publish.yml` no longer requires `RELEASE_NOTE.md`; projects without it are released with only `CHANGELOG.md` moved.
- `tests.yml` and `publish.yml` now run the powershell-ci actions from the same commit as the called workflow. Each job checks out `job.workflow_repository` at `job.workflow_sha` into `.powershell-ci` (excluded from the project's Git changes) instead of referencing `stiwicourage/powershell-ci/actions/<name>@develop`. A caller pinned to a tag no longer picks up unreleased action changes from `develop`.
- `release.yml` pins every powershell-ci reference in `examples/` to the version being released, in the release commit. `scripts/Set-InternalActionRefs.ps1` now targets `examples/` by default.
- The examples and the `README.md` usage example now reference `0.4.0`.

### Fixed

- `release.yml` now moves the `[Unreleased]` sections of `CHANGELOG.md` and `RELEASE_NOTE.md` into a dated version section with KeepAChangelog before creating the release commit. Releases `0.1.0` to `0.4.0` left every entry under `[Unreleased]` without a version or date.
- `CHANGELOG.md` was reconstructed from the Git history so each released version (`0.1.0` to `0.4.0`) lists its actual changes and release date.

## [0.4.0] - 2026-11-21

### Added

- `script-analyzer-severity` input for the reusable `tests.yml` workflow and `severity` input for the `script-analyzer` action.
    - They limit the analyzer gate to the listed severities, for example `Error Warning`.
    - The default (empty) keeps failing on every severity, including `Information`.

## [0.3.0] - 2026-11-20

### Added

- `test-isolation` input for the reusable `tests.yml` workflow and the `nova-test` action.
    - `process` runs `Invoke-NovaTest` and `Test-NovaBuild` each in a fresh PowerShell process through the new `Invoke-NovaTestProcess.ps1`.
    - The default `session` keeps the previous single-session behavior.
    - `examples/Tests.yml` documents the new input.

## [0.2.1] - 2026-11-20

### Fixed

- `release.yml` no longer fails while preparing `develop` for the next prerelease after a release. It now calls `Get-SemanticReleaseNextVersion` with `-Preview` instead of the unsupported `-PreviewRelease` parameter.

## [0.2.0] - 2026-11-15

### Added

- Opt-in `dependency-mode` input for the reusable `tests.yml` and `publish.yml` workflows and the `install-ps-modules` action.
    - `legacy` (default) keeps the CurrentUser installation, repository behavior, custom `install-command` and all previous inputs.
    - `isolated` saves the dependencies into an owned, disposable temporary root and never installs globally. It honours `RequiredVersion`, `ModuleVersion`, `MinimumVersion` and `MaximumVersion` from `project.json` `Manifest.RequiredModules`, intersects repeated constraints and rejects conflicts before downloading.
    - Isolated mode requires PSResourceGet 1.2.0, the official PSGallery v2 endpoint and native PowerShellGet 2.2.5 / PackageManagement 1.4.8.1, and fails closed when they are missing. Existing repository registrations and trust are not changed.
    - Combining `dependency-mode: isolated` with `install-command` fails the workflow, because a custom installer cannot establish the ownership contract.
- `pester-required-version` input for `tests.yml`, `publish.yml`, `install-ps-modules` and `nova-test`. The exact Pester version is imported before Nova, and `nova-test` writes the PowerShell and module versions to `artifacts/runtime-evidence.json`.
- `script-analyzer-required-version` is now also saved exactly in isolated mode, and the analyzer imports that owned version by its exact path without a CurrentUser fallback.
- `module-root` and `module-path` outputs for `install-ps-modules`. Isolated mode publishes `POWERSHELL_CI_BOOTSTRAP`, which shared steps and custom child processes dot-source before importing modules.
- `cleanup-ps-modules` action. The reusable workflows run it under `always()` and it only removes an ownership-validated module root.

### Changed

- The `install-ps-modules` logic moved from the action YAML into `Install-CiModules.ps1`. Legacy-mode installation behaves as before.
- `ensure-psresource-repository` and the PowerShell steps in the reusable workflows reapply the isolated module bootstrap before using modules.

### Fixed

- `nova-test` now snapshots the unit-test coverage before `Test-NovaBuild` runs, so build-validation tests no longer overwrite the collected JaCoCo report, including when the output directory is `artifacts`.

## [0.1.1] - 2026-11-11

### Changed

- The caller workflows in `examples/` now reference the released `0.1.0` tag instead of `@develop`.
- `examples/Tests.yml` now enables `script-analyzer-enabled`.

## [0.1.0] - 2026-11-10

### Added

- Reusable workflows for PowerShell module projects:
    - `tests.yml` runs the shared PSScriptAnalyzer gate, `Invoke-NovaBuild`, `Invoke-NovaTest` and optionally `Test-NovaBuild`, validates changelog files with `Test-KeepAChangelogFile`, uploads artifacts and checks and uploads coverage. `test-command` and `codescene-analysis-command` replace the default steps.
    - `publish.yml` builds and tests the module, releases from `main` with `Invoke-NovaRelease`, moves `[Unreleased]` in `CHANGELOG.md` and `RELEASE_NOTE.md`, creates a verified release commit and annotated tag, and publishes prereleases from `develop`.
    - `dependency-review.yml`, `codeql.yml` and `powershell-analyzer.yml` (PSScriptAnalyzer with SARIF upload).
- Composite actions copied unchanged from NovaModuleTools: `check-coverage`, `create-verified-commit`, `update-git-ref`, `create-annotated-tag` and `ensure-psresource-repository`.
- `install-ps-modules` action, which installs the listed modules plus `project.json` `Manifest.RequiredModules` and registers PSGallery when the runner lacks it.
- `script-analyzer` action with `Invoke-ScriptAnalyzerCI.ps1`. It fails on every finding and excludes only `PSAvoidUsingWriteHost` by default. Local wrappers can call the same script through a sibling `powershell-ci` checkout or `POWERSHELL_CI_PATH`.
- `nova-test` action, which builds the module, runs the Nova tests and collects NUnit and coverage artifacts.
- `codescene-analysis` action, which bundles the coverage upload and analysis scripts.
- Example caller workflows `examples/Tests.yml`, `examples/Publish.yml` and `examples/Security.yml`.
- `scripts/Set-InternalActionRefs.ps1` to pin the internal action references to a release ref.
- Repository CI in `ci.yml` (Pester on Linux, Windows and macOS plus actionlint) and `release.yml`, which uses SemanticRelease to infer the next version from Conventional Commits into `version.json`, creates a verified release commit, annotated tag and GitHub release on `main`, and prepares `develop` for the next preview version.

[Unreleased]: https://github.com/stiwicourage/powershell-ci/compare/0.5.0...HEAD
[0.5.0]: https://github.com/stiwicourage/powershell-ci/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/stiwicourage/powershell-ci/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/stiwicourage/powershell-ci/compare/0.2.1...0.3.0
[0.2.1]: https://github.com/stiwicourage/powershell-ci/compare/0.2.0...0.2.1
[0.2.0]: https://github.com/stiwicourage/powershell-ci/compare/0.1.1...0.2.0
[0.1.1]: https://github.com/stiwicourage/powershell-ci/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/stiwicourage/powershell-ci/releases/tag/0.1.0
