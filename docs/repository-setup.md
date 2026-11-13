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
| Require a pull request before merging | On. Required approvals: 0 (no one reviews pull requests, and GitHub doesn't let the owner approve their own, D-200). |
| Allowed merge methods | Squash only |
| Require status checks to pass | On. Add the check **Check** (from `.github/workflows/ci.yml`). Turn on "Require branches to be up to date before merging". |
| Block force pushes | On |
| Bypass list | Empty, so the rules apply to the owner too |

The status check appears in the picker only after CI has run once, so push a first pull request before adding it.

The required check also builds the engine package with SwiftPM, which compiles it for macOS 26, so an API newer than
macOS 26 fails there (NFR-COMP-001, D-06). CI has no macOS 26 runner: building with Xcode 26 waits until the app
supports macOS 26 (L-02, #213).

**Check** is the only job on a pull request. It runs the static checks and the changelog check for every change. A pull
request that changes only documentation skips its build and test steps, and **Check** still passes (D-66).

Cache warming runs in its own workflow, `.github/workflows/warm-cache.yml`, on pushes to `main` that change code, so
pull requests don't list it (D-111, #213).

In **Settings → General → Pull Requests**:

- Allow squash merging only, with the default commit message set to **Pull request title and description**, so the `[<task ID>] <deliverable>` title becomes the commit title on `main`.
- Turn on **Automatically delete head branches**.
- Turn on **Allow auto-merge**. Pull requests get auto-merge when they open and merge once the required check passes (D-51).

## No code owners

Changes to `scripts/` and `.github/` follow the same rules as any other change and merge once CI passes (D-200), so
the repository has no `.github/CODEOWNERS`. Leave "Require review from Code Owners" off in the `main` ruleset.

## Issues: types, forms and labels

An issue's kind is its **issue type**: Bug, Feature or Task, GitHub's built-in types. Labels say only what a type
can't. The forms in `.github/ISSUE_TEMPLATE/` set the type; blank issues are off, and security reports go to private
vulnerability reporting. An agent that files an issue with `gh issue create` sets them itself:
`gh issue create --type Bug --label area/file-cleanup`.

| Label | Color | Meaning | Added by, removed by |
|---|---|---|---|
| `area/file-cleanup` | `1d76db` | Large Files, Old Files, Developer Junk, Caches & Logs | The agent that triages the issue |
| `area/applications` | `1d76db` | The uninstaller and its leftovers | The agent that triages the issue |
| `area/startup-items` | `1d76db` | Login items, LaunchAgents and launchd | The agent that triages the issue |
| `area/history` | `1d76db` | History and Restore | The agent that triages the issue |
| `area/settings` | `1d76db` | The Settings window, exclusions and project folders | The agent that triages the issue |
| `area/app` | `1d76db` | The window, sidebar, Overview, onboarding and menus | The agent that triages the issue |
| `area/safety` | `1d76db` | The path guard, execution, the history log's records and the static checks | The agent that triages the issue |
| `area/ci` | `1d76db` | `scripts/`, workflows and releases | The agent that triages the issue |
| `area/docs` | `1d76db` | `README.md`, `AGENTS.md`, `docs/` and the changelog | The agent that triages the issue |
| `data-risk` | `b60205` | Shuck could remove, move or hide user data it shouldn't; fixed before any other task | Added in triage; stays as a record |

- **Triage:** an issue with no `area/` label is untriaged (`gh issue list --search "no:label"`). Before picking the
  next task, an agent triages each one: it checks the type, adds one `area/` label (two at most), and adds
  `data-risk` where it applies.
- **Closing:** close with a reason, not a label: `gh issue close N --reason completed`, `"not planned"` or `duplicate`.
- Milestones (M3, M4, …) say when; no label repeats them.
- Shuck has one developer and takes no outside contributions, so there are no contributor labels such as
  `good first issue` or `help wanted`.

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

- **Actions permissions:** allow actions created by GitHub only. The workflows use only `actions/*`, pinned to commit
  SHAs (D-34, D-111).
- **Workflow permissions:** read repository contents by default. The release workflow asks for write access itself.
- **Fork pull request workflows:** require approval for all outside collaborators.

## Code scanning

In **Settings → Code security → Code scanning**, default setup is off, and no workflow runs CodeQL (#213). CodeQL
cannot trace a build on macOS 27 or Xcode 27 and does not support Swift 6.4, which Xcode 27 ships. The only required
check is **Check**.

Release secrets and the `release` environment are described in [releasing.md](releasing.md).
