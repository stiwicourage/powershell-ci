# Changelog

All notable changes to this project will be documented in this file and **UNRELEASED** changes will be included in the next **stable** release!

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Shared composite actions copied from NovaModuleTools: `check-coverage`, `create-verified-commit`, `update-git-ref`, `create-annotated-tag` and `ensure-psresource-repository`.
- Reusable workflows for tests with CodeScene, module publishing, dependency review, CodeQL and PSScriptAnalyzer.
- Example caller workflows for projects.
- `script-analyzer-severity` input for the reusable tests workflow and `severity` input for the `script-analyzer` action. They limit the analyzer gate to the listed severities; the default (empty) keeps failing on every severity.
- `test-isolation` input for the reusable tests workflow and the `nova-test` action. `process` runs `Invoke-NovaTest` and `Test-NovaBuild` each in a fresh PowerShell process; the default `session` keeps the previous behavior.
- Own `ci.yml` (Pester on Linux, Windows and macOS plus actionlint) and `release.yml`, which on `main` uses SemanticRelease to infer the next version from Conventional Commits (stored in `version.json`), creates a verified release commit and annotated tag with the shared actions, creates the GitHub release, and prepares `develop` for the next prerelease (next preview version).

### Changed

### Deprecated

### Removed

### Fixed

### Security
