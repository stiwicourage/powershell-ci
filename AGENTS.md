# powershell-ci agent instructions

Read `.github/copilot-instructions.md` first; it is the index for this repository.

- Rules for changelog, release notes and releases: `.github/instructions/release-policy.instructions.md`.
- How to write entries and prepare a release: `.github/skills/release-and-changelog/SKILL.md` and `.github/prompts/prepare-release.prompt.md`.
- Setting up a project to call powershell-ci (callers, pinned tags and Dependabot): `.github/instructions/consumer-onboarding.instructions.md`.
- Every caller-visible change under `actions/`, `.github/workflows/`, `scripts/` or `examples/` updates `[Unreleased]` in both `CHANGELOG.md` and `RELEASE_NOTE.md`. Never move `[Unreleased]` or bump `version.json` by hand.
