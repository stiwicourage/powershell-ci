---
applyTo: "actions/**,.github/workflows/**,scripts/**,examples/**,README.md,CHANGELOG.md,RELEASE_NOTE.md,version.json,.github/PULL_REQUEST_TEMPLATE.md"
---

# powershell-ci release policy

## Scope

Use this file for any change to the shared actions, reusable workflows, scripts, examples, versioning, `CHANGELOG.md`, `RELEASE_NOTE.md` or the release automation. Load the `release-and-changelog` skill for the detailed how-to.

## Changelog and release-note rules

- Every change that alters behavior, inputs, outputs, defaults, required permissions, dependencies or documented usage of `actions/`, `.github/workflows/`, `scripts/` or `examples/` adds an entry under `## [Unreleased]` in `CHANGELOG.md` in the same change.
- `CHANGELOG.md` is the exhaustive history for maintainers. Name the affected workflow, action, input or script and describe the final behavior.
- `RELEASE_NOTE.md` is the concise summary for callers of the reusable workflows and actions: new, changed or removed inputs, outputs and defaults, permission or dependency requirements, migration steps and fixes callers can notice. Do not copy the `CHANGELOG.md` text verbatim.
- Use only the official Keep a Changelog section types `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` and `Security`. Keep all six headings under `## [Unreleased]`, even when empty. Never add custom headings such as `Documentation`.
- `RELEASE_NOTE.md` placeholder: when `## [Unreleased]` has no caller-facing entries, `### Added` contains exactly `No public API or workflow changes in this release. Internal maintenance only.` and nothing else. Remove the placeholder as soon as a real entry exists in any section.
- While a feature is unreleased, update its existing `Added` entry instead of adding a `Changed` entry for internal iteration. `Changed` describes differences from the last release.
- Test-only and agent-guidance-only changes need no entry unless they change how contributors build, test or release.
- `CHANGELOG.md` keeps the compare-link footer; `RELEASE_NOTE.md` never has link footers.

## Release automation rules

- Never move `[Unreleased]` into a version section, add release dates or edit `version.json` by hand. `.github/workflows/release.yml` does this on `main`:
    1. SemanticRelease infers the version from the Conventional Commits since the last tag and writes `version.json`.
    2. `scripts/Move-ReleaseNotes.ps1` moves `[Unreleased]` in both files into `## [<version>] - <date>` with KeepAChangelog and stops the release when either section is empty.
    3. `scripts/Set-InternalActionRefs.ps1` pins every powershell-ci reference in `examples/` to the new version. The verified `chore(release): <version>` commit contains `version.json`, `CHANGELOG.md`, `RELEASE_NOTE.md` and `examples/`.
    4. The annotated tag message is the released `CHANGELOG.md` section; the GitHub release text is the released `RELEASE_NOTE.md` section.
    5. `develop` is reset to the release commit and bumped to the next preview version.
- Tags have no `v` prefix (`0.4.0`). Commit types decide the version: `fix:` patch, `feat:` minor, `!` or an uppercase `BREAKING CHANGE:` footer major.
- Edit released sections only to correct factual errors. Do not rewrite history to match new behavior.
- Read `release.yml`, `scripts/Move-ReleaseNotes.ps1` and `tests/workflows/ReleaseContracts.Tests.ps1` before changing release behavior, and change them together.

## Agent safety

- Do not push, tag, create GitHub releases or edit existing releases unless the user explicitly requests that exact action.
- `release.yml` force-updates `develop`; do not change branch mutation or tag creation without targeted tests and a `CHANGELOG.md` entry.

## Verification

- Validate both files: `pwsh -NoProfile -c "Import-Module KeepAChangelog; './CHANGELOG.md', './RELEASE_NOTE.md' | ForEach-Object { Test-KeepAChangelogFile -Path `$_ -ThrowOnError }"`.
- Run the Pester suite: `pwsh -NoProfile -c "Invoke-Pester -Path ./tests"`.
- Re-read `.github/PULL_REQUEST_TEMPLATE.md` before preparing a release or review summary.
