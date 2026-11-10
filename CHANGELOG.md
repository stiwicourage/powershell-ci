# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Shared composite actions copied from NovaModuleTools: `check-coverage`, `create-verified-commit`, `update-git-ref`, `create-annotated-tag` and `ensure-psresource-repository`.
- Reusable workflows for tests with CodeScene, module publishing, dependency review, CodeQL and PSScriptAnalyzer.
- Example caller workflows for projects.
- Own `ci.yml` (Pester on Linux, Windows and macOS plus actionlint) and `release.yml`, which on `main` pins the internal references to the version in `CHANGELOG.md`, creates a verified release commit and annotated tag with the shared actions, and creates the GitHub release.
