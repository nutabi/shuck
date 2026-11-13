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
- [x] M2: decide the owner of `node_modules` in project folders (DEV-R06). It is inside the personal-files scope
  (FCL-008), so the ownership map needs an entry for it (FCL-005, D-53). `~/go/pkg/mod` went to Developer Junk in
  M1-T07 (D-55). Done in M2-T13: Developer Junk owns it inside the project folders (D-152).
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
  - Review of 2026-11-10 (DEV-R01): the rule's explanation says that deleting DerivedData also removes `SourcePackages`
    (Swift package checkouts, which need the network to restore) and Xcode's compilation cache. Done in M2-F26.
- [x] M2-T06 Summary confirmation: per-category totals, the item list on demand, progress, Stop and a summary; History
  shows deletions as non-restorable (SAF-003, SAF-006, SAF-011, HIS-004). Starts with one run model (phase, start,
  Stop, report) and one sheet layout that Move to Trash, Restore and the summary confirmation each fill in, instead of
  a third copy of the run scaffolding (#73). Two pull requests (D-62):
  - [x] One run model and one sheet layout; Move to Trash and Restore fill them in, with no change in behavior (D-116,
    #73).
  - [x] The summary confirmation for Delete with Developer Junk's Delete button, History's non-restorable display and
    the UI workflow steps (D-117). Left over: the run shows an indeterminate progress indicator, not a count, since
    `PlanExecutor` reports only when it ends; the measured change in free space is M2-T07 (SAF-013).
- [x] M2-T07 The measured change in free space after a run, and a second confirmation for an oversized target
  (SAF-013, SAF-015). The threshold is 25% of the startup volume's used space, the owner's choice, since measuring the
  home folder means walking all of it (D-144). Two pull requests in one GitHub stack (D-62):
  - [x] The measured change in free space after Delete, Clean Up and Move to Trash, next to the estimate, with the
    reasons it differs: local Time Machine snapshots and APFS clones, a tool's estimate, and other activity, purgeable
    space included. Items in the Trash free nothing until it is emptied, as the Trash summary already said (D-143).
    Left over: the comparison's acceptance check is a manual one on the owner's Mac (SAF-013).
  - [x] A second confirmation for a Rebuildable item larger than the threshold (SAF-015, D-144). Left over: no UI
    test shows it, since a fixture item is never a quarter of the real disk's used space; the model's tests cover it.
- [x] M2-T08 Device support files and CoreSimulator caches, one rule per pull request; stores a tool manages are
  refused (DEV-R02, DEV-R04, DEV-007). Two pull requests, a stack (D-62, D-76):
  - [x] Device support files: every version but the newest of each platform is selected (DEV-R02, D-118).
  - [x] CoreSimulator caches, and the guard refusing simulator device data and the other tool-managed stores
    (DEV-R04, DEV-007, D-119).
  - [x] Owner item (review of 2026-11-10): check on the owner's Mac whether `~/Library/Developer/CoreSimulator/Caches`
    still exists under the current Xcode. DevCleaner's maintainer reports it gone on recent Xcode versions and advises
    against cleaning these caches (PRD S77). If it is gone or risky, the owner decides whether DEV-R04 stays.
    The owner decided on 2026-11-12 that DEV-R04 stays, selected by default (D-177).
- [x] M2-T09 Caches & Logs: caches, logs and app container caches, grouped by app. Caches that Developer Junk's tools
  own are left out, including those whose rule comes later (CAC-001 to CAC-008, FCL-005, SAF-010).
  Two pull requests, a stack (D-62, D-76):
  - [x] Engine: the scan of caches, logs and container caches, each item naming its app, and the ownership map leaving
    out what developer tools and Shuck own; Caches & Logs' scan names its apps for the running-apps check (CAC-001 to
    CAC-005, CAC-008, FCL-005, D-120, D-121).
  - [x] App: register the sub-tool, its page grouped by app with Delete through the summary confirmation, the note
    about macOS clearing caches, and the UI workflow steps (CAC-002, CAC-006, CAC-007, D-122). Left over: a folder named
    after an app rather than a bundle ID, such as `Firefox`, is not tied to a running app (D-121).
- [x] M2-T10 Tool runner: an absolute path, an argument array, an explicit environment and a timeout; output and exit
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
- [x] M2-T11 Tool rules, one per pull request: unavailable simulators, npm, pip and Homebrew; History shows each tool
  run (DEV-R03, DEV-R07 to DEV-R09). Its first pull request decides what a History item shows for each operation,
  since `path` holds a tool name for `tool` and a job label for `launchctl`: for example the tool and its command, and
  the job label, with a unit test for each operation (#63). Six pull requests, a stack (D-62, D-76):
  - [x] History shows each operation as what it is: a file, a tool's command with its output, or a job label; a tool's
    end is worded from its code (#63, HIS-002, SAF-006, D-123).
  - [x] Tool items in Developer Junk: tool lookup under the scan's root, a row for a command, the confirmation's wording
    for tool commands, and tool items leaving the list after a run (DEV-002, DEV-004, SAF-003, SAF-010, D-124, D-125).
  - [x] Unavailable simulators: `xcrun simctl delete unavailable`, listed with no size, run through the fake `xcrun` of the
    UI test (DEV-R03, DEV-002, DEV-004, SAF-010, D-125).
  - [x] npm cache: `npm cache clean --force`, sized from `~/.npm/_cacache` as an upper estimate (DEV-R07, DEV-003, D-126).
  - [x] pip cache: `pip cache purge` with Homebrew's `pip` or `pip3`, sized from `~/Library/Caches/pip` (DEV-R08, D-127).
  - [x] Homebrew: `brew cleanup` with analytics and automatic update off, sized from the download cache (DEV-R09,
    DEV-007, D-128).
- [x] M2-T12 Xcode Archives: "Your data", moved to the Trash after the itemized review, never selected by default
  (DEV-R05, SAF-002). Decides how Developer Junk shows its "Your data" items next to its rebuildable ones.
  Two pull requests, a stack (D-62, D-76):
  - [x] Xcode Archives rule: one item per `.xcarchive` bundle, Trash, "Your data", never selected; Archives is a root
    of Developer Junk and owned by it (DEV-R05, SAF-002, SAF-004, SAF-009, FCL-005, D-145).
  - [x] Developer Junk's page: archives as their own group, never preselected, left out of Select All; one footer
    action for each tier, Delete and Move to Trash, each with its own count and size, and the footer no longer counts
    "Your data" with Delete (DEV-R05, SAF-002, SAF-003, D-147). Left over: the UI workflow steps for archives could
    not be run in the agent's sandbox (AGENTS.md); CI or the owner's run shows them.
- [x] M2-T14 User exclusions, moved from M5 so no release with permanent Delete ships without them: the engine applies
  them to every tool and sub-tool, and Settings gets a minimal list with a folder picker and Remove (SET-001, D-135).
  Done before M2-T13 (D-148). A stack of three pull requests:
  - [x] Exclusions in every scan: Developer Junk and the personal-files scan hide what an exclusion covers or holds;
    a test runs every sub-tool; the guard refuses a plan, re-validation skips a run's item and Restore refuses a
    folder that is excluded (D-149).
  - [x] Stored exclusions reach scans, plans and runs: `UserDefaults` storage, the guard rebuilt when the list
    changes, rows dropped on Add without a rescan, a run keeps the configuration it started with, and the UI test
    launch argument `launch(exclusions:)` (D-150).
  - [x] Exclusions in Settings: the list with Add… and Remove, the UI test steps and the changelog line (D-151).
    Left over for M5: drag and drop into the list (SET-001).
- [x] M2-T13 Stale `node_modules` in the project folders, with a depth limit; decides who owns `node_modules` (DEV-R06,
  DEV-006, SET-003, FCL-005). Done after M2-T14 (D-148): it scans the user's project folders, which must honour
  exclusions from the first release, and it reuses M2-T14's stored folder list and Settings wiring.
  - Review of 2026-11-10 (DEV-006, DEV-R06): the rule's explanation says that restoring needs `npm install` and a
    connection, since Shuck has no network. Require a lockfile next to `node_modules`; take only the top-most
    `node_modules` of a project; warn when the project uses `patch-package` or `file:` links; define "stale" by the
    newest file among the project's own files, not the folder's date.
  - A stack of three pull requests, merged with `gh stack merge` once CI passed (D-146):
    - [x] Ownership: Developer Junk owns `node_modules` inside the project folders, the personal-files scan skips it,
      and the project folders are values in the ownership map and in `DeveloperJunk` (D-152).
    - [x] The DEV-R06 rule and its scan: depth limit, top-most only, a lockfile, the project's own files for staleness,
      warnings for `patch-package` and `file:` links, and a pipeline test from scan to Delete to History (D-153).
    - [x] The project folders in Settings: stored list with the default folders, a refusal outside the home folder,
      Developer Junk and the ownership map rebuilt when the list changes, the Node.js projects' rows, the UI test steps
      and the changelog line (D-154). Left over for M5: drag and drop into the list.

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
- [x] M2-F03 Done as D-160, by building the plan off the main actor instead of measuring first (#62,
  NFR-PERF-001). It read: measure Move to Trash's plan building on the main actor with a few thousand selected files,
  using Instruments' Hangs instrument; if it hangs, fold the protected locations once instead of in every guard check,
  work out Old Files' period once, and build the plan off the main actor.
- [x] M2-F04 CI cancels only pull request runs, so a push to `main` never cancels the check of an earlier merge (#65).
  Moot after M2-F05: a push to `main` no longer runs the check, only a build that warms the cache (D-111).
- [x] M2-F05 Faster CI, at the owner's request: the engine builds once, in Xcode, from a workspace and test plan; the
  macOS job no longer repeats the Linux job's checks; `main` is not tested again after a merge; and builds reuse
  Xcode's compilation cache (D-111).
- [x] M2-F06 Review of 2026-11-10: decisions D-129 to D-135 recorded, PRD and task list updated.

Fixes from the review of 2026-11-10 (D-129 to D-135). Each is one reviewable pull request; the issues are opened
separately. Changes to Safety and Execution go in pull requests of their own (D-62):

Deferred (D-142): the open fixes below and M2-F03 wait until M2-T07 and M2-T12 to M2-T14 have merged. A complete
review of M2 then follows, in a session of its own, and decides how these fixes are done together with its own
findings. They still come before the 0.2.0 release items.

Review done on 2026-11-12: `docs/m2-review.md` (D-155). It proposes sixteen pull requests in three stacks for the open
fixes below and its own findings, and puts ten questions to the owner. No fix starts, and the open items below are
not "the next task", until the owner has approved the breakdown; the approved tasks are then listed here.

Stack 1 of the review's breakdown, approved by the owner on 2026-11-12 (six pull requests, no hard stop;
`docs/m2-review.md` has each one's scope). Stack 2 and stack 3 are below.

The first two merged as one GitHub stack (#152, #153), after a stop at the owner's request. The owner then said to go
on, with Sonnet agents for the implementation and Haiku agents for research; the coordinating session reviews each
change and writes the documents. The other four are a second stack, in the order below.

- [x] An unknown app's cache starts unselected (R-01, CAC-009, D-156): part of M2-F19.
- [x] `npm` and `pip` stay off the network, and `simctl` needs Xcode (R-02, R-13, DEV-002, DEV-004, D-157): the
  rest of M2-F19's code items.
  - [x] Owner item: on the owner's Mac, check that `npm cache clean --force`, `pip cache purge` and `brew cleanup`,
    run from Developer Junk, open no network connection (for example with `nettop` or Little Snitch). An agent may
    not run real tools (DEV-004, NFR-SEC-001). Checked by the owner on 2026-11-12.
- [x] M2-F21 A stray `node_modules` in a project folder does not hide the projects below it (R-08, DEV-006,
  D-158).
- [x] Scans report what they cannot measure (R-10, M2-F17, #118, D-159). Left over: a folder measured with an
  unreadable subfolder still shows a size that is too small, with no mark, and ONB-002's banner that lists the
  folders is M5.
- [x] String Catalog entries and a check for missing ones (R-09, M2-F17, #116, D-161), with DEV-R01's explanation,
  which now says that the project's Swift package checkouts go too. This closes M2-F17. Left over: the check's blind
  spots, which its header lists (a bare literal passed to a parameter typed `LocalizedStringResource`, and raw
  strings).
- [x] Plans are built off the main actor (R-07, R-17, M2-F03, #62, D-160). This closes M2-F03 without the Instruments
  measurement: the review's probe measured 1.7 s for 5,000 files. Left over: no test shows that a second click
  while a plan is being built starts no second plan, since it depends on task scheduling; the buttons are disabled
  meanwhile.

Stack 2 of the review's breakdown, approved by the owner on 2026-11-12 with the review's recommended answers to
questions 1, 3, 5 and 7 (D-162). Each change to Safety or Execution is a pull request of its own (D-62); the seven
form one GitHub stack, in the order below. Sonnet agents implement each one, and the coordinating session reviews
it and writes the documents.

- [x] M2-F22 Every rule-based item needs its rule: a plan of Developer Junk or Caches & Logs refuses an item without
  a rule match, Trash included, the executor skips one, and a project folder that no longer resolves inside the home
  folder is no allowed root (R-03, R-16, SAF-007, SAF-008, D-163).
- [x] M2-F14 The tool runner never signals a process that has not launched, and History says that a stopped tool's
  processes may still be running (R-05, R-13, #114, #127 in part).
- [x] M2-F15 Delete with one descriptor at a time, and Restore removes the folders it created when its move fails
  (R-11, #119, #120).
- [x] M2-F12 One running instance, and a locked history log (R-06, SAF-018).
  - [x] Owner item: open the release build twice; the second launch brings the first window to the front and quits
    (SAF-018's manual check, D-166). Checked by the owner on 2026-11-12.
- [x] M2-F13 An interrupted Trash item can be restored (R-04 steps 1 and 2, R-12's interrupted-run test, #115).
- [x] M2-F13 Shuck asks before quitting during a run (R-04 step 3, #115).
  - [x] Owner item: press ⌘Q during a long Move to Trash; the question appears, Stop and Quit finishes the item and
    quits, and History lists the run. Then try the close button during a run: a sheet is expected to block it
    (D-168). Checked by the owner on 2026-11-12.
- [x] M2-F23 A skip caused by an exclusion says so (R-14, SET-001).

Stack 3 of the review's breakdown, approved by the owner on 2026-11-12 with the review's recommended answers to
questions 6, 8 and 9 (D-170). Three pull requests in one GitHub stack, in the order below. The first two change
`scripts/`, so the stack waits for the owner's go-ahead before it merges (D-170).

- [x] M2-F18 Static checks: only tracked files, calls wrapped across lines, the APIs of #123, and every Must SAF
  requirement named in a test or a script (R-12, R-18, #122, #123, D-170). This closes M2-F16. Left over: #122's
  other proposals (every rule on every Swift file by default, a second local package, `.binaryTarget(`); a self-test
  case for each older alternative of each rule and a remote URL held in a variable (#123); a call wrapped over more
  than 15 lines is matched only in parts.
- [x] M2-F18 Release scripts fail when a check fails (R-18, #66, #121, D-171). This closes M2-F18. Left over: the
  notarization path and the new `stapler` and `spctl` checks run first at the next release.
- [x] M2-F18 `build-dmg.sh` reads the build settings for the archive's destination, so `xcodebuild` no longer warns
  that several Macs match (the owner's run of 2026-11-12).
- [x] M2-F18 The release workflow gives its write token to the step that creates the draft only, keeps no checkout
  credentials and writes the signing keys readable by their owner only. The
  environment's reviewer stays optional, and #125 is closed as not planned (D-173).
- [x] M2-F24 PRD rows, `AGENTS.md` rules and issue housekeeping (R-15, R-19, R-20, #124 and #125 in part, D-172).
  - [x] Owner item: add `.github/CODEOWNERS` and the `v*` tag ruleset (`docs/repository-setup.md`, #124, #125).
- [x] M2-F25 A tool command is skipped when an exclusion added after planning covers its tool's folder (SET-001,
  SAF-008, D-150).

- [x] M2-F07 Synced files stay listed and are marked: the scan records `isUbiquitousItemKey`, the results show a
  "Synced" mark with text, the review sheet warns that moving the file to the Trash removes it from the user's other
  devices, and evicted placeholders are skipped for packages and folders too (FCL-010, FCL-012, SAF-002, D-129).
  Done as D-137, with a UI test launch argument that marks fixture files synced. Left over, for the owner: check on a
  Mac with iCloud's Desktop & Documents that Large Files still lists downloaded files in `~/Documents`, marked
  "Synced", since no test can read what iCloud reports for a real folder.
- [x] M2-F08 Old Files uses the latest of the last-used, modification and added dates, names the date that decided in
  the reason, and uses the newest direct child for a package or folder (OLD-002, D-130, R-18). Done as D-140; the app's
  fixture-root mode ignores added dates, since a UI test makes every file just now. Left over: no UI test can show the
  "Added" reason or label.
- [x] M2-F09 The personal-files scan skips `.git` folders at any depth and does not enter another volume (FCL-008,
  D-131, D-135). Done as D-139: an entry whose volume cannot be read is skipped too.
- [x] M2-F10 Path guard: refuse a folder that contains a protected bundle or name among its direct children, and a
  Trash target that is itself a mount point; the same pull request words FCL-011's examples in code and text
  (SAF-007, section 8.4, D-135). Safety change. Done as D-136: an unreadable folder is refused too and reads as "Not
  accessible", and the mount-point rule covers every method; FCL-011's code already named the Go module cache only.
  Left over: a scan can still list a folder the guard refuses, such as one holding a Photos library, and one such row
  refuses the whole plan. The scanner could mark such folders read-only.
- [x] M2-F11 Re-validation compares the modification date of every item, Trash or Delete, using the deep date for
  contents-only items, and a plan refuses a Delete item without a rule match (SAF-008, D-132). Safety and Execution
  change. Done as D-141.
- [x] M2-F12 One running instance: a second launch of the same build activates the first and quits, and the history log
  is locked with `flock` while a run writes it (SAF-018, D-135).
- [x] M2-F13 A crash or quit between a Trash move and its result record leaves the item unrestorable, and nothing guards
  Cmd-Q during a run. Write what a Restore needs before the move, or recover it at the next launch, and ask before
  quitting during a run (SAF-005, SAF-006, HIS-001, #115). Execution change.
- [x] M2-F14 `ToolRunner` can call `terminate()` on a process that has not launched yet (`ToolRunner.swift`, #114).
  Execution change.
- [x] M2-F15 Execution fixes: Delete holds one file descriptor per folder level, and a failed Restore leaves the parent
  folders it created behind (SAF-006, HIS-003, #119, #120). Execution change.
- [x] M2-F16 The two acceptance checks the PRD names (D-133): a test that stops a run between an intent and its result
  record and checks History and Restore (HIS-001), and a static check that every Must SAF requirement built so far is
  named in a test (NFR-QA-001). The interrupted-run test is done, with M2-F13's first pull request
  (`InterruptedRunTests`, D-167), and the static check with stack 3 (D-170).
- [x] M2-F17 Reports that go missing: unreadable folders vanish silently from Developer Junk scans (SAF-011, SAF-012,
  ONB-002), and two History strings are missing from the String Catalog (NFR-L10N-001, #116, #118). Done in stack 1
  (D-159, D-161).
- [x] M2-F18 Scripts: `build-dmg.sh`'s `get-task-allow` check passes when `codesign` fails, `notarize.sh` aborts before
  printing Apple's log, and `static-checks.sh` scans untracked folders such as `.claude/worktrees` (NFR-SEC-003,
  ENG-006, #121, #122).
- [x] M2-F19 The review of 2026-11-10 read `main` before M2-T06, M2-T09 and M2-T11 merged, so four of the requirements
  it added were written without their code. Check each against the code and fix the code or the PRD: `npm` and `pip` run
  with no setting that stops update checks, where `brew` has them (DEV-004, D-126 to D-128); CAC-009 leaves an unknown
  app's cache unselected, where D-120 selects any cache that is stale for 30 days; the confirmation's item list shows
  each item's full path, so two DerivedData folders of one name differ (SAF-003, D-117); and `/usr/bin/xcrun` exists
  without Xcode and can raise the install prompt, so finding it is not detection (DEV-002, D-124). Tools installed
  through nvm, asdf, mise, fnm, volta or pyenv are not found (D-124): say so in the PRD or find them. Done in stack 1:
  npm and pip run offline and `simctl` needs Xcode (D-157), an unknown app's cache starts unselected (D-156), the
  confirmation shows each item's folder from the home folder (SAF-003), and DEV-002 says that tools installed through
  nvm and the like are not found.
- [x] M2-F20 The owner's test of `main` on 2026-11-11: tool commands quote only the words that need it, a locked row
  names the running app ("Xcode is running"), a DerivedData row shows its project's path, and every sub-tool list has
  Select All and Select None (CAC-003, SAF-002, SAF-009, D-138). Left over: no UI test checks the project path or
  the buttons yet, and the checkbox lists have no keyboard shortcut for them.

Exit criteria (PRD section 13):

- [x] The owner reclaims space with a summary confirmation in Developer Junk and in Caches & Logs on their own Mac, and
  finds every tool run in History. The owner confirmed it on 2026-11-12.
- The other open review issues are part of roadmap tasks: #73 in M2-T06, #63 in M2-T11, and #66 and #67 in the
  0.2.0 release items below.
- [x] User exclusions (SET-001) work in every tool and sub-tool, with a minimal list in Settings (M2-T14, D-135).
- [x] Every Delete-path and Tool-path SAF requirement is tested: SAF-003, SAF-006, SAF-009, SAF-010, SAF-013 and
  SAF-015. SAF-004's warning for a "Your data" action that cannot be undone waits for Docker's rule (DEV-R10, M5).
  Checked on 2026-11-12: each ID is named in tests of the Delete or Tool path: engine tests (`DeleteActionTests`,
  `ToolRunTests`, `RunningAppsTests`, `PlanTests` and the rule tests), app tests (`SummaryConfirmationTests`,
  `FreeSpaceTests`) and the UI workflows of Developer Junk and Caches & Logs.
- [x] `MARKETING_VERSION` is 0.2.0, set in a pull request (`docs/releasing.md`, D-30). The same pull request words
  README's status without a version number, so it no longer goes stale at each release (#67).
- [x] A `v0.2.0` tag produces a notarized, published pre-release once the owner approves the `release` environment
  (D-36, D-37, D-174). Before the tag, `build-dmg.sh` captures
  `xcodebuild`'s build settings before parsing them, and stops with a message if the version comes out empty (#66).
  Checked on 2026-11-12: the pre-release is published.

## M3 Applications (`v0.3.0`)

Goal: an uninstaller with leftovers found by confidence, running-app handling and LaunchAgent unloading, with Restore
(PRD section 13). It is the first use of the launchctl runner (APP-011), which M4's Startup Items reuses (STA-005).
This breakdown is an agent proposal, open for the owner's review (D-178). It is provisional: the PRD says to measure
OQ-08 before M3 is broken down, and that measurement is still open, so M3-T04 and the order of the later tasks may
change with it. Issue fixes sit in the task of the feature they touch; the other fixes and the left-overs from M1 and
M2 that no task owned are in M3-T01.

Owner prerequisites, before the tasks that need them:

- [x] The `v0.2.0` tag exists and its pre-release is published (M2's last exit criterion), on 2026-11-12.
- [ ] Owner item: measure how many of the owner's own apps Shuck could remove (OQ-08, R-16). It tells whether APP-005's
  blocked uninstall is the common case. Needed before M3-T04.
- [ ] Owner decision: whether leftovers in Application Support and Group Containers are ever preselected (OQ-07).
  APP-003 stays as written until the owner decides. Needed before M3-T03 sets default selection.
- [ ] Owner approval of Applications' allowed roots, a hard stop (D-170): `/Applications`, `~/Applications`, each
  `~/Library` leftover folder APP-002 names, and `~/Library/LaunchAgents`. Needed before M3-T02 is implemented.
- [ ] Owner approval of dependencies between items in one run, a change to the run loop and so to the safety layer
  (D-170): a failed `bootout` skips that agent's plist (APP-011), and an app bundle that fails to move to the Trash
  leaves its leftovers alone (APP-005). Needed before M3-T05's dependency pull request.
- [ ] Owner approval of Restore re-enabling a restored LaunchAgent after the user confirms, a hard stop (D-170): it adds
  a Launchctl enable action and changes Restore (APP-011, HIS-005, STA-005). Needed before M3-T05's re-enable pull
  request.
- [ ] Owner decision on a mismatch in the PRD: APP-011 and STA-005 check a "fixture agent in a test domain", but a test
  cannot run the real `launchctl`, which would change the user's real launchd state (safety rule 4). Tests run a fake
  `launchctl` through the runner inside the fixture root, as they run other fake tools, and the real `bootout` is an
  owner check on the owner's Mac (see the exit criteria). The owner words the checks in the PRD.

Tasks:

- [ ] M3-T01 Fixes carried from M2, so the feature tasks start from a clean `main`. Independent pull requests, and one
  outside any stack:
  - [x] Developer Junk rows are clipped after a rescan (#185).
  - [x] Changing the project folders during a Developer Junk scan leaves rows that make the plan fail: the model drops
    rows from an older project-folder revision (#177, SET-003, D-154).
  - [x] The single-instance check runs in a release build too (#178, SAF-018, D-166).
  - [x] Homebrew Cleanup reports what it removed, measured on the download cache after the run, not the whole
    cache (#184, DEV-R09, D-128, D-184). Still open: the item is preselected again at the same estimate.
  - [x] `brew cleanup` is hidden when any folder it cleans is excluded, not only its download cache (#176, SET-001,
    D-149, D-183).
  - Left-overs from M1 and M2 that no task owned (D-178):
  - [x] Large result lists (NFR-PERF-001, M2-T01): at 200,000 rows a click on a column header sorts every row on the
    main actor (2 s by size, 6 s by name), and the selection footer reads every row on each selection change (166 ms
    with 1,000 selected). Move the sort off the main actor and keep the footer's totals incrementally. Done as D-181.
  - [x] Engine: one classifier for the `lstat` errors that `Restorability` and `ItemSnapshot` read in opposite
    directions (M2-T01, D-93), and `ItemSnapshot.read` gets an enumerator error handler, so an unreadable subfolder
    marks the size as incomplete instead of giving a too-small size with no mark (R-10, SAF-012). `matches` and `check`,
    which Execution reads, keep their behavior. Done in the engine: `LstatFailure` and `ItemSnapshot.isComplete`
    (D-182). Left: show a mark where a size is listed whose snapshot is incomplete.
  - [x] Engine tests that M2-T01 left (D-93, TD-18): a FIFO planted as the history log, stopping a scan while a batch
    is applied off the main actor, an executor's records read back through History's wording, and the near-copy Large
    Files and Old Files pipeline tests merged into one.
  - [x] Owner review first, since it changes what a plan accepts: a scan can list a folder the guard refuses, such as
    one holding a Photos library, and that one row makes the whole plan refuse. The scanner marks such a folder as
    not selectable, with the reason (M2-F10, SAF-007, SAF-011).
  - [x] App tests (M2-F20, R-07): a UI test for a DerivedData row's project path and for Select All and Select None,
    a keyboard shortcut for them (NFR-A11Y-001), and a test that a second click while a plan is being built starts no
    second plan.
  - Left out on purpose: the run sheet's indeterminate progress (M2-T06). Showing a count means `PlanExecutor` reports
    each item while it runs, which changes the run loop, a hard stop (D-170), for a cosmetic gain; it waits for a reason
    to touch the run loop for the owner to approve.
  - [x] Standalone pull request, outside any stack, with no auto-merge, since it changes `scripts/` and `.github/`:
    the owner reviews and merges it (D-170). `CHANGELOG.md`'s Unreleased section is checked at the tag (#180); the
    Release configuration and the engine's macOS 26 build are built in CI before a tag (#126, NFR-COMP-001, D-06);
    the String Catalog check also finds a bare literal passed to a `LocalizedStringResource` parameter and raw strings
    (R-09, NFR-L10N-001, D-161); and the static checks take the proposals of #122 and #123 (R-18, ENG-006). #126 was an
    M5 note (D-133, D-172); it moved here on the owner's instruction (D-178). Built as D-180. Left for the owner: #122's
    proposals to apply every rule to all non-test Swift files by default and to flag a second local package (D-170 did
    not approve them), and making the `Engine on macOS 26` job a required check.
- [ ] M3-T02 Engine: Applications' shape and the app inventory (APP-001, APP-009's data, SET-001, SAF-009, CAC-003).
  Owner approval of the allowed roots comes first, a hard stop. Three pull requests:
  - [ ] Applications' shape and the first part of the scanner. It records in `docs/decisions.md`, as an agent choice
    open for review, whether Applications is a `SubTool` conformer or its own entry point through
    `Plan(tool:allowedRoots:items:pathGuard:run:requiresRule:)`; `Plan(subTool:)`, `ExclusionsTests`,
    `ToolRegistryTests` and `FileCleanupModel` assume sub-tools, so every later task depends on the choice. It then
    builds on the choice: apps in `/Applications` and `~/Applications` (one level of subfolders) with name, bundle ID
    and size, leaving out `/System/Applications`, apps protected by System Integrity Protection and Shuck itself. App
    folders are inputs, so tests never read the real `/Applications`. Test support gets a fake app bundle with a real
    `Info.plist`.
  - [ ] The rest of the inventory: version and last opened, the exclusions (the scan hides what an exclusion covers or
    holds, and joins `ExclusionsTests`, D-149), and the data APP-009 sorts by.
  - [ ] Owner opt-in, which D-121 (3) left for the owner to ask for: a cache folder named after an app, such as
    `Firefox`, is tied to its running app through the inventory's name-to-bundle-ID map, so it is disabled while the
    app runs (SAF-009, CAC-003, D-121).
- [ ] M3-T03 Engine: leftovers with confidence (APP-002 to APP-004, OQ-07, R-16). Two pull requests:
  - [ ] Related user-level items by exact bundle ID, and Group Containers through the app groups in the app's
    entitlements, each with a confidence and the reason for it. Only High items are selected, subject to the owner's
    OQ-07 decision (APP-002, APP-003, R-05). The leftover roots are inputs, so fixtures never read the real `~/Library`.
    Reading other apps' `Containers` can make macOS ask for permission, and each container prompts separately
    (PRD S78, R-16): the scan treats a refusal as an unreadable folder and reports it (SAF-012), and the page says why
    in M3-T08.
  - [ ] Medium and Low matches by name, and system-wide items listed as "Needs admin" and never planned (APP-003,
    APP-004).
- [ ] M3-T04 Engine: removability (APP-005, R-16). Needs the OQ-08 measurement first. One pull request: it decides
  whether the user can remove the bundle (root-owned, not writable, App Management permission missing) and gives the
  reason. A check before the run may not see a missing permission, so M3-T05's dependency covers that case.
- [ ] M3-T05 Execution: the launchctl runner (APP-011, STA-005, SAF-005, SAF-006, SAF-014, NFR-SEC-004, D-82). Only
  `ShuckExecution` changes (and Restore's, in the re-enable pull request), in pull requests of their own:
  - [ ] A tool finishing as Stop or a timeout fires can be reported as stopped (#179, SAF-014). The same pull request
    adds the test for a tool that cannot be started at all, which M2-T10 left (a fake cannot fail `posix_spawn`
    without a shell, so the test needs a seam in the runner).
  - [ ] The tool runner starts commands with `posix_spawn` and `POSIX_SPAWN_SETPGROUP`, so Stop and a timeout signal
    every process a tool started (#127, D-164). It was deferred to M5 (D-162, D-164) and moved here on the owner's
    instruction (D-178). History stops saying that such processes may still be running.
  - [ ] `LaunchctlRunner` and a Launchctl action for `bootout` in the `gui/<uid>` domain: an agent that is not loaded
    is trashed directly, and the result is logged with the job label. It is shaped for STA-005's Disable, Enable and
    Remove, which M4 adds. Agent choice, open for review: whether it reuses `ToolRunner`. Tests run a fake `launchctl`
    through the runner inside the fixture root.
  - [ ] Owner approval first, a hard stop: dependencies between items in one run, so a failed `bootout` skips that
    agent's plist and a bundle that fails to move leaves its leftovers alone (APP-005, APP-011, SAF-011). The skip is
    logged with its reason.
  - [ ] Owner approval first, a hard stop, since it changes Restore: a Launchctl enable (bootstrap) action, and
    Restore re-enabling a restored agent after the user confirms (APP-011, HIS-005, STA-005 Enable). History's
    `Restorability` today says a `launchctl` item is "reversed by the opposite action", and no such action exists.
- [ ] M3-T06 Engine: the uninstall (APP-007, APP-011, HIS-005, SAF-011, R-16). Two pull requests:
  - [ ] The uninstall plan: the bundle, the selected leftovers and the agents in one run, `bootout` before the plist
    moves, and the refusals from M3-T04. A refusal from macOS about another app's container is a skipped item with its
    reason, not a failed run (PRD S78).
  - [ ] The end-to-end fixture test through the run, History, Restore and the re-enable confirmation (HIS-005).
- [ ] M3-T07 Quit a running app (APP-006, SAF-009). One pull request: "Quit <App>" with a normal request, continuing
  only after the app has exited and never forcing it. Agent choice, open for review: `NSRunningApplication.terminate()`
  sends a request and changes no file or launchd state, so it may live in the app target; the pull request records
  where. The test uses a stubbed list of running apps.
- [ ] M3-T08 App: the Applications page (APP-001, APP-004 to APP-007, APP-009, HIS-005, NFR-A11Y-001, NFR-L10N-001).
  Four pull requests, all in the app target:
  - [ ] The page and model for Applications, with the list (icon, name, version, size, last opened), sort and search
    (APP-001, APP-009). It generalizes the page and model for a second tool: `FileCleanupModel.scan(_:)`,
    `scanItems(_:urls:)` and `confirmRebuildable(_:)` take an `any SubTool` from the caller, and they take a tool ID
    and look it up instead (R-17). The tool leaves `.planned(milestone: "M3")`, and `FirstLookUITests`, which asserts
    the placeholder, and `ToolRegistryTests` change. A UI test launch argument sets the app folders, so UI tests
    never read the real `/Applications`, and `AGENTS.md`'s UI test notes document it.
  - [ ] The selected app's leftovers with confidence and reasons, "Needs admin" rows with Show in Finder, the blocked
    reason, and the note that macOS may ask for permission to read other apps' containers (APP-002 to APP-005, R-16).
  - [ ] The itemized review, Quit and the uninstall run (APP-006, APP-007).
  - [ ] History showing the run and restoring it, with the re-enable confirmation (HIS-005), the UI workflow steps and
    the changelog line.
- [ ] M3-T09 Should and Could requirements, each its own pull request, done last:
  - [ ] Package receipts (APP-008). Owner decision first: `pkgutil` can run only in `ShuckExecution` (D-82) and
    `ShuckKit` cannot import it, so the scan needs an injected protocol, or the receipts are read without a
    subprocess.
  - [ ] The code-signing developer name (APP-010), which is Could.

Exit criteria (PRD section 13):

- [ ] The owner uninstalls an app with its leftovers on their own Mac and restores it from History.
- [ ] Every Launchctl-path and Applications SAF requirement is tested, and each ID is named in a test (NFR-QA-001).
- [ ] Owner check on the owner's Mac: a real `launchctl bootout` of a LaunchAgent that an uninstall removes, and the
  re-enable after Restore, since a test cannot run the real `launchctl` (APP-011, HIS-005).
- [ ] `MARKETING_VERSION` is 0.3.0, set in a pull request (`docs/releasing.md`, D-30).
- [ ] A `v0.3.0` tag produces a notarized, published pre-release once the owner approves the `release` environment
  (D-36, D-37, D-174).

## M4 to M6

Not broken down yet (PRD section 13). Notes from the review of 2026-11-10 for when each milestone is broken down. The
notes for M3 Applications moved to its section above (OQ-07, OQ-08, R-16). #127 and #126 moved to M3 as well (D-178).

M4 Startup Items:

- `SMAppService.openSystemSettingsLoginItems()` is allowed in the app target by the static check; every other use
  stays an error outside `ShuckExecution`. D-97 said M3; Startup Items is M4. Change `scripts/static-checks.sh` and its
  self-test in the pull request that adds the button (STA-004, D-134).

M5 Overview, onboarding, settings, polish:

- Drag and drop into Settings' list of excluded folders, which SET-001 names; M2-T14 built the folder picker (D-151).
- Clear History: "Clear History…" in Settings, which says that Restore is lost for the cleared runs (HIS-008, SET-007,
  D-135).
- The localization and compatibility pass builds two checks (D-133): hard-coded UI strings and stale String Catalog
  keys (NFR-L10N-001), and the engine's macOS 26 build as a required check (NFR-COMP-001, D-06).
- Info.plist usage strings are optional but recommended, and none are set today: `NSDesktopFolderUsageDescription`,
  `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, and later `NSAppBundlesUsageDescription`
  and `NSAppDataUsageDescription` (ONB).
- Docker (DEV-R10): never `--volumes` or `-a`; prefer `docker builder prune` (PRD S72); the host's `Docker.raw` does not
  shrink, so the measured change can be zero.
- Finder's "Put Back" for items Shuck trashes is unverified on macOS 27; the UI says "Restore in Shuck" (HIS-006).
