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
- [x] M1-T15 UI smoke tests with the fixture root (NFR-QA-002, NFR-QA-003). Two pull requests (D-62).
  - [x] Isolation: debug builds have their own bundle ID, preferences and data folder, and a UI test clears the debug
    build's preferences at launch (D-70).
  - [x] Smoke tests: one UI test file per area, a smoke test for each tool's and sub-tool's main path, listed in
    `ShuckUITestCase` (D-71). Restore's came with M1-T14's last pull request (D-73).
- [ ] M1-T16 Performance baseline recorded (NFR-PERF-002)

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
- [ ] M1-T12: Move to Trash's summary disappears when the run empties the sub-tool's list. The page then shows its
  message instead of the table (D-61), and the review sheet, attached to the table, goes with it, so the user never
  sees the outcome (SAF-011). Found by M1-T14's Restore UI tests, which keep a second file listed to avoid it.

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
