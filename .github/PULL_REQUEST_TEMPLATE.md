## Summary

- What changed?
- Why was this change needed?
- Link the issue, discussion, or follow-up work (for example `Closes #123`).

## Affected area

- [ ] Reusable workflows (`.github/workflows/tests.yml`, `publish.yml`, `codeql.yml`, `dependency-review.yml`, `powershell-analyzer.yml`)
- [ ] Shared actions (`actions/`)
- [ ] Example caller workflows (`examples/`)
- [ ] Repository CI or release automation (`ci.yml`, `release.yml`, `scripts/`)
- [ ] Documentation (`README.md`, agent guidance)
- [ ] Other

## Validation

- [ ] `Invoke-Pester -Path ./tests`
- [ ] `Test-KeepAChangelogFile` on `CHANGELOG.md` and `RELEASE_NOTE.md`
- [ ] actionlint (CI)
- [ ] Docs only; executable validation not needed

Validation notes:

```text
Paste the relevant commands and results here. Explain skipped checks.
```

## Changelog and release notes

- [ ] `CHANGELOG.md` `[Unreleased]` describes the final behavior of this change
- [ ] `RELEASE_NOTE.md` `[Unreleased]` summarizes caller-facing changes, or keeps the internal-maintenance placeholder
- [ ] `README.md` and `examples/` updated if usage changed
- [ ] No changelog entry needed (tests or agent guidance only)

## Compatibility and risk

- [ ] No breaking change for callers
- [ ] Breaking change (commit uses `!` or a `BREAKING CHANGE:` footer)
- [ ] Changes release or branch-mutation behavior

Risk, rollout, or rollback notes:

```text
Describe caller impact, migration steps, or follow-up work.
```
