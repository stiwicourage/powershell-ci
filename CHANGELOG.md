# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Shared composite actions copied from NovaModuleTools: `check-coverage`, `create-verified-commit`, `update-git-ref`, `create-annotated-tag` and `ensure-psresource-repository`.
- Reusable workflows for tests with CodeScene, module publishing, dependency review, CodeQL and PSScriptAnalyzer.
- Example caller workflows for projects.
- Own `ci.yml` (Pester on Linux, Windows and macOS plus actionlint) and `release.yml`, which on `main` uses SemanticRelease to infer the next version from Conventional Commits (stored in `version.json`), pins the internal references, creates a verified release commit and annotated tag with the shared actions, creates the GitHub release, and prepares `develop` for the next prerelease (moving references and next preview version).
