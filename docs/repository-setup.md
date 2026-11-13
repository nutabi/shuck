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

CI has a second job, **Engine on macOS 26**, which builds the engine package on a macOS 26 runner (NFR-COMP-001, D-06,
#126). It is not required yet, because a macOS 26 runner is a different image from the one the required check uses. Add
it to the required checks once it has passed on a few pull requests (D-133 planned this for M5). A pull request that
changes only documentation skips it, like the required check.

A pull request that changes only documentation skips **Lint, build and test**, and GitHub counts a skipped check as
passed (D-66). The **Code changes** job that decides this is not a required check: if it fails, the full check runs.

In **Settings → General → Pull Requests**:

- Allow squash merging only, with the default commit message set to **Pull request title and description**, so the `[<task ID>] <deliverable>` title becomes the commit title on `main`.
- Turn on **Automatically delete head branches**.
- Turn on **Allow auto-merge**. Pull requests get auto-merge when they open and merge once the required check passes (D-51).

## No code owners

Changes to `scripts/` and `.github/` follow the same rules as any other change and merge once CI passes (D-200), so
the repository has no `.github/CODEOWNERS`. Leave "Require review from Code Owners" off in the `main` ruleset.

## Release tags (#125)

The release workflow runs for any `v*` tag (`docs/releasing.md`). In **Settings → Rules → Rulesets**, create a tag
ruleset so only the owner can create one:

| Setting | Value |
|---|---|
| Name | `release tags` |
| Enforcement status | Active |
| Target tags | Include by pattern: `v*` |
| Restrict creations | On |
| Restrict updates | On |
| Restrict deletions | On |
| Bypass list | Repository admin, so the owner can still tag a release |

## Actions

In **Settings → Actions → General**:

- **Actions permissions:** allow actions created by GitHub only. The workflows use only `actions/*` and
  `github/codeql-action`, pinned to commit SHAs (D-34, D-96, D-111).
- **Workflow permissions:** read repository contents by default. The release workflow asks for write access itself.
- **Fork pull request workflows:** require approval for all outside collaborators.

## Code scanning

In **Settings → Code security → Code scanning**, default setup is off. CodeQL runs from
`.github/workflows/codeql.yml` on `main` only (D-96), so it adds no check to pull requests. The only required check is
**Lint, build and test**.

Release secrets and the `release` environment are described in [releasing.md](releasing.md).
