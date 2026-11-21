---
applyTo: "examples/**,README.md,.github/workflows/tests.yml,.github/workflows/publish.yml,.github/workflows/codeql.yml,.github/workflows/dependency-review.yml,.github/workflows/powershell-analyzer.yml"
---

# Onboarding a project to powershell-ci

## Scope

Use this file when a project is set up to call powershell-ci, when an existing project's caller workflows are changed, and when `examples/` or the `README.md` usage sections change. Agents working in a consumer repository should read this file from the powershell-ci repository (`stiwicourage/powershell-ci`) before writing caller workflows.

## Required setup in every consumer project

1. Copy the thin callers from `examples/` (`Tests.yml`, `Publish.yml`, `Security.yml`) into the project's `.github/workflows/` and adjust only triggers, permissions and inputs.
2. Pin every `stiwicourage/powershell-ci/...@<ref>` reference to a released tag such as `@0.4.0`. Do not use `@develop` or a branch name outside short-lived testing; Dependabot only updates release tags.
3. Copy `examples/dependabot.yml` to `.github/dependabot.yml` in the same change. It enables the `github-actions` ecosystem, groups all powershell-ci references into one weekly pull request and uses the `chore` commit prefix. If the project already has a `dependabot.yml`, add or merge the `github-actions` entry and the `powershell-ci` group instead of replacing other ecosystems.
4. Dependabot opens pull requests against the repository's default branch. For projects that release from `main` and integrate on `develop`, keep `develop` as the default branch or set `target-branch: develop`.
5. Grant the permissions the reusable workflows need (`publish.yml`: `contents: write` and `actions: write`).
6. Add `CHANGELOG.md` (and `RELEASE_NOTE.md` for the GitHub release text) in Keep a Changelog format.

## Rules for changes in this repository

- `examples/dependabot.yml` and the pinned tags in `examples/` are part of the consumer contract; `tests/workflows/ConsumerContracts.Tests.ps1` guards them.
- When onboarding requirements change, update this file, `README.md` and `examples/` together, with `[Unreleased]` entries according to `release-policy.instructions.md`.
