# Contributing to powershell-ci

powershell-ci is a set of reusable GitHub Actions workflows and composite actions
for PowerShell projects. Thank you for helping improve it.

## Get it

Reference a released tag from a caller workflow, for example
`stiwicourage/powershell-ci/.github/workflows/tests.yml@<tag>`. The tags and their
signed archives are listed on the
[releases page](https://github.com/stiwicourage/powershell-ci/releases). The
[README](README.md) describes every workflow and action.

## Give feedback

- Bugs and enhancement requests: [open an issue](https://github.com/stiwicourage/powershell-ci/issues/new/choose).
  Name the workflow or action, the tag you use and what you expected.
- Security problems: follow [SECURITY.md](SECURITY.md). Do not open a public issue.
- Issues are answered in English and normally within 14 days.

## Contribute a change

1. Fork the repository and branch from `develop`.
2. Make the change, with tests in `tests/` for new or changed behavior.
3. Open a pull request into `develop` and fill in the pull request template.
   A maintainer reviews it; CI must pass before it is merged.

## Requirements for acceptable contributions

- Use Conventional Commits (`fix:`, `feat:`, `chore:`); the type decides the next version.
- Run `Invoke-Pester -Path ./tests` and make it pass. New behavior needs a test
  that fails without the change.
- Add an entry under `[Unreleased]` in `CHANGELOG.md` and `RELEASE_NOTE.md`
  (Keep a Changelog sections), and validate both with `Test-KeepAChangelogFile`.
  Never edit `version.json` or move `[Unreleased]` by hand.
- Pin every external action to a full commit SHA with a version comment, and keep
  workflow permissions read-only at the top level.
- PowerShell must pass PSScriptAnalyzer without findings.
- CodeScene checks code health and coverage on pull requests. Maintainers configure the `CS_ACCESS_TOKEN` secret and the `CS_URL` and `CS_PROJECT_ID` variables; run `./scripts/Invoke-PesterCoverage.ps1` to produce `artifacts/coverage.xml` locally.
- If a ruleset requires pull requests on `main` or `develop`, maintainers create a GitHub App with Contents write access, add it to the ruleset bypass list, and set the `RELEASE_APP_ID` variable and `RELEASE_APP_PRIVATE_KEY` secret so `release.yml` can update the branches.
- Follow the [code of conduct](CODE_OF_CONDUCT.md).

Contributions are released under the [MIT license](LICENSE).
