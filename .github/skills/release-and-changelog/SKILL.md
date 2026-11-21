---
name: release-and-changelog
description: Guidance for powershell-ci semantic versioning, CHANGELOG.md and RELEASE_NOTE.md entries, and the release.yml flow. Use whenever a change touches actions, reusable workflows, scripts, examples or release automation.
---

# Skill: release and changelog management

## When to use

Use this skill when you change `actions/`, `.github/workflows/`, `scripts/` or `examples/`, prepare a release, or edit `CHANGELOG.md`, `RELEASE_NOTE.md`, `version.json` or `release.yml`. The rules live in `.github/instructions/release-policy.instructions.md`; this skill explains how to apply them.

## Relevant files

- `CHANGELOG.md` and `RELEASE_NOTE.md`
- `version.json` (written only by SemanticRelease)
- `.github/workflows/release.yml` and `.github/workflows/ci.yml`
- `scripts/Move-ReleaseNotes.ps1`
- `tests/workflows/ReleaseContracts.Tests.ps1` and `tests/scripts/Move-ReleaseNotes.Tests.ps1`
- `.github/PULL_REQUEST_TEMPLATE.md`

## Writing entries

1. Decide the section from the impact on the last release: new input, output, action or workflow `Added`; changed default or behavior `Changed`; planned removal `Deprecated`; removal `Removed`; bug fix `Fixed`; vulnerability fix `Security`.
2. Add the `CHANGELOG.md` entry under that section in `## [Unreleased]`. Name the workflow, action, input or script, describe the final behavior and use indented sub-bullets for details such as defaults and compatibility.
3. Decide whether callers of the reusable workflows or actions notice the change. If they do, add a one or two sentence `RELEASE_NOTE.md` entry that says what to set or expect, and remove the placeholder line. If they do not, keep or restore the placeholder under `### Added`.
4. When one change spans several types, add one entry per type. When the type differs between files, use the implementation impact in `CHANGELOG.md` and the caller impact in `RELEASE_NOTE.md`, and mention the difference in the PR description.
5. When the change touches documented usage, update `README.md` and the `examples/` callers in the same change.

Example for a new reusable input:

```markdown
<!-- CHANGELOG.md -->
### Added

- `artifact-retention-days` input for the reusable `tests.yml` workflow.
    - It is forwarded to `actions/upload-artifact`; the default (empty) keeps the repository retention.

<!-- RELEASE_NOTE.md -->
### Added

- `tests.yml` accepts `artifact-retention-days` to shorten how long CI artifacts are kept.
```

## Releasing

- Merge `develop` to `main` with Conventional Commits; `release.yml` does the rest (see the release policy). Do not move `[Unreleased]`, add dates or bump `version.json` yourself.
- Before merging, make sure `[Unreleased]` in both files describes the final behavior. The release stops when either section is empty, so internal-only releases keep the `RELEASE_NOTE.md` placeholder.
- After a release, `[Unreleased]` in both files is empty with all six headings. Add the placeholder to `RELEASE_NOTE.md` again with the next internal-only change.

## Common pitfalls

- Logging internal iteration history instead of the final unreleased behavior.
- Custom headings such as `Documentation` or removing empty official headings from `[Unreleased]`.
- Copying maintainer detail into `RELEASE_NOTE.md`, or leaving the placeholder next to real entries.
- Adding compare links to `RELEASE_NOTE.md`, or editing the `CHANGELOG.md` footer by hand.
- Editing released sections to describe later behavior.

## Verification

- Validate both files with `Test-KeepAChangelogFile` (the CI `changelog` job does the same).
- Run `tests/workflows/ReleaseContracts.Tests.ps1` and `tests/scripts/Move-ReleaseNotes.Tests.ps1` when release behavior changes, and the full `./tests` suite before handoff.
