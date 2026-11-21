# Prepare a powershell-ci release

> Invoke with `@.github/prompts/prepare-release.prompt.md`.

Prepare `CHANGELOG.md` and `RELEASE_NOTE.md` for the next release without pushing, tagging or creating GitHub releases.

## Required process

1. Load the `release-and-changelog` skill and read `.github/instructions/release-policy.instructions.md`. If either cannot be loaded, stop and report it.
2. Read `CHANGELOG.md`, `RELEASE_NOTE.md`, `version.json`, `README.md`, `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/release.yml`.
3. List the commits since the last tag (`git log --oneline "$(git describe --tags --abbrev=0)"..HEAD`) and compare them with `[Unreleased]` in both files. Add missing entries and correct entries that no longer describe the final behavior.
4. State the version SemanticRelease will produce from the commit types (`fix:` patch, `feat:` minor, `!` or `BREAKING CHANGE:` major). Do not edit `version.json` or move `[Unreleased]`; `release.yml` does both.
5. Apply the `RELEASE_NOTE.md` placeholder rule and keep all six official headings under `[Unreleased]` in both files.
6. Validate both files with `Test-KeepAChangelogFile` and run `Invoke-Pester -Path ./tests`.
7. Summarize the result with the structure of `.github/PULL_REQUEST_TEMPLATE.md`, writing `N/A` for sections that do not apply.

## Reminders

- Do not push, tag, merge to `main` or create or edit GitHub releases.
- Keep `CHANGELOG.md` exhaustive and `RELEASE_NOTE.md` caller-focused.
