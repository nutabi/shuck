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
- An agent's own memory or notes are a local scratchpad only. They must never be the only place a rule is recorded.
- When the owner states a new preference, add it to this file in the same change.
- When a task leaves open a decision that the PRD does not settle, ask the owner before implementing instead of guessing.

## Commands

Run commands from the repository root. Commands marked *planned* do not exist yet: the task named next to each one adds it and removes the marker from this table.

| Purpose | Command | Status |
|---|---|---|
| Build the app | `xcodebuild -project Shuck.xcodeproj -scheme Shuck -destination 'platform=macOS' build` | available |
| App tests (unit and UI) | `xcodebuild -project Shuck.xcodeproj -scheme Shuck -destination 'platform=macOS' test` | available |
| Engine tests | `swift test --package-path Packages/ShuckKit` | *planned* (M0-T04) |
| Lint | `scripts/lint.sh` (`swift-format`) | *planned* (M0-T05) |
| All tests, as CI runs them | `scripts/test.sh` | *planned* (M0-T06) |
| Static checks (ENG-006) | `scripts/static-checks.sh` | *planned* (M0-T07) |
| Build a DMG | `scripts/build-dmg.sh` | *planned* (M0-T08) |
| Notarize | `scripts/notarize.sh` | *planned* (M0-T08) |

## Repository layout

```text
shuck/
├── AGENTS.md                  this file
├── README.md
├── LICENSE                    full GPL-3.0 text
├── docs/
│   ├── PRD.md                 product requirements; the source of truth
│   ├── decisions.md           decisions after the planning phase; planned (M0-T09)
│   ├── progress.md            milestone and task checklist; planned (M0-T09)
│   └── third-party.md         attribution for reused rule data or code; created on first reuse
├── Shuck.xcodeproj
├── Shuck/                     app target: views, navigation, view models
├── ShuckTests/                app unit tests
├── ShuckUITests/              UI tests (fixture root only, NFR-QA-002)
├── Packages/ShuckKit/         engine package, its tests and test support; planned (M0-T04)
├── scripts/                   lint, test, static checks, build-dmg, notarize; planned (M0-T05 to T08)
└── .github/                   workflows and pull request template; planned (M0-T06, T08, T09)
```

The app target is thin. All scanning, planning, safety and execution logic lives in `ShuckKit` (PRD section 11.1), split into Tools, Scanning, Rules, Planning, Safety, Execution and History, plus a test-support target.

## Coding conventions

- Swift 6 language mode with strict concurrency checking. Scans run off the main actor in task groups; UI state and view models are `@Observable` and `@MainActor`.
- No force unwraps, `try!` or `as!` in `ShuckKit`.
- Engine APIs throw typed errors (`throws(SomeError)`) whose cases callers can act on.
- Diagnostics use `Logger` with subsystem `me.nutabi.shuck` and one category per tool and sub-tool (NFR-OBS-001). Mark paths and file names `privacy: .private` (NFR-SEC-006). No `print` in shipped code.
- The main thread is never blocked for more than 250 ms (NFR-PERF-001).
- User-facing strings live in String Catalogs; no hard-coded UI strings (NFR-L10N-001).
- Every control has a VoiceOver label and works from the keyboard. Never convey information by color alone (NFR-A11Y-001).
- Subprocesses run through `Process` with an absolute executable path, an argument array, an explicit environment and a timeout. Never `/bin/sh -c`, `system()` or `popen` (DEV-004, NFR-SEC-004).
- No network APIs (`URLSession`, Network framework, `NSURLConnection`, sockets) and no authorization or privilege APIs (NFR-SEC-001, ONB-003).
- Code is `swift-format` clean.

## Safety rules

Shuck deletes files. These rules are not negotiable, and CI enforces them where it can (ENG-006).

1. **Every mutation goes through the Execution layer.** No code outside `ShuckKit`'s Execution module may delete, move, rename or modify user files or launchd state (SAF-017). That includes the app target, other engine modules and scripts.
2. **The path guard is mandatory.** Every target passes the path guard (SAF-007) and the protected-locations list (PRD section 8.4) when planned, and is re-validated just before acting (SAF-008). Never bypass, weaken or special-case the guard, not even to make a test pass. If a guard rule looks wrong, stop and ask the owner.
3. **Tests stay inside the fixture root.** Use the fixture-root harness from test support (SAF-016). Never build test paths from `homeDirectoryForCurrentUser`, `NSHomeDirectory()`, `~` or environment variables. UI tests launch the app with the debug-only fixture-root argument (NFR-QA-002).
4. **Never touch the real home folder.** Not in tests, not in experiments and not to "try out" a deletion. Never run the app against real data to test a change.
5. **The tier sets the review and limits the method** (SAF-004). "Your data" is never deleted permanently. Data owned by a tool (Docker, simulators, Homebrew, npm, pip) is cleaned only through that tool's documented command (SAF-010).
6. **No silent failures.** Every operation is logged as an intent before it runs and as a result after (SAF-005, SAF-006). Every run ends with a per-item outcome (SAF-011).

If you are unsure whether a change could remove, move or hide user data, stop and ask in the pull request before going further.

## Dependencies and reuse

- **Apple frameworks only** (D-03). Do not add Swift packages, CocoaPods, Carthage or vendored code. CI fails if the project resolves any package dependency (NFR-SEC-002). A third-party package needs an owner-approved entry in `docs/decisions.md` first.
- **Write our own code by default.** Code or rule data from the GPL-3.0 projects Mole and DevCleaner for Xcode may be reused with attribution recorded in `docs/third-party.md`.
- **Never copy code from Pearcleaner.** Its license (Apache-2.0 with Commons Clause) is incompatible with GPL-3.0. The same applies to any project whose license is not GPL-3.0-compatible.

## Pull requests and commits

- **One pull request = one roadmap task** (ENG-002). Aim for about 200 changed lines of production code. Above 400 lines, split the task or explain why in the pull request.
- **Titles:** the pull request title and every commit title use `[<task ID>] <deliverable>`, for example `[M1-T02] PathGuard`. `main` is squash-merged, so the pull request title becomes the commit title on `main`.
- **Commit bodies:** a blank line after the title, then text wrapped at 72 characters explaining what changed and why. End with the requirement IDs, for example `Requirements: SAF-007, SAF-016`.
- **Partial tasks:** a commit that delivers only part of a task keeps the task ID in its title. Its body lists what is left, for example `Still to do for M0-T03: Swift 6 language mode and the sidebar placeholder window.`
- **Before the GitHub repository exists:** there is no remote yet, so commit straight to `main`. Once the repository and branch protection are set up (M0-T06), every change goes through a pull request (ENG-001).
- **Pull request description** (ENG-003). Until the template exists (M0-T09), use these headings:
  - **Summary.**
  - **Requirement IDs.**
  - **How to review this:** risky areas and the files to read first. Call out every change to Safety or Execution.
  - **SwiftUI concepts used:** a short explanation of each SwiftUI API or pattern the change uses, with a link to Apple's documentation.
  - **Test evidence.**
  - **Screenshots** (UI changes).
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

- Take the first unchecked task in `docs/progress.md`, in roadmap order (PRD section 13), unless the owner assigns one. Until `docs/progress.md` exists, use the M0 task list in PRD section 13.1.
- Milestones run in order. Do not start a milestone until the previous one meets its exit criteria.
- Milestones M2 to M6 are broken into tasks when each one starts. If the next milestone has no breakdown, propose one to the owner instead of starting work.
- Record progress in the same pull request: tick the task in `docs/progress.md`, and add a line for anything left over.
- Record any decision made during a task in `docs/decisions.md` (ENG-011) with ID, date, decision, rationale and rejected alternatives.

## Adding a sub-tool or a cleanup rule

**A new File Cleanup sub-tool** (FCL-003):

1. Implement the sub-tool interface in `ShuckKit`: ID, name, description, tier rules, and a scan that produces items.
2. Register it in the sub-tool registry. The sidebar and the File Cleanup landing page are built from the registry; do not edit them by hand.
3. Add its locations to the ownership map. Within File Cleanup, each location has exactly one owner (FCL-005), and the ownership test must still pass.
4. Add fixture tests for its scan and for a full run through the safety pipeline, plus a UI smoke test for its main path (NFR-QA-003).
5. Its ID goes in the history log's `tool` field (PRD section 8.5). Ask the owner to add it to the PRD.

A sub-tool must not require changes to other sub-tools or to the safety layer. If it does, stop and ask: that is a design change.

**A new Developer Junk or Caches & Logs rule** (DEV-001):

1. Add the rule as data in the engine: ID, name, description, detection, targets or tool command, tier, staleness rule, explanation, documentation link.
2. Targets must lie inside the allowed roots. Data owned by a tool is cleaned with that tool's documented command, never deleted directly (SAF-010). Tool commands follow DEV-004.
3. Add the rule's locations to the ownership map (FCL-005).
4. Add a fixture test for a path rule, or a recorded-output test with a fake tool executable for a tool rule. Never parse tool output to choose deletion targets (R-07).
5. One rule per pull request. A rule that is not in the PRD's rule table (section 9.1.3) needs the owner's approval first.
