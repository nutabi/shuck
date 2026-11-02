# Progress

The milestone and task checklist (PRD section 13). Each pull request ticks its task here. Milestones run in order;
M2 to M6 are broken into tasks when each one starts.

## M0 Foundations (`v0.0.1`)

Goal: repository, project skeleton, CI/CD proven end to end.

- [x] M0-T01 `LICENSE`, README skeleton, `.gitignore`, `docs/` with the PRD
- [x] M0-T02 `AGENTS.md`
- [x] M0-T03 Xcode project and app shell with sidebar placeholders
- [x] M0-T04 `ShuckKit` package skeleton, linked into the app
- [x] M0-T05 `swift-format` configuration and lint script
- [x] M0-T06 CI workflow; branch protection documented in `docs/repository-setup.md`
- [x] M0-T07 Static-check script, wired into CI
- [x] M0-T08 Release workflow, DMG and notarize scripts; secrets documented in `docs/releasing.md`
- [x] M0-T09 Pull request template, `docs/progress.md`, `docs/decisions.md`

Exit criteria:

- [x] Create `nutabi/shuck` on GitHub, push `main`, and apply `docs/repository-setup.md`.
- [x] CI green on a pull request. UI tests run on the `xcode-27` runner with ad hoc signing (D-31).
- [x] Set up the `release` environment and secrets (`docs/releasing.md`).
- [x] A `v0.0.1` tag produces a notarized draft release of the app shell (D-36, D-37).

Also ready: the local release fallback (ENG-012). The App Store Connect API key is stored on the owner's Mac as the
notarytool profile `shuck-notary`, checked against Apple's notary service on 2026-11-02. The Developer ID Application
certificate is in the owner's login keychain too, so `scripts/build-dmg.sh` can run end to end locally (not yet
exercised).

## M1 Safety core + File Cleanup (Large Files, Old Files) + Restore (`v0.1.0`)

- [x] M1-T01 Fixture-root test harness and file factory (SAF-016)
- [x] M1-T02 Path guard and protected locations, with the full test matrix (SAF-007, 8.4)
- [x] M1-T03 History log writer and reader (SAF-005, HIS-001)
- [x] M1-T04 Trash executor with re-validation and per-item outcomes (SAF-004, SAF-008, SAF-011). Adds the
  `ShuckExecutionTests` target.
- [x] M1-T05 Restore (HIS-003, HIS-004)
- [x] M1-T06 Sub-tool interface, registry and ownership map; File Cleanup landing page (FCL-001 to FCL-005). Replaces
  the app's placeholder `SidebarItem`.
  - [x] Engine: `SubTool` protocol, `ScanItem`, `ToolRegistry`, `OwnershipMap`, plans from a sub-tool (D-53).
  - [x] App: sidebar built from `ToolRegistry.standard`, File Cleanup landing page (FCL-004), FCL-002 test (D-54).
- [x] M1-T07 Personal-files scanner with shared item state (FCL-006, FCL-008 to FCL-011, SAF-014). Engine only;
  the app uses it from M1-T09 (D-55).
- [x] M1-T08 Shared results UI for personal files (FCL-012). The table and its view model; a sidebar page shows them
  from M1-T09 (D-56).
- [x] M1-T09 Large Files sub-tool (LRG-001 to LRG-003)
  - [x] Engine: `LargeFiles` and the `PersonalFilesSubTool` protocol; scans read the protected list from
    `ScanContext` (D-57).
  - [x] App: the debug-only fixture-root argument, one shared personal-files scan, the Large Files page grouped by
    top-level folder, the minimum size from `UserDefaults`, and the UI tests (D-58).
- [x] M1-T10 "Last opened" metadata with fallback (OLD-002). Engine reader and the table's Last Opened column; Old
  Files uses them from M1-T11 (D-59).
- [x] M1-T11 Old Files sub-tool (OLD-001, OLD-003). Period and minimum size from `UserDefaults`, one flat list
  oldest first (D-60). Sub-tool pages now scan when first opened and show no empty table (D-61).
- [x] M1-T12 Itemized review sheet, confirmation, summary (SAF-002, LRG-004, OLD-004). Two pull requests (D-62, D-63).
  - [x] Run: `FolderTrash` in `ShuckExecution` for tests and the app's fixture-root mode; the app's plan, run and
    removal of moved items from both lists (`TrashReview`), with no UI yet.
  - [x] UI: the "Move to Trash…" button, the review sheet with its confirmation, progress, Stop and summary, and the
    UI tests (SAF-002, D-64).
- [x] M1-T13 De-duplicated totals across sub-tools (FCL-007). Totals count each file once by file-system identity,
  so hard links count once too; the landing page shows the total above the sub-tools (D-67).
- [x] M1-T14 History view and Restore action (HIS-002). Four pull requests (D-62, D-68, D-72, D-73).
  - [x] Engine: `HistoryLog.Contents.runs()` groups the log into runs with every logged item, its outcome and whether
    Restore can undo it; restores are runs of their own.
  - [x] App: the History page lists runs (date, area, item count, size, method, status), each expanding to its items;
    the run summary links to it.
  - [x] Run: `HistoryRestore` and `AppEnvironment.restore(_:)`: the run, the check for taken paths and the answer
    passed to every request, without UI (D-72).
  - [x] UI: Restore for selected items and "Restore All", one Keep Both or Skip question for taken paths, and a
    summary (HIS-003, D-73).
- [x] M1-T15 UI smoke tests with the fixture root (NFR-QA-002, NFR-QA-003). Five pull requests (D-62).
  - [x] Isolation: debug builds have their own bundle ID, preferences and data folder, and a UI test clears the debug
    build's preferences at launch (D-70).
  - [x] Smoke tests: one UI test file per area, a smoke test for each tool's and sub-tool's main path, listed in
    `ShuckUITestCase` (D-71). Restore's came with M1-T14's last pull request (D-73).
  - [x] Notes on running and writing UI tests, moved from agents' own memory into `AGENTS.md`.
  - [x] Faster waits: `appears(within:)` and `disappears(within:)` check every 0.1 s, so the 15 UI tests take 74 s
    instead of 123 s (D-74).
  - [x] Workflows: three UI tests, one app launch each, keep every check the 15 made and take 38 s (D-75).
- [x] M1-T16 Scan performance (NFR-PERF-002, NFR-PERF-003). Owner decisions: optimize the personal-files scan, not
  only record a baseline, and no cache of scan results yet (D-78). Targets: about a million files in under 2 minutes,
  so about 8,300 entries a second, and under 1 GB of memory. The owner measures on their own Mac (`AGENTS.md`, "Scan
  performance"). Five pull requests: the measurement, one for each change below and the result (D-62).
  - [x] Measure: a finished scan logs its entry count and duration, and `vmmap` gives Shuck's peak memory. Baseline on
    the owner's Mac (M3 Pro, 18 GB, macOS 27.0.1), release build: 559,284 entries in 436 s on a second run (294 s on
    the first), about 1,300 entries a second, with a peak memory footprint of 17.1 GB. Only 25 MB was still allocated
    after the scans, so the memory is temporary objects that stay alive until the walk ends; the second run was likely
    slower because the Mac was short of memory. About 80% of the CPU time went to comparing each entry with every
    protected location.
  - [x] Faster: protected locations become keys once per scan, so matching an entry is a set lookup (D-79). A
    generated fixture of 50,501 entries took 4.0 s instead of 35.5 s in a release build, about 12,500 entries a second.
  - [x] Leaner: each entry's temporary objects are freed before the next (D-80). On the fixture with 20 packages added,
    50,522 entries, the scan's peak memory fell from 534 MB to 16 MB.
  - [x] Parallel: up to one task per processor core less one reads folders as the walk finds them, as gdu and dua do,
    instead of one task per top-level folder (D-81). On 11 cores the same fixture took 1.1 s instead of 3.9 s, about
    47,000 entries a second, with a peak of 20 MB.
  - [x] Measure again, on the same Mac with a release build: 559,921 entries in 26.2 s on a second run (26.5 s on the
    first), about 21,400 entries a second, with a peak memory footprint of 82.8 MB. At that rate a million entries take
    about 47 s, so both targets are met.

Exit criteria (PRD section 13):

- [ ] The owner finds, trashes and restores files with both sub-tools, Large Files and Old Files, on their own Mac.
- [x] Every Trash-path SAF requirement is tested. On 2026-11-02, tests named SAF-001, SAF-002, SAF-004, SAF-005,
  SAF-007, SAF-008, SAF-011 to SAF-014 and SAF-016, and the static checks cover SAF-017 (ENG-006). SAF-003, SAF-006,
  SAF-009, SAF-010 and SAF-015 are about rebuildable items, deletes, tool commands and running apps, from M2 on.
  Checked against each requirement's verification in PRD section 8 on 2026-11-02. Two parts have nothing to test in
  M1: SAF-004's warning for a "Your data" action that cannot be undone (every M1 action is a Trash move), and SAF-013's
  measured change in free space, a Should left out of the run summary by D-63.
- [x] `MARKETING_VERSION` is 0.1.0, set in a pull request (`docs/releasing.md`, D-30).
- [ ] A `v0.1.0` tag produces a notarized draft pre-release that opens without a Gatekeeper warning (D-36, D-37).

Left over from M1 tasks:

- [x] M1-T15: UI tests run the real app, which would trash fixture files into the real Trash. The app needs a fixture
  Trash for its debug-only fixture-root mode (D-47). Done in M1-T12 (D-63).
- [ ] M2: decide the owner of `node_modules` in project folders (DEV-R06). It is inside the personal-files scope
  (FCL-008), so the ownership map needs an entry for it (FCL-005, D-53). `~/go/pkg/mod` went to Developer Junk in
  M1-T07 (D-55).
- [x] M1-T11: give `FileCleanupModel`'s personal-files scan a `LastOpenedReader` with Old Files' minimum size, and
  show Old Files' list with `dateColumn: .lastOpened`, oldest first (OLD-003, D-59). Done in M1-T11.
- [x] M1-T15: UI tests share the app's real preferences domain, `me.nutabi.shuck`. AppKit saves the main window's
  frame and sidebar width there, and the next run, UI test or not, restores them (D-60). Done in M1-T15 (D-70).
- [x] M1-T14: the run summary links to History once the History page exists (D-63). Done in M1-T14 (D-69).
- [x] M1-T14: when an item's original path is taken, ask "keep both" or "skip" and pass the answer in
  `RestoreRequest` (HIS-003). The engine skips by default (D-52). Done in M1-T14 (D-73).
- [x] M1-T12: Move to Trash's summary disappears when the run empties the sub-tool's list. The page then shows its
  message instead of the table (D-61), and the review sheet, attached to the table, goes with it, so the user never
  sees the outcome (SAF-011). Found by M1-T14's Restore UI tests, which keep a second file listed to avoid it. Done
  in M1-T12 (D-77).

Carried over from M0:

- [x] Turn the engine coverage report in `scripts/test.sh` into an 80% gate (SM-4, D-32). Done in M1-T02; test support
  is reported but not gated (D-44).

Process changes during M1:

- [x] Pull requests open ready for review with auto-merge, gated by CI (D-51).
- [x] The pull request template has no Screenshots section (D-65).
- [x] CI runs lint, build and test only when a change touches code (D-66).
- [ ] Revisit CodeQL code scanning once it can build the app on macOS 27, or in M5's security pass at the latest
  (D-50).

## M2 to M6

Not broken down yet (PRD section 13).
