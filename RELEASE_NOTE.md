# Release notes

This file summarizes the release notes for powershell-ci. **UNRELEASED** changes will be included in the next **stable** release!

## [Unreleased]

### Added

- `tests.yml` now fails a pull request into `main` when a file in `changelog-files` has no entries under `[Unreleased]`, because the release stops on an empty section. Add the entries in the pull request. Set `release-branch` if your release branch is not `main`.
- powershell-ci now has an MIT `LICENSE`. Dependency Review in projects that pin this release no longer reports an unknown license for the reusable workflows.

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.6.0] - 2026-11-22

### Changed

- `examples/dependabot.yml` now exempts powershell-ci from Dependabot's default 3-day cooldown. Add the same `cooldown.exclude` entry to an existing `.github/dependabot.yml` to get new powershell-ci tags proposed right away.

### Fixed

- `publish.yml` no longer leaves an extra blank line at the end of `CHANGELOG.md` and `RELEASE_NOTE.md` in the release commit, which made trailing-newline checks fail after a release.

## [0.5.0] - 2026-11-21

### Added

- `publish.yml` now creates a GitHub release when it tags a stable release. The text is that version's `RELEASE_NOTE.md` section, or `Version <version> has been released.` when the project has no release notes. No caller changes are needed beyond pinning the new tag.
- New `create-github-release` action for creating a GitHub release from a notes file.
- `examples/dependabot.yml`: copy it to `.github/dependabot.yml` so Dependabot proposes new powershell-ci tags in one weekly pull request.

### Changed

- GitHub releases of `powershell-ci` now show these release notes, and annotated tags contain the matching `CHANGELOG.md` section.
- `publish.yml` no longer fails when a project has no `RELEASE_NOTE.md`.
- `tests.yml` and `publish.yml` now always run the actions from the powershell-ci version you pin, instead of the latest `develop` actions. No caller changes are needed; the jobs add a `.powershell-ci` checkout that is excluded from your Git changes.
- The files in `examples/` always reference the newest powershell-ci release.

## [0.4.0] - 2026-11-21

### Added

- `tests.yml` accepts `script-analyzer-severity` and the `script-analyzer` action accepts `severity`, so the analyzer gate can fail only on selected severities such as `Error Warning`. Empty (default) still fails on every finding.

## [0.3.0] - 2026-11-20

### Added

- `tests.yml` and the `nova-test` action accept `test-isolation`. Set it to `process` to run `Invoke-NovaTest` and `Test-NovaBuild` in separate PowerShell processes; the default `session` keeps the previous behavior.

## [0.2.1] - 2026-11-20

### Added

No public API or workflow changes in this release. Internal maintenance only.

## [0.2.0] - 2026-11-15

### Added

- `tests.yml`, `publish.yml` and `install-ps-modules` accept `dependency-mode: isolated`, which installs dependencies into a disposable, owned module root instead of CurrentUser. The default `legacy` keeps the previous behavior; `isolated` cannot be combined with `install-command`.
- `pester-required-version` pins an exact Pester version for `tests.yml`, `publish.yml`, `install-ps-modules` and `nova-test`.
- `install-ps-modules` outputs `module-root` and `module-path`, and the new `cleanup-ps-modules` action removes an isolated module root.

### Fixed

- `nova-test` keeps the unit-test coverage report when `Test-NovaBuild` runs afterwards.

## [0.1.1] - 2026-11-11

### Changed

- The example caller workflows in `examples/` pin `@0.1.0` instead of `@develop`, and `examples/Tests.yml` enables the shared analyzer.

## [0.1.0] - 2026-11-10

### Added

- First release with reusable `tests.yml`, `publish.yml`, `dependency-review.yml`, `codeql.yml` and `powershell-analyzer.yml` workflows.
- Shared actions `install-ps-modules`, `script-analyzer`, `nova-test`, `codescene-analysis`, `check-coverage`, `create-verified-commit`, `update-git-ref`, `create-annotated-tag` and `ensure-psresource-repository`.
- Example caller workflows in `examples/`.
