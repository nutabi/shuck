# Repository setup

One-time GitHub settings for `nutabi/shuck` that the owner applies by hand. Workflows cannot set them.

## Branch protection for `main` (ENG-001)

In **Settings → Rules → Rulesets**, create a branch ruleset:

| Setting | Value |
|---|---|
| Name | `main` |
| Enforcement status | Active |
| Target branches | Default branch |
| Restrict deletions | On |
| Require a pull request before merging | On. Required approvals: 0 (the owner is the only reviewer and cannot approve their own pull request). |
| Allowed merge methods | Squash only |
| Require status checks to pass | On. Add the check **Lint, build and test** (from `.github/workflows/ci.yml`). Turn on "Require branches to be up to date before merging". |
| Block force pushes | On |
| Bypass list | Empty, so the rules apply to the owner too |

The status check appears in the picker only after CI has run once, so push a first pull request before adding it.

In **Settings → General → Pull Requests**:

- Allow squash merging only, with the default commit message set to **Pull request title and description**, so the `[<task ID>] <deliverable>` title becomes the commit title on `main`.
- Turn on **Automatically delete head branches**.
- Turn on **Allow auto-merge**. Pull requests start as drafts and get auto-merge once their checks pass and code scanning is clean (D-49).

## Actions

In **Settings → Actions → General**:

- **Actions permissions:** allow actions created by GitHub only. The workflows use only `actions/*` and
  `github/codeql-action`, pinned to commit SHAs.
- **Workflow permissions:** read repository contents by default. The release workflow asks for write access itself.
- **Fork pull request workflows:** require approval for all outside collaborators.

## Code scanning

In **Settings → Code security → Code scanning**:

- **CodeQL analysis:** default setup off. `.github/workflows/codeql.yml` runs the scan instead, on the `xcode-27`
  runner, and uploads its results (D-50). GitHub rejects workflow results while default setup is on.
- GitHub Actions workflows are not scanned (owner choice, 2026-11-02).

Release secrets and the `release` environment are described in [releasing.md](releasing.md).
