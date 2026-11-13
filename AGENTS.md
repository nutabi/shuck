# AGENTS.md

Instructions for AI coding agents working on Shuck. This is the only agent-instruction file in the repository. Do not add `CLAUDE.md` or any other vendor-specific instruction file: Claude Code reads `AGENTS.md` only when no `CLAUDE.md` exists (ENG-010).

## Project

Shuck is a free, open-source (GPL-3.0-or-later), native macOS app that keeps a Mac tidy. It has three tools: **File Cleanup** (sub-tools Large Files, Old Files, Developer Junk, Caches & Logs), **Applications** (uninstaller with leftovers) and **Startup Items**. Every action goes through a review-first safety model with an in-app restore log.

- The requirements, decisions and roadmap are in [docs/PRD.md](docs/PRD.md). Read sections 2, 6, 8 and 12 before any task, and the sections for the requirement IDs your task lists.
- macOS 27 or later, Apple Silicon only. The `ShuckKit` engine package uses only macOS 26 APIs (D-06).
- No network connections, no telemetry, no accounts, no admin rights.
- The owner reviews every change and is learning SwiftUI from the pull requests (G-5). Write for that reader.
- If the code and the PRD disagree, raise it with the owner (an issue, or a note in the pull request). Do not silently diverge. The owner records the outcome in `docs/decisions.md`.

## Where rules and preferences live

- Conventions, owner preferences and decisions are written down in the repository, so every agent can read them:
  - this file: how to work;
  - [docs/PRD.md](docs/PRD.md): what to build;
  - `docs/decisions.md`: decisions made after the planning phase.
- An agent's own memory or notes are a local scratchpad only. They must never be the only place a rule, preference or fact about the project is recorded. When an agent learns something the next agent needs, such as a tool's quirk or how to measure something, it adds it to this file or to `docs/` in the same change.
- When the owner states a new preference, add it to this file in the same change.
- When a task leaves open a decision that the PRD does not settle, the agent may decide it after consulting a stronger reviewer model, and records it in `docs/decisions.md` as an agent choice, open for review in the pull request (D-146). The hard stops still go to the owner before anything is implemented: the path guard, the static checks, any change to the safety layer, a change to a sub-tool's allowed roots, a change to a PRD requirement's text that settles an open question, and anything that could remove, move or hide user data beyond what the PRD says (D-170). The agent may still edit the PRD to match a decision the owner made.

## Commands

Run commands from the repository root. When a task adds or changes a command, it updates this table.

| Purpose | Command | Status |
|---|---|---|
| Build the app | `xcodebuild -workspace Shuck.xcworkspace -scheme Shuck -destination 'platform=macOS' build` | available |
| Engine, app and UI tests, from `Shuck.xctestplan` | `xcodebuild -workspace Shuck.xcworkspace -scheme Shuck -destination 'platform=macOS' test` | available |
| Engine tests only, built separately by SwiftPM | `swift test --package-path Packages/ShuckKit` | available |
| Lint (`--fix` to reformat), with the String Catalog check | `scripts/lint.sh` | available |
| User-facing strings without a String Catalog entry (NFR-L10N-001, D-161); `lint.sh` runs it, with `--self-test` first | `scripts/strings-check.py` | available |
| All tests and the coverage gate, as CI runs them (`--no-ui` skips UI tests; `--build-only` only builds) | `scripts/test.sh` | available |
| Static checks (ENG-006), on the files git tracks, including that every Must SAF requirement is named in a test | `scripts/static-checks.sh` | available |
| Static checks self-test (after changing the checks) | `scripts/static-checks-test.sh` | available |
| Whether a change touches code; CI skips lint, build and test if not (D-66) | `scripts/code-changed.sh BASE [HEAD]` | available |
| Build, sign and notarize the release DMG (docs/releasing.md) | `scripts/build-dmg.sh` | available |
| Print a version's release notes from `CHANGELOG.md` (D-95) | `scripts/release-notes.sh VERSION` | available |
| Check `CHANGELOG.md`'s form: every release has notes and a link (D-98) | `scripts/release-notes.sh --check` | available |
| Check that `## [Unreleased]` is empty at a tagged commit (the Release workflow runs it, D-180) | `scripts/release-notes.sh --tag-ready` | available |
| Build the Release configuration unsigned (`release`) or the engine package with SwiftPM (`engine`, on macOS 26 in CI), as CI does (#126, D-180) | `scripts/build-check.sh release` or `scripts/build-check.sh engine` | available |
| Notarize one file (called by `build-dmg.sh`) | `scripts/notarize.sh FILE` | available |

## Repository layout

```text
shuck/
├── AGENTS.md                  this file
├── README.md
├── LICENSE                    full GPL-3.0 text
├── CHANGELOG.md               changes users see, per release; each release's notes (D-95)
├── docs/
│   ├── PRD.md                 product requirements; the source of truth
│   ├── decisions.md           decisions after the planning phase (D-30 onwards)
│   ├── m1-review.md           tech-debt review at the end of M1; M2-T01 fixes its findings
│   ├── m2-review.md           review of M2 against the PRD and the safety rules, with the proposed fixes (D-142)
│   ├── progress.md            milestone and task checklist
│   ├── releasing.md           how to cut a release, secrets, local fallback
│   ├── repository-setup.md    GitHub settings the owner applies by hand
│   └── third-party.md         attribution for reused rule data or code; created on first reuse
├── Shuck.xcworkspace         open this in Xcode: the project and the engine package, so every test runs (D-111)
├── Shuck.xcodeproj
├── Shuck.xctestplan           the scheme's tests: engine, app unit and UI tests
├── Shuck/                     app target: views, navigation, view models
├── ShuckTests/                app unit tests
├── ShuckUITests/              UI tests (fixture root only, NFR-QA-002)
├── Packages/ShuckKit/         engine package (D-28)
│   ├── Sources/ShuckKit/              Tools, Scanning, Rules, Planning, Safety, History
│   ├── Sources/ShuckExecution/        the only code that mutates user files or launchd state
│   ├── Sources/ShuckKitTestSupport/   fixture-root harness and file factory
│   └── Tests/
├── scripts/                   lint, test, static checks, code-change check, build-dmg, notarize, release notes
└── .github/                   CI and release workflows, pull request template
```

The app target is thin and links the local ShuckKit package. All scanning, planning, safety and execution logic lives in the package (PRD section 11.1):

- `ShuckKit` holds Tools, Scanning, Rules, Planning, Safety and History, one folder each. It never mutates user files or launchd state.
- `ShuckExecution` depends on `ShuckKit` and is the only code that mutates user files or launchd state, including Restore's moves. `ShuckKit` cannot import it.
- `ShuckKitTestSupport` is shared by engine tests and the app's UI tests. Its helpers are `FixtureRoot` with `historyFolder` and `trashFolder`, and `items(from:context:)`, which collects a sub-tool's scan, and `app(_:bundleID:…)`, which writes a fake app bundle with a real `Info.plist`, and `tool(_:_:)`, which writes a fake tool (a script that exits, prints, sleeps or ignores SIGTERM) inside the root. `xcrun(_:)` writes the fake `xcrun` together with a fake Xcode's `simctl`, without which Developer Junk hides its `xcrun simctl` rule (DEV-002, D-157). Execution tests build a plan executor for a fixture root with `PlanExecutor(root:pathGuard:)`, whose tool runner finds tools only inside the root; a test never starts a process itself (D-82, D-114).
- Tests for `ShuckExecution` go in its own test target, `Tests/ShuckExecutionTests/`.

## Coding conventions

- Swift 6 language mode with strict concurrency checking. Scans run off the main actor in task groups; UI state and view models are `@Observable` and `@MainActor`.
- The app target makes code main-actor isolated by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Mark plain data types there `nonisolated`.
- The app and the engine compile with different concurrency settings (D-86). The app turns on approachable concurrency (`SWIFT_APPROACHABLE_CONCURRENCY`), so a `nonisolated` async function there runs on its caller's actor: mark one that must leave the main actor `@concurrent`, as `AppEnvironment`'s runs are. The engine keeps Swift 6's defaults, where such a function runs on the global executor.
- A compiler warning fails the build, in the app and in the engine (D-86). Fix the warning; don't silence it.
- No force unwraps, `try!` or `as!` in `ShuckKit`.
- Engine APIs throw typed errors (`throws(SomeError)`) whose cases callers can act on.
- Diagnostics use `Logger` with subsystem `me.nutabi.shuck` and one category per tool and sub-tool (NFR-OBS-001): `Logger(tool:)` in the engine. Code shared by several tools, such as an executor, logs under the tool it runs for; a scan Large Files and Old Files share logs under File Cleanup. The history log logs under `History`, and the app's own diagnostics under `Logger.app`. Mark paths and file names `privacy: .private` (NFR-SEC-006). No `print` in shipped code.
- The main thread is never blocked for more than 250 ms (NFR-PERF-001).
- User-facing strings live in String Catalogs; no hard-coded UI strings (NFR-L10N-001). A command-line build does not
  add new keys to `Shuck/Localizable.xcstrings`; only a build in Xcode does. Without Xcode, add each new key by hand
  as an empty entry like the ones around it, with `%@` for an interpolated value and `%lld` for an integer.
  `scripts/lint.sh` fails when a user-facing literal has no entry (`scripts/strings-check.py`, D-161). The check
  knows a literal by the call it is passed to (`Text`, `Button`, `.help`, `LocalizedStringResource`, …) or by the type
  of the declaration it is in; a literal it should leave alone gets `// not localized: <reason>` on its line.
- Every control has a VoiceOver label and works from the keyboard. Never convey information by color alone (NFR-A11Y-001).
- Subprocesses run through `posix_spawn` in a process group of their own (`ToolRunner`, D-191), with an absolute executable path, an argument array, an explicit environment and a timeout. Never `/bin/sh -c`, `system()` or `popen` (DEV-004, NFR-SEC-004). Only `ShuckExecution` may start one, tests included (D-82).
- No network APIs (`URLSession`, Network framework, `NSURLConnection`, sockets) and no authorization or privilege APIs (NFR-SEC-001, ONB-003).
- Code is `swift-format` clean: 4-space indentation and 120-character lines (`.swift-format`). `Packages/ShuckKit/.swift-format` adds the engine-only rules against force unwraps, `try!` and implicitly unwrapped optionals. Run `scripts/lint.sh --fix` before committing.

## UI tests

UI tests drive the real app on a fixture root (NFR-QA-002). They take over the mouse and keyboard while they run.

- Each UI test is a user workflow (D-75). It launches the app once and follows one realistic path through several tools, in named steps (`step(_:_:)` in `ShuckUITestCase.swift`) whose names carry the requirement IDs. Add a check to the step where a user would see it, a step to the workflow a user would follow, or a new workflow for a new journey. Logic and edge cases belong in unit tests.
- A fake tool that a UI test writes (`FixtureRoot.tool(_:_:)`) cannot run in the app: the UI test runner is sandboxed, so the files it writes are quarantined and the app gets "Operation not permitted" when it starts one. In CI the run of a tool item therefore ends as a failure. A UI test checks what a user sees whatever the tool's exit (the row, the confirmation, the finished sheet, the run in History); a tool that succeeds, with its output, is the engine tests' job (`ToolRunTests` and the rule tests in `ShuckExecutionTests`). Never remove the quarantine outside `ShuckExecution`.
- A check costs about 0.03 s; a launch costs about 1.6 s and a click about 0.7 s. So keep the checks a workflow passes, and don't add steps that only repeat another workflow's setup.
- After a step changes the page, first wait for something only the new page shows, so later checks can't pass on the page before.
- Run them from Xcode or from a terminal outside any sandbox. A sandboxed shell, such as an agent's command tool, launches the app without a window (only its menu bar appears), so every UI test fails, even on an unchanged `main`. Unit and engine tests run fine there: `scripts/test.sh --no-ui`. Run it in the repository or in a worktree inside it, such as `.claude/worktrees`: in a worktree under `/private/tmp`, the tests pass but the coverage gate finds no engine code and fails.
- Never launch the debug app by hand with a made-up `-ShuckFixtureRoot`. The app accepts only a fixture root the test harness created (`AppEnvironment.fixtureRoot(in:debugBuild:)`) and otherwise stops with `fatalError`, which leaves "Shuck quit unexpectedly" dialogs behind.
- A fixture-root scan finishes too fast to stop. A workflow that stops one launches with `launch(scanDelay:)`, which makes each personal-files scan wait that many seconds before it starts (D-91).
- A fixture file cannot be synced by iCloud. A workflow that checks a synced file's mark or warning launches with `launch(syncedFiles:)`, whose names the personal-files scan treats as synced (D-137).
- A workflow that checks what excluding a folder hides launches with `launch(exclusions:)`, whose paths are relative to
  the fixture root. They are the app's whole list of excluded folders (SET-001, D-150). A UI test never drives the open
  panel.
- A workflow that needs developer project folders (stale `node_modules`, DEV-R06) launches with
  `launch(projectFolders:)`, whose paths are relative to the fixture root too. They are the app's whole list, and a
  fixture root never starts with the default folders (SET-003, D-154).
- A fixture root has no installed apps, and Caches & Logs never preselects a cache whose app it cannot name
  (CAC-009). A workflow that needs a cache to start selected launches with `launch(installedApps:)`, whose bundle IDs
  the app treats as installed apps named by their ID; other names are still looked up on the Mac, as TextEdit is
  (D-156). Its map of app names is empty, so no UI test can show a folder named after an app, such as `Firefox`,
  disabled while the app runs; engine tests cover that (D-189).
- An engine test that scans Caches & Logs passes `CachesAndLogs(appNames: StubAppNames(…))`. The default
  `SystemAppNames` reads the real `/Applications` during a scan to tie folders named after apps (D-189, SAF-016).
- A fixture file was added to its folder when the test made it, so the app's fixture-root mode reads no added dates
  and Old Files judges fixture files by their last-opened and modified dates only (D-140). No UI test can show the
  "Added" reason or label; unit tests cover them.
- Wait with `appears(within:)` and `disappears(within:)` from `ShuckUITestCase.swift`, which check every 0.1 s (D-74). XCTest's `waitForExistence(timeout:)` and `waitForNonExistence(timeout:)` first check the element about a second after they start, so each call costs at least a second, even for an element already on screen. On 2026-11-02, waits took 52 s of the UI suite's 123 s.
- `firstMatch` does not find a SwiftUI `DisclosureGroup` row's combined accessibility element, such as a run on the History page. Use `.element` on a query that matches exactly one element.
- `scripts/test.sh` prints only each suite's time. Per-test times are in the result bundles in `build/DerivedData/Logs/Test/`, which CI uploads only when a run fails (D-34). `xcrun xcresulttool get test-results tests --path <bundle>` lists each test's duration, and `xcrun xcresulttool get test-results activities --test-id "<Class>/<method>()" --path <bundle>` lists one test's steps with their start times.

## Scan performance

A personal-files scan that is not cancelled logs one line in the `FileCleanup` category, such as `Scanned 812345 entries in 74.2 seconds` (NFR-PERF-002, D-78). An entry is a file or folder the scan looked at. A package or a device backup counts as one entry, although measuring its size reads everything inside it.

The measurements in `docs/progress.md` come from the owner's own home folder. Agents never scan a real home folder (safety rule 4), so an agent gives the owner these steps instead of running them:

1. Build the release app: `SHUCK_SIGN_IDENTITY=- scripts/build-dmg.sh --skip-notarization` writes `build/release/Shuck.app`. A debug build is not optimized, so its times say little.
2. Open `build/release/Shuck.app` and click Large Files, which starts the scan. macOS asks once about each protected folder, such as Documents, and the scan waits for the answer. When the scan has finished, click Scan to run it again.
3. Read both lines with `/usr/bin/log show --last 1h --style compact --predicate 'process == "Shuck" AND subsystem == "me.nutabi.shuck" AND eventMessage BEGINSWITH "Scanned"'` and record the second. The process filter leaves out engine tests, which log the same line. In zsh, `log` is a shell builtin, so the command needs the full path.
4. While Shuck is still open, read its peak memory with `vmmap --summary $(pgrep -x Shuck) | grep 'Physical footprint'` and record the peak (NFR-PERF-003). Only 25 MB of the baseline's 17.1 GB peak was still allocated after the scan, so the current footprint says little.

## Safety rules

Shuck deletes files. These rules are not negotiable, and CI enforces them where it can (ENG-006). `scripts/static-checks.sh` lists what is checked automatically. Creating or writing files is allowed only in `ShuckExecution` and in `ShuckKit`'s `History/` folder, which writes Shuck's own log. `History/` may also change the permissions of Shuck's own data folder and log, never anything else (D-45). If a check blocks legitimate code, ask the owner; do not weaken the check.

1. **Every mutation goes through the Execution layer.** No code outside the `ShuckExecution` module may delete, move, rename or modify user files or launchd state (SAF-017). That includes the app target, other engine modules and scripts.
2. **The path guard is mandatory.** Every target passes the path guard (SAF-007) and the protected-locations list (PRD section 8.4) when planned, and is re-validated just before acting (SAF-008). Never bypass, weaken or special-case the guard, not even to make a test pass. The only test difference allowed is D-41: tests configure the guard with the fixture root as home and without the temporary folder's `/private` prefix. If a guard rule looks wrong, stop and ask the owner.
   Every item, Trash or Delete, keeps the modification date its scan read in `ScanItem.modified`, and execution skips
   it if the date differs just before acting, even if kind and size still match (owner decisions D-105, D-132). For an
   item whose scope is its contents, the date is the newest inside it, as the scan judged staleness. Scanners read
   dates with `ModificationDate` (or `RuleMatch.modificationDate(at:)`, the same `lstat`), so scan and execution
   compare at the same precision; an item without a date is skipped. A plan refuses a Delete item without a rule
   match, and execution checks the rule again (D-141). Tests build such items with `FixtureRoot.planned(_:)`.
3. **Tests stay inside the fixture root.** Use the fixture-root harness from test support (SAF-016). Never build test paths from `homeDirectoryForCurrentUser`, `NSHomeDirectory()`, `~` or environment variables. A test of code that takes a home folder passes a made-up one, such as `/Users/someone`. UI tests launch the app with the debug-only fixture-root argument (NFR-QA-002).
4. **Never touch the real home folder.** Not in tests, not in experiments and not to "try out" a deletion. Never run the app against real data to test a change.
5. **The tier sets the review and limits the method** (SAF-004). "Your data" is never deleted permanently. Data owned by a tool (Docker, simulators, Homebrew, npm, pip) is cleaned only through that tool's documented command (SAF-010).
6. **No silent failures.** Every operation is logged as an intent before it runs and as a result after (SAF-005, SAF-006). Every run ends with a per-item outcome (SAF-011).

If you are unsure whether a change could remove, move or hide user data, stop and ask in the pull request before going further.

## Dependencies and reuse

- **Apple frameworks only** (D-03). Do not add third-party Swift packages, CocoaPods, Carthage or vendored code. CI fails if the project resolves any package other than Shuck's own local `ShuckKit` package (NFR-SEC-002, D-29). A third-party package needs an owner-approved entry in `docs/decisions.md` first.
- **Write our own code by default.** Code or rule data from the GPL-3.0 projects Mole and DevCleaner for Xcode may be reused with attribution recorded in `docs/third-party.md`.
- **Never copy code from Pearcleaner.** Its license (Apache-2.0 with Commons Clause) is incompatible with GPL-3.0. The same applies to any project whose license is not GPL-3.0-compatible.

## Pull requests and commits

- **One task = one pull request, or one stack** (ENG-002, owner preference 2026-11-13). A task is a roadmap task or a
  fix the owner asks for. Aim for about 200 changed lines of production code per pull request. When a task needs more,
  split it into several pull requests that are each small and reviewable on their own, for example engine first and
  then UI, or the Execution change before the code that uses it (D-62), and make them one stack. A task of one pull
  request needs no stack. Plan the split at the start of the task and say in each pull request what the next one adds.
- **Titles:** the pull request title and every commit title use `[<task ID>] <deliverable>`, for example `[M1-T02] PathGuard`. `main` is squash-merged, so the pull request title becomes the commit title on `main`.
- **Commit bodies:** a blank line after the title, then text wrapped at 72 characters explaining what changed and why. End with the requirement IDs, for example `Requirements: SAF-007, SAF-016`.
- **Partial tasks:** a commit that delivers only part of a task keeps the task ID in its title. Its body lists what is left, for example `Still to do for M0-T03: Swift 6 language mode and the sidebar placeholder window.`
- **Auto-merge:** open every pull request ready for review and turn on auto-merge (squash) right away. `main` requires the `Lint, build and test` check, so a pull request merges once CI passes. If CI fails, fix it on the branch (D-51). A stack is the exception: the agent merges it itself, as described under stacked pull requests. A pull request that changes only documentation (Markdown files and `LICENSE`) skips that check, and a skipped check counts as passed (D-66). The static checks and the changelog check still run for it, on Linux in the `Code changes` job (D-98). The exception is a task whose entry in `docs/progress.md` says the owner merges its stack in one go, such as M2-T01 (D-83): leave auto-merge off for its pull requests. A pull request that changes anything in `scripts/` or `.github/` never gets auto-merge, and an agent does not merge it, or a stack that holds it, on its own: those files decide what CI checks, so the owner reviews it and merges it or tells the agent to (#124, D-170).
- **Changelog** (D-95): a pull request that changes what users see or can do adds a line under `## [Unreleased]` in `CHANGELOG.md`, in the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) section that fits: Added, Changed, Deprecated, Removed, Fixed or Security. Write it for someone who uses Shuck: what changed for them, in plain words, not the task title, requirement IDs or type names. A change users can't notice, such as a refactor, a test or CI, gets no line. Each release's notes on GitHub are its section, so never write release notes by hand.
- **Branches:** every change goes through a pull request; `main` accepts only squash merges of pull requests that pass CI and are up to date (ENG-001). Name the branch after the task in lowercase plus a short slug, for example `m1-t02-path-guard`.
- **Signed commits** (owner preference, 2026-11-13): every commit on a branch is signed, as the owner's git
  config does by default. Bring a pull request up to date by rebasing locally and pushing with
  `--force-with-lease`, never with `gh pr update-branch` or GitHub's "Update branch" button: GitHub rewrites the
  commits on its servers and leaves them unsigned. `gh stack rebase` rebases locally, so it is fine.
- **Stacked pull requests** (D-76): when a pull request needs another one that is still open, make them a GitHub stack with the `gh stack` extension (`gh extension install github/gh-stack`). `gh stack init` adopts or creates the branches, bottom to top; `gh stack add <branch>` adds a layer on top; `gh stack submit --open` pushes the branches and creates the pull requests, ready for review, and the stack. Keep the stack linear with `gh stack rebase`, then `gh stack push`, never by merging. A stack merges from the bottom up, one squashed commit per pull request: merging a pull request also merges every one below it, and GitHub then rebases the next one onto `main` itself. After a merge, `gh stack sync --prune` updates the local branches. The agent merges the stack itself with `gh stack merge` once the CI of every pull request has passed, and does not wait for the owner (D-146). It does not turn on auto-merge for a stack. A stack with a pull request that changes `scripts/` or `.github/` waits for the owner's go-ahead (D-170). The exception is a task whose entry in `docs/progress.md` says the owner merges its stack in one go (D-83): leave that stack open for the owner.
- **One open change at a time** (owner preference, 2026-11-13): an agent has at most one task open: one pull request
  or one stack. It never opens two pull requests that are not in the same stack, so one merging first never leaves the
  other with conflicts. It starts the next task only after the previous one has merged. Something found along the way
  goes into the open stack if it belongs to the task, and otherwise waits, as a note to the owner, until it has merged.
- **Clean up after a merge** (owner preference, 2026-11-12): once a task's pull requests have merged, the agent removes the local worktrees and branches it used (`git worktree remove`, `git branch -D`, including an agent's `worktree-agent-*` branches) and prunes its stack with `gh stack sync --prune`.
- **Pull request description** (ENG-003, without its Screenshots section: D-65). Fill in every section of `.github/pull_request_template.md`:
  - **Summary.**
  - **Requirement IDs.**
  - **How to review this:** risky areas and the files to read first. Call out every change to Safety or Execution.
  - **SwiftUI concepts used:** a short explanation of each SwiftUI API or pattern the change uses, with a link to Apple's documentation.
  - **Test evidence.**
  - **Checklist:** tests added, no new dependencies, no network APIs, docs updated.
- **Definition of done** (ENG-004):
  - The project builds.
  - All tests pass locally and in CI.
  - New behavior has tests; deletion paths use fixture tests.
  - Tests for SAF requirements reference the requirement ID (NFR-QA-001).
  - `swift-format` reports nothing.
  - Static checks pass.
  - `docs/progress.md` is updated.
  - `CHANGELOG.md` has a line for each change users can notice.
  - The pull request description is complete.

## Delegating to other agents

Owner preference (2026-11-12, updated 2026-11-13): for every task or fix, the agent the owner prompts orchestrates
and delegates the work, picking the model by the work.

- Haiku agents read code and read or write docs.
- Sonnet agents write code, in parallel when their pieces touch different files and none needs another's code;
  otherwise one after another. Each works in its own worktree, and the orchestrating agent puts their work into the
  task's one pull request or one stack.
- A Fable advisor is consulted when a decision needs a stronger reviewer (D-146).

Decisions from several workers (owner preference, 2026-11-12), so parallel workers never fight over
`docs/decisions.md`:

- A worker agent never edits `docs/decisions.md`. Its final report gives each decision it made: the decision, the
  rationale, the rejected alternatives, and whether the owner made it or it is an agent choice open for review. Where
  the worker's own files must name the decision, such as a code comment or `docs/progress.md`, it writes a placeholder
  like `D-NEXT-sort`.
- The orchestrating agent gives each decision the next free ID and replaces the placeholders before it pushes a branch.
- When every worker of the batch is done, the orchestrating agent adds all the batch's decisions to
  `docs/decisions.md` in one commit on the top pull request of the stack, or on the task's only pull request.

## Picking the next task

- Take the first unchecked task in `docs/progress.md`, in roadmap order (PRD section 13), unless the owner assigns one.
- Milestones run in order. Do not start a milestone until the previous one meets its exit criteria.
- Milestones M2 to M6 are broken into tasks when each one starts. If the next milestone has no breakdown, propose one to the owner instead of starting work.
- Record progress in the same pull request: tick the task in `docs/progress.md`, and add a line for anything left over. In a stack, each pull request ticks its own sub-item, even when the owner merges the stack in one go (D-93).
- Record any decision made during a task in `docs/decisions.md` (ENG-011) with ID, date, decision, rationale and rejected alternatives.

## Adding a sub-tool or a cleanup rule

**A new File Cleanup sub-tool** (FCL-003):

1. Implement the `SubTool` protocol in `ShuckKit`: its `ToolInfo` (ID, name, summary, symbol), tiers, allowed roots, and a scan that streams items. Put its name and summary in `ShuckKit`'s String Catalog, loaded with `#bundle`.
2. Register it in `ToolRegistry.standard`, replacing its `PlannedSubTool` placeholder if it has one. The sidebar and the File Cleanup landing page are built from the registry; do not edit them by hand.
3. Build its page on `SubToolPage` and add it to `SubToolPages`, by tool ID; `ContentView` needs no change (D-91). `SubToolPage` gives the toolbar with Scan and Stop, the scan when the page opens if the sub-tool has not scanned yet (`FileCleanupModel.scanIfNotScanned`), the message that stands in for an empty list (D-61) and the review sheet (D-77). The page gives its subtitle, messages, own toolbar controls and list. `FileCleanupModel` keeps its items in a `ScanResults` of its own.
4. Add its locations to `OwnershipMap.standardEntries`. Within File Cleanup, each location has exactly one owner (FCL-005), the most specific pattern wins, and the ownership test must still pass. Its scan skips anything the map does not give it.
5. Its scan hides anything inside or holding one of the user's exclusions (SET-001, D-149): check each path item with the
   guard, as Caches & Logs does. Add the sub-tool's fixtures to `ExclusionsTests`, which fails if a sub-tool that scans
   is left out.
6. Add fixture tests for its scan and for a full run through the safety pipeline, plus a UI smoke test for its main path (NFR-QA-003): a step in the UI workflow where a user would take that path, or a new workflow (see "UI tests"). List it in `ShuckUITestCase`'s documentation comment (D-75).
7. Its ID goes in the history log's `tool` field (PRD section 8.5). Ask the owner to add it to the PRD.

A sub-tool must not require changes to other sub-tools or to the safety layer. If it does, stop and ask: that is a design change.

**A new Developer Junk or Caches & Logs rule** (DEV-001):

1. Add the rule as data in the engine: ID, name, description, detection, targets or tool command, tier, staleness rule, explanation, documentation link, and the bundle IDs of the apps that use its data (`apps`, D-110). Its scanner builds items with `CleanupRule.scanItem(…runningApps: context.runningApps…)`, which disables them while one of those apps runs (SAF-009).
2. Targets must lie inside the allowed roots. Data owned by a tool is cleaned with that tool's documented command, never deleted directly (SAF-010). Tool commands follow DEV-004.
3. Add the rule's locations to `OwnershipMap.standardEntries` (FCL-005).
4. A tool command's item is hidden when the folder it is sized from is, or holds, an exclusion: add the rule to
   `DeveloperJunk.toolFolder` and to the test in `ExclusionsTests` (SET-001, D-149).
5. Add a fixture test for a path rule, or a recorded-output test with a fake tool executable for a tool rule. Never parse tool output to choose deletion targets (R-07).
6. One rule per pull request. A rule that is not in the PRD's rule table (section 9.1.3) needs the owner's approval first.
