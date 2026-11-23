# Getting started

powershell-ci is not installed as a package. A project calls its reusable
workflows and actions from GitHub Actions.

## Install

1. Pick a released tag from the [releases page](https://github.com/stiwicourage/powershell-ci/releases).
2. Copy the caller workflows you need from [`examples/`](../examples/) into the
   project's `.github/workflows/`, and copy `examples/dependabot.yml` to
   `.github/dependabot.yml` so new tags are proposed automatically.

## Start

The caller workflow owns the triggers. Pushing to a branch or opening a pull
request starts it, and GitHub then runs powershell-ci's reusable workflow:

```yaml
jobs:
  tests:
    uses: stiwicourage/powershell-ci/.github/workflows/tests.yml@<tag>
    with:
      script-analyzer-enabled: true
    secrets: inherit
```

## Use

- `tests.yml` runs PSScriptAnalyzer, the Nova tests, coverage and changelog checks.
- `publish.yml` builds, tags and publishes a module from the release branch.
- Change behavior through the `with:` inputs; each input is described in the
  `on.workflow_call` block of the workflow file and in the
  [README](../README.md).
- Keep `[Unreleased]` in `CHANGELOG.md` filled before merging into the release
  branch; the pull request check fails when it is empty.

Read [Using powershell-ci securely](USING-SECURELY.md) before enabling publishing.
