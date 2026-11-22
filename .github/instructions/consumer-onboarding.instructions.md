---
applyTo: "examples/**,README.md,.github/workflows/tests.yml,.github/workflows/publish.yml,.github/workflows/codeql.yml,.github/workflows/dependency-review.yml,.github/workflows/powershell-analyzer.yml"
---

# Onboarding a project to powershell-ci

## Scope

Use this file when a project is set up to call powershell-ci, when an existing project's caller workflows are changed, and when `examples/` or the `README.md` usage sections change. Agents working in a consumer repository should read this file from the powershell-ci repository (`stiwicourage/powershell-ci`) before writing caller workflows.

## Required setup in every consumer project

1. Copy the thin callers from `examples/` (`Tests.yml`, `Publish.yml`, `Security.yml`) into the project's `.github/workflows/` and adjust only triggers, permissions and inputs.
2. Pin every `stiwicourage/powershell-ci/...@<ref>` reference to a released tag such as `@0.4.0`. Do not use `@develop` or a branch name outside short-lived testing; Dependabot only updates release tags.
3. Copy `examples/dependabot.yml` to `.github/dependabot.yml` in the same change. It enables the `github-actions` ecosystem, groups all powershell-ci references into one weekly pull request and uses the `chore` commit prefix. Its `cooldown.exclude` entry for `stiwicourage/powershell-ci*` skips Dependabot's default 3-day cooldown so new powershell-ci tags are proposed on the next run; keep it. If the project already has a `dependabot.yml`, add or merge the `github-actions` entry, the `powershell-ci` group and the `cooldown` entry instead of replacing other ecosystems.
4. Dependabot opens pull requests against the repository's default branch. For projects that release from `main` and integrate on `develop`, keep `develop` as the default branch or set `target-branch: develop`.
5. Grant the permissions the reusable workflows need (`publish.yml`: `contents: write` and `actions: write`).
6. Add `CHANGELOG.md` (and `RELEASE_NOTE.md` for the GitHub release text) in Keep a Changelog format.
7. Do not set `script-analyzer-severity`, `exclude-rules` or a severity filter in a local analyzer wrapper. Keep the default gate, which fails on every finding including `Information` and excludes only `PSAvoidUsingWriteHost`, and fix findings in the code instead. A local `scripts/build/Invoke-ScriptAnalyzerCI.ps1` should delegate to `actions/script-analyzer/Invoke-ScriptAnalyzerCI.ps1` with the same inputs as CI.

## Rules for changes in this repository

- `examples/dependabot.yml` and the pinned tags in `examples/` are part of the consumer contract; `tests/workflows/ConsumerContracts.Tests.ps1` guards them. `release.yml` pins the examples to each new release, so do not bump them by hand.
- Reusable workflows run their actions from their own commit: check out `job.workflow_repository` at `job.workflow_sha` into `.powershell-ci`, add it to `.git/info/exclude` and use `./.powershell-ci/actions/<name>`. Never reference `stiwicourage/powershell-ci/actions/<name>@develop` or a tag; `tests/workflows/InternalActionRefs.Tests.ps1` guards this.
- When onboarding requirements change, update this file, `README.md` and `examples/` together, with `[Unreleased]` entries according to `release-policy.instructions.md`.
