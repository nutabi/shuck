# AGENTS.md

Instructions for AI coding agents working on Shuck. This is the only agent-instruction file: do not add `CLAUDE.md` or
any other vendor-specific file, because Claude Code reads `AGENTS.md` only when no `CLAUDE.md` exists (ENG-010).

## Project

Shuck is a free, open-source (GPL-3.0-or-later), native macOS app that keeps a Mac tidy. Its tools are **File
Cleanup** (Large Files, Old Files, Developer Junk, Caches & Logs), **Applications** (an uninstaller with leftovers) and
**Startup Items**. Every action goes through a review-first safety model with an in-app restore log.

- [docs/PRD.md](docs/PRD.md) says what to build. Read sections 2, 6, 8 and 12, and the sections for your task's
  requirement IDs.
- macOS 27 or later, Apple Silicon only. The `ShuckKit` engine uses only macOS 26 APIs (D-06).
- No network connections, telemetry, accounts or admin rights.
- Shuck has one developer, the owner, and takes no outside contributions or pull requests (owner preference,
  2026-11-14).
- Write pull requests and comments so a reader new to the code and to SwiftUI can follow them (G-5).

## Rules and decisions

- This file says how to work and `docs/PRD.md` what to build. Detail lives in `docs/`: [testing.md](docs/testing.md),
  [extending.md](docs/extending.md) and [scan-performance.md](docs/scan-performance.md). `docs/archive/` holds
  finished work, such as the decisions D-30 to D-200 that `D-NN` references point at; it is frozen.
- An agent's memory is only a scratchpad. A rule, owner preference or tool quirk the next agent needs goes into this
  file or `docs/`, in the same change.
- **The advisor decides** (owner preference, 2026-11-13, D-200). Anything the PRD leaves open goes to the
  advisor, as does a conflict between the code and the PRD. So do changes to the path guard, the safety layer, the
  static checks, a sub-tool's allowed roots or a dependency, and any change that could remove, move or hide user data
  beyond what the PRD says. When unsure whether a change could, stop and ask the advisor. The agent follows the
  advisor's decision and updates the PRD to match. Nothing waits for the owner's review.
- **Decisions are recorded in the pull request** that makes them (ENG-011): under "How to review this", each decision
  in a sentence or two, with why and the alternatives rejected. The description becomes the commit on `main`, so
  `git log --grep` finds it. Code that must cite a decision cites the pull request, such as `#215`. Worker agents
  report their decisions to the orchestrating agent, which writes them into the description.

## Working on a task

Owner preference, 2026-11-13:

- Take the first unchecked task in `docs/progress.md` unless the owner names one. Milestones run in order, and one
  starts only when the previous one meets its exit criteria. If the next milestone has no task breakdown, propose one
  to the owner before starting.
- The agent the owner prompts orchestrates and delegates:
  - Haiku agents read code and read or write docs.
  - Sonnet agents write code. They run in parallel when their pieces touch different files and none needs another's
    code, otherwise one after another, each in its own worktree.
  - The advisor decides, as described above.
- **One task is one pull request, or one stack** (ENG-002). A task is a roadmap task or a fix. Aim for about 200 changed
  lines of production code per pull request. A bigger task is split into a stack of pull requests that are each small
  and reviewable on their own: engine before UI, Execution before the code that uses it (D-62). Say in each pull
  request what the next one adds.
- **One open change at a time.** Never have two open pull requests outside one stack, so a merge never leaves another
  pull request with conflicts. Start the next task only after the last one has merged. Something found along the way
  goes into the open stack if it belongs to the task; otherwise it becomes an issue.
- **Issues** (`docs/repository-setup.md` has the types and labels): before picking the next task, triage the issues
  with no label. An open `data-risk` bug goes before any other task. Something found along the way that doesn't belong
  to the open task becomes an issue, with its type and `area/` label.
- Tick the task in `docs/progress.md` in the same pull request (each pull request in a stack ticks its own sub-item,
  D-93), and add a line for anything left over.
- After the merge, remove the worktrees and branches you used, including `worktree-agent-*` (`git worktree remove`,
  `git branch -D`, `gh stack sync --prune`).

## Pull requests and commits

- **Branches:** every change goes through a pull request. `main` takes only squash merges that pass CI and are up to
  date (ENG-001). Name the branch after the task in lowercase plus a slug: `m1-t02-path-guard`.
- **The pull request is what lands.** `main` squash-merges each pull request, with its title as the commit title and
  its description as the commit body. The title is `[<task ID>] <deliverable>`, for example `[M1-T02] PathGuard`.
  Commits on the branch need only a short title (D-200).
- **Signed commits** (owner preference, 2026-11-13): every commit is signed, as the owner's git config does by
  default. To update a branch, rebase locally and push with `--force-with-lease`, or use `gh stack rebase`. Never use
  `gh pr update-branch` or GitHub's "Update branch" button, which leave the commits unsigned.
- **A single pull request** opens ready for review with auto-merge (squash) on. If CI fails, fix it on the branch
  (D-51). A change to Markdown files and `LICENSE` only runs just the static and changelog checks of `Check`, which
  still passes (D-66).
- **A stack** (D-76) uses the `gh stack` extension (`gh extension install github/gh-stack`): `gh stack init`,
  `gh stack add <branch>` and `gh stack submit --open`. Keep it linear with `gh stack rebase` and `gh stack push`,
  never by merging. Turn on auto-merge (squash) on the top pull request: once CI passes, it merges the whole stack,
  bottom up, one squashed commit per pull request (D-200).
- Changes to `scripts/` and `.github/` follow the same rules as any other change (D-200).
- **Changelog** (D-95): a change users can notice adds a plain-words line under `## [Unreleased]` in `CHANGELOG.md`,
  in the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) section that fits. Refactors, tests and CI get no
  line. Never write release notes by hand.
- **Description** (ENG-003): the three sections of `.github/pull_request_template.md`, kept short: what changed and
  why, ending with the requirement IDs; what to read first, including every change to Safety or Execution and each
  advisor decision; and the test evidence.
- **Done** (ENG-004): CI passes; new behavior has tests, deletion paths have fixture tests, and SAF tests name their
  requirement ID (NFR-QA-001); `docs/progress.md` and `CHANGELOG.md` are updated.

## Commands

Run from the repository root. A task that adds or changes a command updates this table.

| Purpose | Command |
|---|---|
| Build the app | `xcodebuild -workspace Shuck.xcworkspace -scheme Shuck -destination 'platform=macOS' build` |
| Engine, app and UI tests (`Shuck.xctestplan`) | `xcodebuild -workspace Shuck.xcworkspace -scheme Shuck -destination 'platform=macOS' test` |
| Engine tests only, with SwiftPM | `swift test --package-path Packages/ShuckKit` |
| All tests and the coverage gate, as CI runs them (`--no-ui`, `--build-only`) | `scripts/test.sh` |
| Lint (`--fix` reformats), including the String Catalog check | `scripts/lint.sh` |
| User-facing strings without a String Catalog entry (D-161; `--self-test`) | `scripts/strings-check.py` |
| Static checks (ENG-006), including that every Must SAF requirement is named in a test | `scripts/static-checks.sh` |
| Static checks self-test, after changing the checks | `scripts/static-checks-test.sh` |
| Whether a change touches code; CI's `Check` skips its build and test steps if not (D-66) | `scripts/code-changed.sh BASE [HEAD]` |
| Release build unsigned, or the engine with SwiftPM, as CI does (D-180) | `scripts/build-check.sh release` or `engine` |
| Build, sign and notarize the release DMG (`docs/releasing.md`) | `scripts/build-dmg.sh` |
| Notarize one file (called by `build-dmg.sh`) | `scripts/notarize.sh FILE` |
| A version's release notes from `CHANGELOG.md` (D-95) | `scripts/release-notes.sh VERSION` |
| `CHANGELOG.md`'s form (D-98), or an empty Unreleased at a tag (D-180) | `scripts/release-notes.sh --check` or `--tag-ready` |

## Code layout

- `Shuck/` is the app target: views, navigation and view models. It is thin and links the local `ShuckKit` package.
  Open `Shuck.xcworkspace`, which holds the project and the package, so every test runs (D-111).
- `Packages/ShuckKit` holds all scanning, planning, safety and execution logic (PRD section 11.1):
  - `ShuckKit` has Tools, Scanning, Rules, Planning, Safety and History, one folder each. It never mutates user files or
    launchd state.
  - `ShuckExecution` is the only code that mutates user files or launchd state, Restore included. `ShuckKit` cannot
    import it.
  - `ShuckKitTestSupport` holds the fixture-root harness, described in [docs/testing.md](docs/testing.md).
- `ShuckTests/` and `ShuckUITests/` hold the app's unit and UI tests. `scripts/` holds the scripts in the table above.
  `docs/` holds the PRD, decisions, `progress.md` and the detail docs.

## Coding conventions

- Swift 6 language mode with strict concurrency. Scans run off the main actor in task groups. UI state and view models
  are `@Observable` and `@MainActor`.
- The app target is main-actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION`), so mark plain data types there
  `nonisolated`. It also uses approachable concurrency, so a `nonisolated` async function that must leave the main actor
  is marked `@concurrent` (D-86). The engine keeps Swift 6's defaults.
- A compiler warning fails the build (D-86). Fix it; don't silence it.
- `ShuckKit` has no force unwraps, `try!` or `as!`. Engine APIs throw typed errors (`throws(SomeError)`) whose cases
  callers can act on.
- Diagnostics use `Logger` with subsystem `me.nutabi.shuck` and one category per tool and sub-tool (NFR-OBS-001):
  `Logger(tool:)` in the engine and `Logger.app` in the app. Shared code logs under the tool it runs for (a scan Large
  Files and Old Files share, under File Cleanup), and the history log under `History`. Mark paths
  `privacy: .private` (NFR-SEC-006). Shipped code never uses `print`.
- The main thread is never blocked for more than 250 ms (NFR-PERF-001).
- User-facing strings live in String Catalogs (NFR-L10N-001). A command-line build doesn't add keys to
  `Shuck/Localizable.xcstrings`, so add each new key by hand as an empty entry, with `%@` for a value and `%lld` for an
  integer. `scripts/lint.sh` fails on a literal without an entry (D-161). A literal it should skip gets
  `// not localized: <reason>`.
- Every control has a VoiceOver label and works from the keyboard. Color never carries information alone
  (NFR-A11Y-001).
- Subprocesses run only in `ShuckExecution`, tests included (D-82). They go through `ToolRunner` (`posix_spawn`, in a
  process group of their own, D-191), with an absolute path, an argument array, an explicit environment and a timeout.
  Never use `/bin/sh -c`, `system()` or `popen` (DEV-004, NFR-SEC-004).
- No network APIs and no authorization or privilege APIs (NFR-SEC-001, ONB-003).
- Code is `swift-format` clean: 4 spaces and 120-character lines, and the engine's own `.swift-format` bans force
  unwraps, `try!` and implicitly unwrapped optionals. Run `scripts/lint.sh --fix` before committing.

## Safety rules

Shuck deletes files. These rules are not negotiable, and CI enforces them where it can (`scripts/static-checks.sh`,
ENG-006). Only `ShuckExecution` creates or writes files, plus `ShuckKit`'s `History/` folder, which writes Shuck's own
log and may change the permissions of Shuck's own data folder and log (D-45). If a check blocks legitimate code, the
advisor decides how the check changes; never just weaken it to get past.

1. **Every mutation goes through the Execution layer.** Only `ShuckExecution` may delete, move, rename or modify user
   files or launchd state (SAF-017). That excludes the app target, other engine modules and scripts.
2. **The path guard is mandatory.** Every target passes the path guard (SAF-007) and the protected locations (PRD
   section 8.4) when planned, and again just before acting (SAF-008). Never bypass, weaken or special-case the guard,
   not even to make a test pass; if a guard rule looks wrong, stop and ask the advisor. The only test difference is
   D-41: tests configure it with the fixture root as home and without the `/private` prefix. Each item
   keeps the modification date its scan read (`ScanItem.modified`, read with `ModificationDate` or
   `RuleMatch.modificationDate(at:)`, the same `lstat` execution uses). Execution skips the
   item if that date changed or is missing (D-105, D-132). For an item whose scope is its contents, the date is the
   newest one inside. A Delete item needs a rule match, which execution checks again (D-141). Tests build such items
   with `FixtureRoot.planned(_:)`.
3. **Tests stay inside the fixture root** (SAF-016). Never build test paths from `homeDirectoryForCurrentUser`,
   `NSHomeDirectory()`, `~` or environment variables. Code that takes a home folder gets a made-up one, such as
   `/Users/someone`.
4. **Never touch the real home folder:** not in tests, not in experiments, and never by running the app on real data.
5. **The tier sets the review and limits the method** (SAF-004). "Your data" is never deleted permanently. Data owned
   by a tool (Docker, simulators, Homebrew, npm, pip) is cleaned only through that tool's documented command (SAF-010).
6. **No silent failures.** Every operation is logged as an intent before it runs and as a result after (SAF-005,
   SAF-006), and every run ends with a per-item outcome (SAF-011).

## Adding a sub-tool or a cleanup rule

Follow the checklists in [docs/extending.md](docs/extending.md): the registry entry, the ownership map (FCL-005),
exclusions (SET-001) and fixture tests.

## Dependencies and reuse

- Apple frameworks only (D-03). CI fails if the project resolves any package other than `ShuckKit` (NFR-SEC-002,
  D-29). A third-party package needs the advisor's decision first.
- Write our own code. Code or rule data from the GPL-3.0 projects Mole and DevCleaner for Xcode may be reused, with
  attribution in `docs/third-party.md`.
- Never copy code from Pearcleaner (Apache-2.0 with Commons Clause), or from any project whose license is not
  GPL-3.0-compatible.
