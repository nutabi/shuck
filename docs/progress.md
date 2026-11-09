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

- [x] The owner finds, trashes and restores files with both sub-tools, Large Files and Old Files, on their own Mac.
  Done on 2026-11-02 with the `v0.1.0` release build.
- [x] Every Trash-path SAF requirement is tested. On 2026-11-02, tests named SAF-001, SAF-002, SAF-004, SAF-005,
  SAF-007, SAF-008, SAF-011 to SAF-014 and SAF-016, and the static checks cover SAF-017 (ENG-006). SAF-003, SAF-006,
  SAF-009, SAF-010 and SAF-015 are about rebuildable items, deletes, tool commands and running apps, from M2 on.
  Checked against each requirement's verification in PRD section 8 on 2026-11-02. Two parts have nothing to test in
  M1: SAF-004's warning for a "Your data" action that cannot be undone (every M1 action is a Trash move), and SAF-013's
  measured change in free space, a Should left out of the run summary by D-63.
- [x] `MARKETING_VERSION` is 0.1.0, set in a pull request (`docs/releasing.md`, D-30).
- [x] A `v0.1.0` tag produces a notarized draft pre-release that opens without a Gatekeeper warning (D-36, D-37).
  Shuck 0.1.0 was published as a pre-release on 2026-11-02.

M1 is done. M2 starts with its task breakdown (PRD section 13).

Left over from M1 tasks:

- [x] M1-T15: UI tests run the real app, which would trash fixture files into the real Trash. The app needs a fixture
  Trash for its debug-only fixture-root mode (D-47). Done in M1-T12 (D-63).
- [ ] M2: decide the owner of `node_modules` in project folders (DEV-R06). It is inside the personal-files scope
  (FCL-008), so the ownership map needs an entry for it (FCL-005, D-53). `~/go/pkg/mod` went to Developer Junk in
  M1-T07 (D-55). M2-T13 decides it.
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
- [x] Revisit CodeQL code scanning (D-50). Done during M2: CodeQL scans the engine and the workflows on `main` (D-96).

## M2 File Cleanup: rebuildable sub-tools (`v0.2.0`)

Goal: Developer Junk with its Must rules, and Caches & Logs, with permanent Delete and tool commands (PRD section 13).
M2 starts by cleaning up M1, then builds Developer Junk before Caches & Logs (D-82).

- [x] M2-T01 M1 cleanup: the findings of `docs/m1-review.md` (TD-01 to TD-24), in nine pull requests (D-62). Changes
  to Safety and Execution go in pull requests of their own. The nine form one GitHub stack, in the order below, with
  auto-merge off; the owner merges the whole stack in one go (D-83). A tenth pull request on top follows up the
  independent review of the stack (D-93).
  - [x] Restore moves only the file it trashed (TD-01, HIS-003, HIS-004). An item whose name in the Trash a later run
    reused reads "Not restorable (Trash emptied)", and the trash record keeps the file's identity, which Restore checks
    (D-84). PRD section 8.5 has the `identity` field (D-93).
  - [x] Static checks for M2, and tests kept out of the home folder (TD-02, TD-12, TD-19, SAF-016, SAF-017). The checks
    also catch the `*at` and `_np` calls, `copyfile`, `clonefile`, `ftruncate`, `.write(toFile:)` and `openat`; only
    `ShuckExecution` may start a subprocess; test code never names the real home folder (D-85).
  - [x] Build settings and test helpers (TD-17, TD-18, TD-20 to TD-22): warnings as errors, a shared scheme, the version
    set once, fixture helpers for the history folder and the Trash, and UI tests in English with the en_US region
    (D-86).
  - [x] Scanner and History fixes (TD-03, TD-14, TD-15, TD-23): error text logged as private, protected names compared
    with case folded, other listing errors reported and counted on the landing page, a history reader that refuses a
    symlinked log or data folder, and stale text. The Group by Folder toggle is now remembered (D-87).
  - [x] Run outcomes that say why (TD-05, TD-06, SAF-012): "not accessible" kept apart from "missing", typed Trash
    errors, and stable reason codes in the log's `detail` (D-88). The wording table shared by both sheets and History
    is in the seventh layer.
  - [x] One run loop for every method, for Delete, Tool and Launchctl to plug into (TD-04, TD-11, TD-24), with Logger
    categories per tool and sub-tool (NFR-OBS-001). `PlanExecutor` hands each item to the action for its method, and a
    plan may mix methods; an item whose method has no action yet is skipped and logged. Restore runs through the same
    loop. The path guard's `realpath`, "item exists" and case-folding helpers are the only copies (D-89).
  - [x] History wording in one place (TD-06, TD-08, TD-16): one table from reason codes to words for both sheets and
    the History page, each history item with its own operation, and errors in words. A run whose items mix methods is
    labelled by all of them, and a logged failure shows its error's description (D-90).
  - [x] One page layout for every sub-tool (TD-07, TD-10, TD-13, SAF-014): pages found by tool ID, a Stop button for
    scans, and one main window. A stopped scan stays stopped until the user clicks Scan (D-91).
  - [x] A results list that merges new rows instead of sorting every row again (TD-09, NFR-PERF-001): rows built off
    the main actor, each batch merged into the sorted rows in the order a full sort gives, and Group by Folder's groups
    built once per change of the rows (D-92). Left over, as before: at 200,000 rows, a click on a column header sorts
    every row on the main actor (2 s by size, 6 s by name), and the selection footer reads every row on each selection
    change (166 ms with 1,000 selected) (NFR-PERF-001).
  - [x] Follow-up to the independent review of the stack (D-93): the history log's `identity` and `detail` in PRD
    section 8.5. Left over, for a later task: one classifier for the `lstat` errors that `Restorability` and
    `ItemSnapshot` read in opposite directions; tests for a FIFO planted as the history log, for stopping a scan while
    a batch is applied off the main actor, and for an executor's records read back through History's wording; and the
    near-copy Large Files and Old Files pipeline tests (TD-18).
- [x] M2-T02 Delete in the run loop: re-validation, nothing followed out of the target, only a folder's contents when
  the item says so, and records marked non-restorable (SAF-004, SAF-006 to SAF-008, SAF-011, SAF-014, CAC-004). Five
  pull requests in one GitHub stack, in the order below. GitHub refuses auto-merge for stacked pull requests, so the
  owner merges the stack with `gh stack merge` (D-100).
  - [x] Items that remove only a folder's contents: `ItemScope` on `ScanItem` and `PlannedItem`; a plan refuses it for
    any method but Delete, and for anything but a folder (CAC-004, SAF-004, D-100).
  - [x] The Delete action: nothing followed out of the target, logged as `delete` (SAF-006, SAF-007, SAF-011, D-101).
    Left over: no test mounts a volume inside a target, since tests may not start `hdiutil` (D-82).
  - [x] Stop interrupts re-measuring a large folder during a run or a restore (#70, SAF-014, D-102).
  - [x] Re-validation compares the file identity the scan read, so a replaced file is skipped (#71, SAF-008, D-103).
  - [x] History records are flushed with a barrier, and the log fully at the end of each run (#72, HIS-001, D-104).
- [x] M2-T03 Rebuildable items and rules as data: each item has a category, a default selection and the reason it
  cannot be selected, if any; Tool items carry a command instead of a path (DEV-001 to DEV-003, DEV-005, SAF-001,
  SAF-004). Three pull requests (D-105):
  - [x] Validated rule definitions, path patterns, structured commands and staleness defaults.
  - [x] File and command item targets, categories, default selection and disabled reasons through planning and results.
  - [x] Rule re-validation before Delete, including modification-date changes after the scan.
    `CleanupRule.scanItem` keeps the matched rule and date in the plan; tests cover an unchanged target, a recent
    item chosen explicitly, a recreated folder, contents-only Delete, changed dates, vanished detection and guard
    rejections. Rule scanners and pages still arrive in M2-T05 onwards, and command execution in M2-T10.
- [x] M2-T04 Running apps: their items cannot be selected, and are skipped if the app starts before the run; the
  fixture-root mode stubs the list, since Xcode runs during UI tests (SAF-009, CAC-003). Decides whether a running
  Xcode blocks Developer Junk's rules: per rule, as data (D-110). Left over: each rule and Caches & Logs' scan name
  their apps as they arrive (M2-T05, M2-T08, M2-T09, M2-T12), and a UI test launch argument for running apps comes
  with the first page that shows a disabled item.
- [x] M2-T05 Developer Junk with DerivedData: one item per project, selected when stale for 30 days or when its
  project is gone; the sub-tool's page (DEV-R01, DEV-008). Two pull requests (D-62):
  - [x] Engine: the DerivedData rule and Developer Junk's scan, ownership, and fixture and pipeline tests (D-112).
  - [x] App: register the sub-tool, its page, the running-apps launch argument and the UI workflow steps (D-113).
    Left over: the page's Delete button came with M2-T06; the other rules and Caches & Logs'
    scan name their apps as they arrive (M2-T08, M2-T09, M2-T12).
- [x] M2-T06 Summary confirmation: per-category totals, the item list on demand, progress, Stop and a summary; History
  shows deletions as non-restorable (SAF-003, SAF-006, SAF-011, HIS-004). Starts with one run model (phase, start,
  Stop, report) and one sheet layout that Move to Trash, Restore and the summary confirmation each fill in, instead of
  a third copy of the run scaffolding (#73). Two pull requests (D-62):
  - [x] One run model and one sheet layout; Move to Trash and Restore fill them in, with no change in behavior (D-116,
    #73).
  - [x] The summary confirmation for Delete with Developer Junk's Delete button, History's non-restorable display and
    the UI workflow steps (D-117). Left over: the run shows an indeterminate progress indicator, not a count, since
    `PlanExecutor` reports only when it ends; the measured change in free space is M2-T07 (SAF-013).
- [ ] M2-T07 The measured change in free space after a run, and a second confirmation for an oversized target
  (SAF-013, SAF-015). Proposes the threshold's basis, since measuring the home folder means walking all of it.
- [x] M2-T08 Device support files and CoreSimulator caches, one rule per pull request; stores a tool manages are
  refused (DEV-R02, DEV-R04, DEV-007). Two pull requests, a stack (D-62, D-76):
  - [x] Device support files: every version but the newest of each platform is selected (DEV-R02, D-118).
  - [x] CoreSimulator caches, and the guard refusing simulator device data and the other tool-managed stores
    (DEV-R04, DEV-007, D-119).
- [ ] M2-T09 Caches & Logs: caches, logs and app container caches, grouped by app. Caches that Developer Junk's tools
  own are left out, including those whose rule comes later (CAC-001 to CAC-008, FCL-005, SAF-010).
- [ ] M2-T10 Tool runner: an absolute path, an argument array, an explicit environment and a timeout; output and exit
  code in the history log; fake tools in test support; in the fixture-root mode, tools are found only inside the
  fixture root (DEV-002, DEV-004, SAF-006, SAF-010, NFR-SEC-004). `PlanAction.act` becomes `async` here, so a tool
  command can be stopped while it runs (SAF-014, D-93). Two pull requests, a stack (D-76):
  - [x] `PlanAction.act` and the run loop's steps are `async`; Stop reaches an action that is still running (SAF-014,
    D-93).
  - [x] The tool runner, the Tool action and its history output: a timeout stops the tool with SIGTERM, then SIGKILL;
    the exit status and the end of the output go to the result record; fake tools are scripts that test support writes
    in the fixture root, and the fixture-root mode finds tools only there (DEV-002, DEV-004, SAF-006, SAF-010,
    NFR-SEC-004, D-114, D-115). Left over for M2-T11: History shows a tool failure's output in its message until the
    item display is decided (#63); no test covers a tool that cannot be started at all, since a fake cannot fail
    `posix_spawn` without a shell.
- [ ] M2-T11 Tool rules, one per pull request: unavailable simulators, npm, pip and Homebrew; History shows each tool
  run (DEV-R03, DEV-R07 to DEV-R09). Its first pull request decides what a History item shows for each operation,
  since `path` holds a tool name for `tool` and a job label for `launchctl`: for example the tool and its command, and
  the job label, with a unit test for each operation (#63).
- [ ] M2-T12 Xcode Archives: "Your data", moved to the Trash after the itemized review, never selected by default
  (DEV-R05, SAF-002). Decides how Developer Junk shows its "Your data" items next to its rebuildable ones.
- [ ] M2-T13 Stale `node_modules` in the project folders, with a depth limit; decides who owns `node_modules` (DEV-R06,
  DEV-006, SET-003, FCL-005)

Patch releases during M2 (D-94):

- [x] `MARKETING_VERSION` is 0.1.1, set in a pull request, for M2-T01's fixes to TD-01 and TD-03 (`docs/releasing.md`).
  `CHANGELOG.md` has its notes.
- [x] A `v0.1.1` tag produces a notarized draft pre-release, which the owner checks on their Mac and publishes.
  Published on 2026-11-03; the owner confirmed the check and release on 2026-11-06.

Process changes during M2:

- [x] Release notes come from `CHANGELOG.md`, in the Keep a Changelog format, instead of GitHub's list of pull
  requests. Each pull request adds its user-facing changes under Unreleased (D-95).
- [x] CodeQL scans the engine package and the workflows on every push to `main` that changes code (D-96).
- [ ] CodeQL also scans the app target, once it can build the Xcode 27 project, or in M5's security pass at the latest
  (D-96).

Fixes from the review of `main` at 380a07d (#55 to #73):

- [x] The static checks catch the URL folder properties, `.allDomainsMask`, the date and attribute-list calls,
  `SMAppService`, FIFOs and folders created on request; `AppEnvironment`'s home has no default (#56, D-97).
- [x] Documentation-only pull requests still run the static checks, and every change checks `CHANGELOG.md`'s form
  (#57, D-98).
- [x] Closing the main window quits Shuck, and the code comment and the 0.1.1 notes say so (#55, D-99). The 0.1.1 notes
  also say that only Large Files remembers Group by Folder (#58).
- [x] M2-F01 History fixes, grouped in one pull request at the owner's request: Restore asks Keep Both or Skip when
  selected items share an original path (#59); a folder-access error is reported instead of reading as empty history
  (#69); unknown tool IDs are shown verbatim, without an empty localization key (#68, D-108). Other review issues
  remain open; M2-T04 is still the next roadmap task.
- [x] M2-F02 File Cleanup fixes, in one owner-requested pull request: review, Quick Look and Finder follow grouped
  results' display order (#60); the landing page's scan age updates while idle (#61); exclusions hide tool-owned
  stores as well as personal files (#64, D-109). M2-T04 remains the next roadmap task.
- [ ] M2-F03 Measure Move to Trash's plan building on the main actor with a few thousand selected files, using
  Instruments' Hangs instrument. If it hangs: fold the protected locations once instead of in every guard check, work
  out Old Files' period once, and build the plan off the main actor (#62, NFR-PERF-001).
- [x] M2-F04 CI cancels only pull request runs, so a push to `main` never cancels the check of an earlier merge (#65).
  Moot after M2-F05: a push to `main` no longer runs the check, only a build that warms the cache (D-111).
- [x] M2-F05 Faster CI, at the owner's request: the engine builds once, in Xcode, from a workspace and test plan; the
  macOS job no longer repeats the Linux job's checks; `main` is not tested again after a merge; and builds reuse
  Xcode's compilation cache (D-111).
- The other open review issues are part of roadmap tasks: #73 in M2-T06, #63 in M2-T11, and #66 and #67 in the
  0.2.0 release items below.

Exit criteria (PRD section 13):

- [ ] The owner reclaims space with a summary confirmation in Developer Junk and in Caches & Logs on their own Mac, and
  finds every tool run in History.
- [ ] Every Delete-path and Tool-path SAF requirement is tested: SAF-003, SAF-006, SAF-009, SAF-010, SAF-013 and
  SAF-015. SAF-004's warning for a "Your data" action that cannot be undone waits for Docker's rule (DEV-R10, M5).
- [ ] `MARKETING_VERSION` is 0.2.0, set in a pull request (`docs/releasing.md`, D-30). The same pull request words
  README's status without a version number, so it no longer goes stale at each release (#67).
- [ ] A `v0.2.0` tag produces a notarized draft pre-release (D-36, D-37). Before the tag, `build-dmg.sh` captures
  `xcodebuild`'s build settings before parsing them, and stops with a message if the version comes out empty (#66).

## M3 to M6

Not broken down yet (PRD section 13).
