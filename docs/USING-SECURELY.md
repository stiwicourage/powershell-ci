# Using powershell-ci securely

- **Pin** a released tag, or its commit SHA for the strictest setups. Never use
  `@develop`. Verify a release with the `cosign verify-blob` command in the
  [README](../README.md#verify-a-release).
- Grant only the **permissions** a caller job needs: `contents: read` for tests,
  and `contents: write` only for the publish job.
- Pass credentials such as `PSGALLERY_API` and `CS_ACCESS_TOKEN` only as
  repository **secrets**, never as inputs or in workflow files. Avoid
  `secrets: inherit` where the caller has secrets the workflow does not need.
- Do not run these workflows on untrusted pull request code with write
  permissions or secrets.
- Report vulnerabilities privately as described in [SECURITY.md](../SECURITY.md).
