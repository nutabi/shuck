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
- When a task leaves open a decision that the PRD does not settle, ask the owner before implementing instead of guessing.

## Commands

Run commands from the repository root. When a task adds or changes a command, it updates this table.

| Purpose | Command | Status |
|---|---|---|
| Build the app | `xcodebuild -project Shuck.xcodeproj -scheme Shuck -destination 'platform=macOS' build` | available |
| App tests (unit and UI) | `xcodebuild -project Shuck.xcodeproj -scheme Shuck -destination 'platform=macOS' test` | available |
| Engine tests | `swift test --package-path Packages/ShuckKit` | available |
| Lint (`--fix` to reformat) | `scripts/lint.sh` | available |
| All tests, as CI runs them (`--no-ui` skips UI tests) | `scripts/test.sh` | available |
| Static checks (ENG-006) | `scripts/static-checks.sh` | available |
| Static checks self-test (after changing the checks) | `scripts/static-checks-test.sh` | available |
| Whether a change touches code; CI skips lint, build and test if not (D-66) | `scripts/code-changed.sh BASE [HEAD]` | available |
| Build, sign and notarize the release DMG (docs/releasing.md) | `scripts/build-dmg.sh` | available |
| Notarize one file (called by `build-dmg.sh`) | `scripts/notarize.sh FILE` | available |

## Repository layout

```text
shuck/
├── AGENTS.md                  this file
├── README.md
├── LICENSE                    full GPL-3.0 text
├── docs/
│   ├── PRD.md                 product requirements; the source of truth
│   ├── decisions.md           decisions after the planning phase (D-30 onwards)
│   ├── progress.md            milestone and task checklist
│   ├── releasing.md           how to cut a release, secrets, local fallback
│   ├── repository-setup.md    GitHub settings the owner applies by hand
│   └── third-party.md         attribution for reused rule data or code; created on first reuse
├── Shuck.xcodeproj
├── Shuck/                     app target: views, navigation, view models
├── ShuckTests/                app unit tests
├── ShuckUITests/              UI tests (fixture root only, NFR-QA-002)
├── Packages/ShuckKit/         engine package (D-28)
│   ├── Sources/ShuckKit/              Tools, Scanning, Rules, Planning, Safety, History
│   ├── Sources/ShuckExecution/        the only code that mutates user files or launchd state
│   ├── Sources/ShuckKitTestSupport/   fixture-root harness and file factory
│   └── Tests/
├── scripts/                   lint, test, static checks, code-change check, build-dmg, notarize
└── .github/                   CI and release workflows, pull request template
```

The app target is thin and links the local ShuckKit package. All scanning, planning, safety and execution logic lives in the package (PRD section 11.1):

- `ShuckKit` holds Tools, Scanning, Rules, Planning, Safety and History, one folder each. It never mutates user files or launchd state.
- `ShuckExecution` depends on `ShuckKit` and is the only code that mutates user files or launchd state, including Restore's moves. `ShuckKit` cannot import it.
- `ShuckKitTestSupport` is shared by engine tests and the app's UI tests.
- Tests for `ShuckExecution` go in `Tests/ShuckExecutionTests/`, a test target added with the first executor (M1-T04).

## Coding conventions

- Swift 6 language mode with strict concurrency checking. Scans run off the main actor in task groups; UI state and view models are `@Observable` and `@MainActor`.
- The app target makes code main-actor isolated by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Mark plain data types there `nonisolated`.
- No force unwraps, `try!` or `as!` in `ShuckKit`.
- Engine APIs throw typed errors (`throws(SomeError)`) whose cases callers can act on.
- Diagnostics use `Logger` with subsystem `me.nutabi.shuck` and one category per tool and sub-tool (NFR-OBS-001). Mark paths and file names `privacy: .private` (NFR-SEC-006). No `print` in shipped code.
- The main thread is never blocked for more than 250 ms (NFR-PERF-001).
- User-facing strings live in String Catalogs; no hard-coded UI strings (NFR-L10N-001).
- Every control has a VoiceOver label and works from the keyboard. Never convey information by color alone (NFR-A11Y-001).
- Subprocesses run through `Process` with an absolute executable path, an argument array, an explicit environment and a timeout. Never `/bin/sh -c`, `system()` or `popen` (DEV-004, NFR-SEC-004).
- No network APIs (`URLSession`, Network framework, `NSURLConnection`, sockets) and no authorization or privilege APIs (NFR-SEC-001, ONB-003).
- Code is `swift-format` clean: 4-space indentation and 120-character lines (`.swift-format`). `Packages/ShuckKit/.swift-format` adds the engine-only rules against force unwraps, `try!` and implicitly unwrapped optionals. Run `scripts/lint.sh --fix` before committing.

## UI tests

UI tests drive the real app on a fixture root (NFR-QA-002). They take over the mouse and keyboard while they run.

- Each UI test is a user workflow (D-75). It launches the app once and follows one realistic path through several tools, in named steps (`step(_:_:)` in `ShuckUITestCase.swift`) whose names carry the requirement IDs. Add a check to the step where a user would see it, a step to the workflow a user would follow, or a new workflow for a new journey. Logic and edge cases belong in unit tests.
- A check costs about 0.03 s; a launch costs about 1.6 s and a click about 0.7 s. So keep the checks a workflow passes, and don't add steps that only repeat another workflow's setup.
- After a step changes the page, first wait for something only the new page shows, so later checks can't pass on the page before.
- Run them from Xcode or from a terminal outside any sandbox. A sandboxed shell, such as an agent's command tool, launches the app without a window (only its menu bar appears), so every UI test fails, even on an unchanged `main`. Unit and engine tests run fine there: `scripts/test.sh --no-ui`.
- Never launch the debug app by hand with a made-up `-ShuckFixtureRoot`. The app accepts only a fixture root the test harness created (`AppEnvironment.fixtureRoot(in:debugBuild:)`) and otherwise stops with `fatalError`, which leaves "Shuck quit unexpectedly" dialogs behind.
- Wait with `appears(within:)` and `disappears(within:)` from `ShuckUITestCase.swift`, which check every 0.1 s (D-74). XCTest's `waitForExistence(timeout:)` and `waitForNonExistence(timeout:)` first check the element about a second after they start, so each call costs at least a second, even for an element already on screen. On 2026-11-02, waits took 52 s of the UI suite's 123 s.
- `firstMatch` does not find a SwiftUI `DisclosureGroup` row's combined accessibility element, such as a run on the History page. Use `.element` on a query that matches exactly one element.
- `scripts/test.sh` prints only each suite's time. Per-test times are in the result bundles in `build/DerivedData/Logs/Test/`, which CI uploads only when a run fails (D-34). `xcrun xcresulttool get test-results tests --path <bundle>` lists each test's duration, and `xcrun xcresulttool get test-results activities --test-id "<Class>/<method>()" --path <bundle>` lists one test's steps with their start times.

## Safety rules

Shuck deletes files. These rules are not negotiable, and CI enforces them where it can (ENG-006). `scripts/static-checks.sh` lists what is checked automatically. Creating or writing files is allowed only in `ShuckExecution` and in `ShuckKit`'s `History/` folder, which writes Shuck's own log. `History/` may also change the permissions of Shuck's own data folder and log, never anything else (D-45). If a check blocks legitimate code, ask the owner; do not weaken the check.

1. **Every mutation goes through the Execution layer.** No code outside the `ShuckExecution` module may delete, move, rename or modify user files or launchd state (SAF-017). That includes the app target, other engine modules and scripts.
2. **The path guard is mandatory.** Every target passes the path guard (SAF-007) and the protected-locations list (PRD section 8.4) when planned, and is re-validated just before acting (SAF-008). Never bypass, weaken or special-case the guard, not even to make a test pass. The only test difference allowed is D-41: tests configure the guard with the fixture root as home and without the temporary folder's `/private` prefix. If a guard rule looks wrong, stop and ask the owner.
3. **Tests stay inside the fixture root.** Use the fixture-root harness from test support (SAF-016). Never build test paths from `homeDirectoryForCurrentUser`, `NSHomeDirectory()`, `~` or environment variables. UI tests launch the app with the debug-only fixture-root argument (NFR-QA-002).
4. **Never touch the real home folder.** Not in tests, not in experiments and not to "try out" a deletion. Never run the app against real data to test a change.
5. **The tier sets the review and limits the method** (SAF-004). "Your data" is never deleted permanently. Data owned by a tool (Docker, simulators, Homebrew, npm, pip) is cleaned only through that tool's documented command (SAF-010).
6. **No silent failures.** Every operation is logged as an intent before it runs and as a result after (SAF-005, SAF-006). Every run ends with a per-item outcome (SAF-011).

If you are unsure whether a change could remove, move or hide user data, stop and ask in the pull request before going further.

## Dependencies and reuse

- **Apple frameworks only** (D-03). Do not add third-party Swift packages, CocoaPods, Carthage or vendored code. CI fails if the project resolves any package other than Shuck's own local `ShuckKit` package (NFR-SEC-002, D-29). A third-party package needs an owner-approved entry in `docs/decisions.md` first.
- **Write our own code by default.** Code or rule data from the GPL-3.0 projects Mole and DevCleaner for Xcode may be reused with attribution recorded in `docs/third-party.md`.
- **Never copy code from Pearcleaner.** Its license (Apache-2.0 with Commons Clause) is incompatible with GPL-3.0. The same applies to any project whose license is not GPL-3.0-compatible.

## Pull requests and commits

- **One pull request = one roadmap task** (ENG-002). Aim for about 200 changed lines of production code. When a task needs more, split it into several pull requests that are each small and reviewable on their own, for example engine first and then UI, or the Execution change before the code that uses it (D-62). Plan the split at the start of the task and say in each pull request what the next one adds.
- **Titles:** the pull request title and every commit title use `[<task ID>] <deliverable>`, for example `[M1-T02] PathGuard`. `main` is squash-merged, so the pull request title becomes the commit title on `main`.
- **Commit bodies:** a blank line after the title, then text wrapped at 72 characters explaining what changed and why. End with the requirement IDs, for example `Requirements: SAF-007, SAF-016`.
- **Partial tasks:** a commit that delivers only part of a task keeps the task ID in its title. Its body lists what is left, for example `Still to do for M0-T03: Swift 6 language mode and the sidebar placeholder window.`
- **Auto-merge:** open every pull request ready for review and turn on auto-merge (squash) right away. `main` requires the `Lint, build and test` check, so a pull request merges once CI passes. If CI fails, fix it on the branch (D-51). A pull request that changes only documentation (Markdown files and `LICENSE`) skips that check, and a skipped check counts as passed (D-66).
- **Branches:** every change goes through a pull request; `main` accepts only squash merges of pull requests that pass CI and are up to date (ENG-001). Name the branch after the task in lowercase plus a short slug, for example `m1-t02-path-guard`.
- **Stacked pull requests** (D-76): when a pull request needs another one that is still open, make them a GitHub stack with the `gh stack` extension (`gh extension install github/gh-stack`). `gh stack init` adopts or creates the branches, bottom to top; `gh stack add <branch>` adds a layer on top; `gh stack submit --open` pushes the branches and creates the pull requests, ready for review, and the stack. Keep the stack linear with `gh stack rebase`, then `gh stack push`, never by merging. A stack merges from the bottom up, one squashed commit per pull request: merging a pull request also merges every one below it, and GitHub then rebases the next one onto `main` itself. After a merge, `gh stack sync --prune` updates the local branches. Turn on auto-merge for each pull request in the stack (D-51); if GitHub refuses it for a stack, say so in the pull request, and merge with `gh stack merge` when the owner asks.
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
  - The pull request description is complete.

## Picking the next task

- Take the first unchecked task in `docs/progress.md`, in roadmap order (PRD section 13), unless the owner assigns one.
- Milestones run in order. Do not start a milestone until the previous one meets its exit criteria.
- Milestones M2 to M6 are broken into tasks when each one starts. If the next milestone has no breakdown, propose one to the owner instead of starting work.
- Record progress in the same pull request: tick the task in `docs/progress.md`, and add a line for anything left over.
- Record any decision made during a task in `docs/decisions.md` (ENG-011) with ID, date, decision, rationale and rejected alternatives.

## Adding a sub-tool or a cleanup rule

**A new File Cleanup sub-tool** (FCL-003):

1. Implement the `SubTool` protocol in `ShuckKit`: its `ToolInfo` (ID, name, summary, symbol), tiers, allowed roots, and a scan that streams items. Put its name and summary in `ShuckKit`'s String Catalog, loaded with `#bundle`.
2. Register it in `ToolRegistry.standard`, replacing its `PlannedSubTool` placeholder if it has one. The sidebar and the File Cleanup landing page are built from the registry; do not edit them by hand.
3. Its page starts its scan when it opens, if it has not scanned yet (`FileCleanupModel.scanIfNotScanned`). While there is nothing to list, the page shows only a message, never an empty table (D-61).
4. Add its locations to `OwnershipMap.standardEntries`. Within File Cleanup, each location has exactly one owner (FCL-005), the most specific pattern wins, and the ownership test must still pass. Its scan skips anything the map does not give it.
5. Add fixture tests for its scan and for a full run through the safety pipeline, plus a UI smoke test for its main path (NFR-QA-003): a step in the UI workflow where a user would take that path, or a new workflow (see "UI tests"). List it in `ShuckUITestCase`'s documentation comment (D-75).
6. Its ID goes in the history log's `tool` field (PRD section 8.5). Ask the owner to add it to the PRD.

A sub-tool must not require changes to other sub-tools or to the safety layer. If it does, stop and ask: that is a design change.

**A new Developer Junk or Caches & Logs rule** (DEV-001):

1. Add the rule as data in the engine: ID, name, description, detection, targets or tool command, tier, staleness rule, explanation, documentation link.
2. Targets must lie inside the allowed roots. Data owned by a tool is cleaned with that tool's documented command, never deleted directly (SAF-010). Tool commands follow DEV-004.
3. Add the rule's locations to `OwnershipMap.standardEntries` (FCL-005).
4. Add a fixture test for a path rule, or a recorded-output test with a fake tool executable for a tool rule. Never parse tool output to choose deletion targets (R-07).
5. One rule per pull request. A rule that is not in the PRD's rule table (section 9.1.3) needs the owner's approval first.
