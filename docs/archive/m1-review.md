# M1 tech-debt review

A review of the whole code base at the end of M1, on 2026-11-03, at `main` f7e6ded ("[M1] Milestone done"). M2-T01
fixes its findings (`docs/progress.md`, D-82). Line numbers refer to that commit.

The review read every Swift file in `Shuck/`, `ShuckTests/`, `ShuckUITests/` and `Packages/ShuckKit/` (sources, test
support and tests), both String Catalogs, `Package.swift`, both `.swift-format` files,
`Shuck.xcodeproj/project.xcproj`, every script, both workflows, the pull request template, `README.md`, `AGENTS.md`
and the parts of `docs/` that describe code. It also built, linted and tested (results at the end). Five findings rest
on probes: small scripts, or tests added to a copy of the package outside the repository.

**Counts:** 3 High, 8 Medium, 13 Low (24 findings).

Severity: **High** means a bug, a safety or data-loss risk, or a broken AGENTS.md or PRD rule. **Medium** means a
maintainability or correctness risk that M2 to M4 will hit. **Low** means consistency or polish. "Safety/Exec" means
the fix touches Safety or `ShuckExecution`, so it needs its own pull request (D-62).

## Findings at a glance

| ID | Sev | Finding | Main location | Size (prod lines) | Safety/Exec |
|---|---|---|---|---|---|
| TD-01 | High | Restore can move another run's file when a Trash name is reused | `ShuckKit/History/Restorability.swift:92-120` | ~10 (+20 with identity) | Yes (History decides what Restore moves) |
| TD-02 | High | Static checks miss `*at`/`_np` mutation calls, `.write(toFile:)`, `Process`, and the real home folder in tests | `scripts/static-checks.sh:62-77` | ~40 bash + ~10 Swift | Yes |
| TD-03 | High | A public log line contains file and folder names | `Scanning/PersonalFilesScanner.swift:335-336` | 1–2 | No |
| TD-04 | Medium | One hand-written run loop per executor; Trash-specific outcomes; other methods skipped unlogged | `ShuckExecution/TrashExecutor.swift:30-57` | ~150 | Yes |
| TD-05 | Medium | Errors during re-validation and moves lose their cause, so a run can't report "Not accessible" | `TrashExecutor.swift:69,74-75` | ~60 | Yes |
| TD-06 | Medium | The log's `detail` is Swift reflection output that the History page parses back | `TrashExecutor.swift:95`, `HistoryView.swift:193-206` | ~80 | Yes (engine part) |
| TD-07 | Medium | The File Cleanup model and pages are built around personal files only | `Shuck/FileCleanupModel.swift:101-116,246-263` | ~150–250 | No |
| TD-08 | Medium | A history run takes its one operation from its first record | `History/HistoryRun.swift:49,114` | ~45 | No |
| TD-09 | Medium | The results list re-sorts every row on every batch, on the main actor | `Shuck/PersonalFilesResults.swift:45-53` | ~40 | No |
| TD-10 | Medium | Scans can't be stopped from the app | `Shuck/FileCleanupModel.swift:101-157` | ~40 | No |
| TD-11 | Medium | Logger categories are per component, not per tool and sub-tool; the app logs nothing | `TrashExecutor.swift:21` | ~20 | Yes (logging only) |
| TD-12 | Low | The fixture-root gate uses `resolvingSymlinksInPath`, so one of its accepted shapes never matches | `Shuck/AppEnvironment.swift:141,147` | ~10 | Test isolation |
| TD-13 | Low | Every window shares one navigation and one selection | `Shuck/ShuckApp.swift:10,38-40` | ~5 | No |
| TD-14 | Low | Scanner: other listing errors are silent; protected-name check is case-sensitive; a comment is wrong | `PersonalFilesScanner.swift:264,334-338` | ~15 | No |
| TD-15 | Low | The history reader follows a symlinked log, though the writer refuses one | `History/HistoryLog.swift:76-86` | ~10 | No |
| TD-16 | Low | Raw error text is shown in the UI | `TrashReviewSheet.swift:123,153` | ~40 | No |
| TD-17 | Low | A SAF-014 test cancels its own task and is reported "cancelled" | `ShuckExecutionTests/TrashExecutorTests.swift:191` | 0 (test) | No |
| TD-18 | Low | Test setup is repeated across 10 files | `ShuckExecutionTests/*` | 0 (~40 test) | No |
| TD-19 | Low | No test names SAF-017 (NFR-QA-001) | `scripts/static-checks-test.sh` | 0 | No |
| TD-20 | Low | UI tests depend on the Mac's language and region | `ShuckUITests/ShuckUITestCase.swift:36-44` | 0 (2 test) | No |
| TD-21 | Low | Project settings: no shared scheme, warnings don't fail, version set three times, unused setting | `Shuck.xcodeproj/project.xcproj` | 0 (settings) | No |
| TD-22 | Low | The app and the engine compile with different concurrency rules | `Packages/ShuckKit/Package.swift:15-25` | ~5 + fallout | No |
| TD-23 | Low | Stale README, comments and one decision rationale | `README.md:15`, `TrashReview.swift:9` | ~10 | No |
| TD-24 | Low | `realpath`, "item exists" and case-folding helpers are duplicated | `ShuckExecution/RestoreExecutor.swift:151-160` | ~20 | Yes (trivial) |

## High

### TD-01 Restore can move another run's file when a Trash name is reused

- **Severity:** High. **Confidence:** verified (ran a probe). **Revisits D-52.**
- **Locations:**
  - `Packages/ShuckKit/Sources/ShuckKit/History/Restorability.swift:92-120`. `entries()` records each trash result in
    `inTrash[trashedPath]` (line 100), but an earlier entry for the same trashed path stays `.restorable`.
    `checkTrash` (lines 119 and 124) only checks with `lstat` that something exists at the path.
  - Downstream: `Shuck/HistoryView.swift:128-130` selects by trashed URL. `ShuckExecution/RestoreExecutor.swift:87-93`
    checks only that the item is directly inside the Trash and within the size tolerance.
- **The scenario:** run A trashes `~/Downloads/report.pdf` to `~/.Trash/report.pdf`, and the user empties the Trash.
  Later, run B trashes `~/Documents/report.pdf`, and the Trash gives it the free name `report.pdf` again. History now
  lists A's item and B's item as restorable. Restoring A's row moves B's file to A's original place.
- **What History shows afterwards:** the restore record is matched to the latest trash record for that path, so B's
  item reads "Restored", although nothing is at `~/Documents/report.pdf`, and A's item reads "Not restorable (Trash
  emptied)". The size check passes whenever the two files are within 64 KiB or 1% of each other, which is common for
  same-named files such as a re-downloaded installer. Selecting both rows sends two requests with the same trashed URL,
  which also gives duplicate list IDs in `HistoryRestoreSheet.swift:52,96`.
- **Evidence:** a probe test in a copy of the package ran the scenario above with `TrashExecutor`, `FolderTrash` and
  `RestoreExecutor`:
  - before the restore, both entries were `restorable`, each with trashed URL `.Trash/report.pdf`;
  - restoring A's entry returned `.restored(…/Downloads/report.pdf)`, and that file now exists;
  - after the restore, A's entry read `trashEmptied` and B's read `restored`.
- **Why it matters:**
  - HIS-003 and HIS-004: an item no longer in the Trash must read "Not restorable".
  - P-1, and the spirit of SM-2: acting on an item outside what the user reviewed.
  - D-68: Restore starts without a confirmation, so the user has no chance to notice.
  - D-52's rule "a later trash record for the same path replaces the earlier one" covers matching restores only, not
    the stale earlier entry.
- **Fix:** in `entries()`, when a trash record's trashed path is already in `inTrash`, mark the earlier entry
  `.trashEmptied`, since it must have left the Trash for its name to be free. Add the scenario to `RestorabilityTests`
  and `RestoreExecutorTests`.
  - A stronger, optional fix: also log the file's identity (`FileIdentity`, which the scan already reads) in the trash
    result record, and have Restore require it to match. The inode survives a move into `~/.Trash` on the same volume.
    An optional JSON field keeps schema v1 readable. This needs an owner decision.
- **Size:** about 10 lines of production code, or about 30 with the identity check. It changes what Restore may move,
  so it gets its own pull request.

### TD-02 Static checks miss mutation calls, subprocess deletion, and tests that reach the real home folder

- **Severity:** High. **Confidence:** verified (ran on a test tree). **Revisits D-38.** **Needs an owner
  decision.**
- **Locations:**
  - `scripts/static-checks.sh:62-64` (the `mutation` rule) and `:74-77` (the `file-write` rule). No rule covers
    `Process` or the home folder.
  - `scripts/static-checks-test.sh` has no case for any of the calls below.
  - `ShuckTests/AppEnvironmentTests.swift:26-29` and `:86-89` use `URL.homeDirectory`.
- **What the checks miss:** `scripts/static-checks.sh <tree>`, run on a test tree outside the repository, printed
  `static-checks: OK` for all of these:
  - in `ShuckKit`: `renamex_np(`, `renameat(`, `unlinkat(`, `clonefile(`, `copyfile(`, `openat(…, O_CREAT)`,
    `ftruncate(` and `"text".write(toFile:…)`;
  - in the app target: `Process` with `executableURL = URL(filePath: "/bin/rm")` and `arguments = ["-rf", path]`;
  - in `ShuckTests`: `homeDirectoryForCurrentUser` and `URL.homeDirectory.appending(path: "Downloads/file.dmg")`.
- **Why these gaps matter:**
  - `\bunlink\(` and `\brename\(` skip the `*at` and `_np` variants. That is the same kind of gap D-45 closed for
    `chmod`.
  - `ShuckExecution` already calls `renamex_np` (`RestoreExecutor.swift:102`), so copying that code into `ShuckKit`
    would pass.
  - Nothing constrains `Process`, which M2's tool commands need (DEV-R03, R07 to R09, R11 and R12).
- **The real home folder in tests:** safety rule 3 is enforced by review only. `AppEnvironmentTests` builds the
  production configuration from the real home folder, so unit tests call `realpath` on `~/Library/Mail`, `~/.ssh` and
  the other section 8.4 locations. This reads metadata only and writes nothing.
- **Why it matters:** SAF-017 (this check is its acceptance check), ENG-006, AGENTS.md safety rules 1, 3 and 4.
- **Fix:**
  - Extend `mutation` with `renamex_np|renameat|renameatx_np|unlinkat|exchangedata|copyfile|clonefile|ftruncate`.
  - Extend `file-write` with `\.write\(toFile:|openat\(|mkdirat\(|OutputStream\(`.
  - Add a `process` rule: `\bProcess\(|posix_spawn|NSTask` outside `ShuckExecution`, plus one allowlisted read-only
    tool-query file if the owner wants it.
  - Add a `real-home` rule for test code: `homeDirectoryForCurrentUser|NSHomeDirectory|URL\.homeDirectory|"~/`.
  - Give `AppEnvironment` an injectable home folder, so its tests need no allowlist entry.
  - Add self-test cases for each new pattern, naming SAF-017 (see TD-19).
- **Size:** about 40 lines of bash and 10 of Swift. It is a Safety change, so it gets its own pull request, landing
  before M2's first tool runner.

### TD-03 A public log line contains file and folder names

- **Severity:** High (a broken AGENTS.md rule, with a one-line fix). **Confidence:** verified (read and ran a probe).
- **Location:** `Packages/ShuckKit/Sources/ShuckKit/Scanning/PersonalFilesScanner.swift:335-336`:
  `Self.logger.error("Cannot list \(folder.path, privacy: .private): \(error.localizedDescription, privacy: .public)")`.
- **What is wrong:** Cocoa's error descriptions name the item. A probe printed `The file “Tax Returns 2025” couldn’t
  be opened because there is no such file.` So the folder's name reaches the unified log in clear text, although its
  path is marked private.
- **Why it matters:** NFR-SEC-006, and AGENTS.md: "Mark paths and file names `privacy: .private`."
- **Fix:** log the error's domain and code as public and its description as private.
- **Size:** 1–2 lines. Not Safety or Execution.

## Medium

### TD-04 One hand-written run loop per executor, with Trash-specific outcomes

- **Severity:** Medium. **Confidence:** verified (read). **Revisits D-48.** **Needs an owner decision.**
- **Locations:**
  - `ShuckExecution/TrashExecutor.swift:30-57` and `RestoreExecutor.swift:31-57` repeat the same loop: the stop reason,
    the cancellation check, the intent record, the action, the result record, and stopping when the log fails.
  - `TrashExecutor.swift:38-40` skips items with another method without writing a log record (D-48).
  - `:84` and `:101` hard-code `operation: .trash`.
  - `:107-138` has `ItemOutcome.Result.trashed(URL)` and `SkipReason.unsupportedMethod`.
  - `Shuck/TrashReview.swift:67-77` adds `RunReport.trashedURLs` in the app.
- **What is wrong:** M2 needs Delete (DEV-R01, R02, R04, R06 and CAC-004) and Tool (DEV-R03 and R07 to R09). M3 and M4
  need Launchctl (APP-011, STA-005).
  - A rebuildable Developer Junk run mixes Delete and Tool items in one plan, behind one summary confirmation per run
    (section 8.2, SAF-003).
  - With one executor per method, each would skip the other's items as `unsupportedMethod`, with no log record.
  - Copying the loop twice more multiplies the code that SAF-005, SAF-006, SAF-008, SAF-011 and SAF-014 depend on.
- **Fix:** one `Executor` that owns the loop and hands each item to an action for its method: `trash` now, and later
  `delete`, `tool` and `launchctl`.
  - Its outcome does not depend on the method: done (with where the item went, if trashed), skipped or failed.
  - `HistoryRecord.Operation(method)` maps a method to its log operation in one place.
  - Restore reuses the same loop with its own action.
  - Keep today's tests, and add one for a mixed plan.
- **Size:** about 150 lines. `ShuckExecution`, so it gets its own pull request, before M2's first executor.
- **Owner decisions:** one executor that dispatches by method, or plans limited to one method? And now, or in M2's
  first Delete task?

### TD-05 Errors during re-validation and moves lose their cause, so a run can't report "Not accessible"

- **Severity:** Medium. **Confidence:** verified (read).
- **Locations:**
  - `ShuckKit/Scanning/ItemSnapshot.swift:26-28` returns `nil` for any error (`try?`).
  - `ShuckExecution/TrashExecutor.swift:69` turns that `nil` into `.skipped(.missing)`.
  - `TrashExecutor.swift:74-75` and `RestoreExecutor.swift:74`, `:90` and `:99` record `.failed(String(describing:
    error))`.
  - `ShuckExecution/Trash.swift:9` and `:12` throw untyped errors.
- **What is wrong:** a permission error (TCC or POSIX) during re-validation is reported as "No longer there", and one
  during the move as free text. Callers can't act on either, against AGENTS.md's "typed errors whose cases callers can
  act on". Caches & Logs reads `~/Library/Containers/*/Data/Library/Caches`, which needs Full Disk Access (CAC-001),
  so M2 will hit exactly this.
- **Why it matters:** SAF-012 ("Not accessible", with guidance), SAF-011, and AGENTS.md's typed-error convention.
- **Fix:**
  - Re-validation reports one of three results: missing, not accessible, or the item's snapshot.
  - The executor maps EPERM and EACCES to `.skipped(.notAccessible)`.
  - `Trash` throws a typed error that carries the errno or Cocoa code.
  - `.failed` carries a code and the localized description.
- **Size:** about 60 lines in `ShuckExecution` and `ShuckKit/Scanning`. Its own pull request, which pairs with TD-04.

### TD-06 The log's `detail` is Swift reflection output that the History page parses back

- **Severity:** Medium. **Confidence:** verified (ran a probe). **Revisits D-69.**
- **Locations:**
  - Writing: `ShuckExecution/TrashExecutor.swift:95` and `RestoreExecutor.swift:131` (`String(describing: reason)`),
    plus the error strings in TD-05.
  - Reading: `Shuck/HistoryView.swift:193-206` parses the text before the first "(".
  - `ShuckTests/HistoryTests.swift:98` tests a hand-written format.
  - The reasons are put into words three times: `TrashReviewSheet.swift:136-155`,
    `HistoryRestoreSheet.swift:128-151` and `HistoryView.swift:194-206`.
- **What the log stores:** a probe printed
  - `changed(ShuckKit.ItemSnapshot(kind: ShuckKit.ItemSnapshot.Kind.file, allocatedSize: 4))`,
  - `rejected(ShuckKit.PathGuardError.outsideAllowedRoots("/x/y"))`,
  - and, for a failure, `CocoaError(_nsError: Error Domain=NSCocoaErrorDomain Code=513 "The file couldn’t be saved
    because you don’t have permission.")`.
- **What is wrong:**
  - The format depends on type, module and case names. Renaming any of them changes what new records say and how old
    ones read.
  - The app test checks `changed(ItemSnapshot(kind: file, …))`, a format the executors never write, so nothing ties
    the two ends together.
  - The three wordings differ: "No longer there", "no longer there" and "Skipped: no longer in the Trash".
  - M2 adds more reasons: a running app (SAF-009), a missing tool (SAF-010), and not accessible (TD-05).
- **Why it matters:** section 8.5 (the log is a durable record), SAF-011, maintainability.
- **Fix:**
  - Give every skip reason a stable code: a `String` raw value that keeps today's case names, so existing logs still
    read.
  - Write `code` or `code: detail`, and write errors as their domain and code plus a message.
  - Keep one table from code to words, shared by both sheets and History.
  - Add a test that runs an executor and reads its records back through History's wording.
- **Size:** about 80 lines, about 25 of them in `ShuckExecution`. The Execution part goes with TD-04 and TD-05.

### TD-07 The File Cleanup model and pages are built around personal files only

- **Severity:** Medium. **Confidence:** verified (read). **Needs an owner decision.**
- **Locations:** in `Shuck/FileCleanupModel.swift`:
  - `:39`: `results` exists only for the personal-files sub-tools.
  - `:101-116` and `:246-263`: scans of other sub-tools keep only counts and sizes, and drop their items.
  - `:160` and `:171`: `scanItems` and `reviewMoveToTrash` take `any PersonalFilesSubTool`.
  - `:45` and `:165`: the only run the model can start is a Trash run.

  Elsewhere:
  - `Shuck/ContentView.swift:49-58` has one case and one downcast per sub-tool.
  - `LargeFilesView.swift` and `OldFilesView.swift` are about two thirds the same: toolbar, scanning indicator, Scan
    button, scan on appear, empty-state switch and review sheet.
  - `TrashReview`, `TrashReviewSheet` and `MoveToTrash` handle Trash only.
  - `ItemRow` is shared but lives in `TrashReviewSheet.swift:159`.
- **What is wrong:** Developer Junk and Caches & Logs need an item list, a selection, a review (SAF-003's summary
  confirmation) and a run. The model offers none of these for a sub-tool that is not a personal-files one. Each M2
  page would copy the page skeleton again and add another case to `ContentView`.
- **Why it matters:** FCL-003's intent, and AGENTS.md's "Adding a sub-tool" steps 2 and 3. FCL-002. Maintainability.
- **Fix:**
  - Results state per sub-tool, over `ScanItem`s. The personal files keep their shared scan behind it.
  - A reusable sub-tool page scaffold.
  - Pages looked up by tool ID instead of a case per sub-tool.
  - Generalize the review types when the summary review lands.
- **Size:** about 150–250 lines in the app. Not Safety or Execution.
- **Owner decision:** do this in M2-T01, or in M2's first sub-tool task, when the second kind of list exists?

### TD-08 A history run takes its one operation from its first record

- **Severity:** Medium. **Confidence:** verified (read).
- **Locations:**
  - `ShuckKit/History/HistoryRun.swift:49` (`operation`) and `:114` (`run.first.operation`).
  - `HistoryRun.Item` (`:10-43`) has no operation of its own.
  - `Shuck/HistoryView.swift:146-154` and `:218` show the run's operation.
- **What is wrong:** an M2 Developer Junk run mixes Delete and Tool records. An M3 uninstall unloads LaunchAgents and
  then moves files to the Trash, in one run (APP-007, APP-011). History would label the whole run by its first record
  (an uninstall would read "Changed with launchctl") and can't say what was done to each item.
- **Why it matters:** HIS-002 (each run shows its method) and SAF-006.
- **Fix:** add `operation` to `HistoryRun.Item`, and derive the run's label from its items: the single operation, or a
  combined label such as "Deleted and cleaned by tools".
- **Size:** about 30 lines in `ShuckKit/History` and 15 in the app. Not Execution.

### TD-09 The results list re-sorts every row on every batch, on the main actor

- **Severity:** Medium. **Confidence:** verified by a benchmark of an equivalent loop; not measured in the app.
- **Locations:** in `Shuck/PersonalFilesResults.swift`:
  - `:45-53`: each scan event runs `removeAll`, `append` and then `rows.sort(using:)` over every row.
  - `:69-73`: `groups` is rebuilt on every read.
  - `:121-137`: `ResultRow.init`, which looks up a `UTType` for every row, runs on the main actor.
- **Evidence:** a release-build benchmark ran the same steps with a simplified row:

  | Rows | Main-thread time, total | Slowest batch |
  |---|---|---|
  | 50,000 | 3.5 s | 31 ms |
  | 200,000 | 55 s | 138 ms |

  The real row is larger, so these figures are a lower bound.
- **When it happens:** whenever a list reaches six figures, for example Old Files with a minimum size of 0. OLD-001
  allows that; today it takes a launch argument, and Settings adds a control in M5.
- **Why it matters:** NFR-PERF-001: the main thread is never blocked for more than 250 ms, and interactions respond
  within 100 ms.
- **Fix:** sort each incoming batch and merge it into the sorted rows, which costs linear time, or insert by binary
  search. Build `ResultRow`s off the main actor, and cache `groups`.
- **Size:** about 40 lines in the app. Not Safety or Execution.

### TD-10 Scans can't be stopped from the app

- **Severity:** Medium. **Confidence:** verified (read). **Needs an owner decision.**
- **Locations:**
  - `Shuck/FileCleanupModel.swift:101-116`, `:117-121` and `:131-157` return the scan task but keep no handle to it.
  - Every caller drops it: `FileCleanupView.swift:26` and `:91`, `LargeFilesView.swift:47` and `:54`, and
    `OldFilesView.swift:42` and `:49`.
- **What is wrong:** the engine's scans stop when their task is cancelled (the SAF-014 tests show it), and the model
  even puts back the earlier state on cancel. But nothing in the app can cancel a scan: there is no Stop button, and
  the model keeps no task to cancel. A scan of the owner's home folder takes about 26 s.
- **Why it matters:** SAF-014: "Scans and runs MUST be cancellable." OVR-002 asks for cancel per sub-tool in M5.
- **Fix:** keep each scan's task in the model, add `cancelScan(_:)`, and show Stop next to the scanning indicator.
- **Size:** about 40 lines in the app.
- **Owner decision:** add Stop now, or with OVR-002 in M5?

### TD-11 Logger categories are per component, not per tool and sub-tool

- **Severity:** Medium. **Confidence:** verified (read). **Needs an owner decision.**
- **Locations:**
  - Categories in use: "Execution" (`ShuckExecution/TrashExecutor.swift:21`), "Restore" (`RestoreExecutor.swift:22`),
    "History" (`ShuckKit/History/HistoryLog.swift:17`) and "PersonalFiles" (`Scanning/PersonalFilesScanner.swift:28`).
  - The app target has no `Logger` at all, so refused plans, failed history reads and launch errors are not logged.
- **What is wrong:** AGENTS.md and NFR-OBS-001 say one category per tool and sub-tool. A failed move is logged under
  "Execution", without the sub-tool that ran. M2 adds more components.
- **Why it matters:** NFR-OBS-001 and AGENTS.md's coding conventions.
- **Fix:** one of:
  - use the run's tool ID as the category in executors and scans, and add a few app categories; or
  - record that categories are per component, and update AGENTS.md.
- **Size:** about 20 lines. It touches `ShuckExecution` (logging only), so it goes with TD-04.

## Low

### TD-12 The fixture-root gate uses `resolvingSymlinksInPath`, so one of its accepted shapes never matches

- **Severity:** Low. **Confidence:** verified (ran a probe).
- **Locations:**
  - `Shuck/AppEnvironment.swift:141` resolves with `.resolvingSymlinksInPath()`, and `:147` then requires
    `starts(with: ["/", "private", "var", "folders"])`.
  - `ShuckTests/AppEnvironmentTests.swift:12` and `:32-40` test with a fixture path that does not exist.
- **Evidence:** for an existing `/private/var/folders/…/T/ShuckFixtures/<UUID>`, `resolvingSymlinksInPath()` returns
  `/var/folders/…`. So `isProcessTemporary` is false, and the app stops with `fatalError`. Only the shape of the
  sandboxed runner's container works. The tests pass because Foundation strips `/private` only from paths that
  exist.
- **Why it matters:** it fails closed, so there is no data risk. But a UI test run outside the sandboxed runner would
  crash at launch, and the test gives false confidence. D-42 and D-43 already explain why the engine avoids this API.
  NFR-QA-002, SAF-016.
- **Fix:** resolve with `realpath`, as `FixtureRoot` does, and test with a real temporary folder.
- **Size:** about 10 lines in the app, plus the test. It pairs with TD-02 (test isolation).

### TD-13 Every window shares one navigation and one selection

- **Severity:** Low. **Confidence:** verified (read; not run). **Needs an owner decision.**
- **Locations:** `Shuck/ShuckApp.swift:10` and `:38-40` put one `AppNavigation`, held in `@State` at app level, into
  every `WindowGroup` window. The selection lives in the shared `PersonalFilesResults`
  (`PersonalFilesResults.swift:20`).
- **What is wrong:** File > New Window (⌘N) opens a second main window whose sidebar follows the first. A selection in
  one window is also the other's selection, so a review opened in one window acts on what the other window shows as
  selected.
- **Fix:** use a single-window `Window` scene, since Shuck is a one-window utility, or keep navigation and selection
  per window.
- **Size:** about 5 lines.

### TD-14 Scanner: other listing errors are silent; protected-name check is case-sensitive; a comment is wrong

- **Severity:** Low. **Confidence:** verified (read).
- **Locations:** in `Scanning/PersonalFilesScanner.swift`:
  - `:334-338`: errors other than "no permission" are only logged, so the folder silently drops out of the results.
  - `:264`: `protectedNames.contains(url.lastPathComponent)` is case-sensitive, while `PathGuard.swift:70` folds case.
  - `:256` and `:289`: the comment says protected bundles and the Music and TV libraries are shown read-only, but the
    code shows every section 8.4 home location that way.
- **What the user sees:**
  - A folder that fails to list for another reason disappears from the results without a trace.
  - A folder named `backups.BACKUPDB` is walked, and its files are offered as selectable. The plan is then refused with
    an alert, because the guard folds case, which looks like a bug to the user.
- **Why it matters:** SAF-011 (no silent failures), and keeping the scanner consistent with the path guard (section
  8.4).
- **Fix:** report such folders as a scan event that the landing page shows, fold the name check as the guard does, and
  correct the comment.
- **Size:** about 15 lines in `ShuckKit/Scanning`.

### TD-15 The history reader follows a symlinked log, though the writer refuses one

- **Severity:** Low. **Confidence:** verified (read).
- **Locations:** `ShuckKit/History/HistoryLog.swift:76-86` reads with `fileExists` and `Data(contentsOf:)`, which
  follow symlinks. The writer refuses them: `:29` opens with `O_NOFOLLOW`, and `:106-117` checks the folder.
- **What is wrong:** the writer never writes through a planted symlink (D-46), but the reader reads one, and History
  lists its records. Restore's "directly inside the Trash" and size checks limit the damage, but History can show
  records Shuck never wrote.
- **Fix:** read with `O_NOFOLLOW` too, and check the folder.
- **Size:** about 10 lines in `ShuckKit/History`.

### TD-16 Raw error text is shown in the UI

- **Severity:** Low. **Confidence:** verified (read; the formats come from the TD-06 probe).
- **Locations:**
  - `Text(verbatim: String(describing: error))` of a `HistoryError`, which reads like
    `cannotOpen("/Users/…/history.jsonl", errno: 13)`: `HistoryView.swift:42`, `TrashReviewSheet.swift:123` and
    `HistoryRestoreSheet.swift:115`.
  - Logged failure text such as `CocoaError(_nsError: …)`, shown as is: `TrashReviewSheet.swift:153`,
    `HistoryRestoreSheet.swift:149` and `HistoryView.swift:184-185`.
- **Why it matters:** NFR-L10N-001, and P-2 ("Explain, don't just list").
- **Fix:** a user-facing message for each `HistoryError` case, with the path on a second, selectable line, and the
  localized description for failures (with TD-05 and TD-06).
- **Size:** about 40 lines in the app.

### TD-17 A SAF-014 test cancels its own task and is reported "cancelled"

- **Severity:** Low. **Confidence:** verified (ran).
- **Location:** `Tests/ShuckExecutionTests/TrashExecutorTests.swift:188-200`. Line 191 calls
  `withUnsafeCurrentTask { $0?.cancel() }` inside the test's own task.
- **What is wrong:** `scripts/test.sh` prints `Test cancellingStopsBeforeTheNextItemSAF014() was cancelled after 0.037
  seconds`, not "passed". A probe showed that a failing expectation after the cancel is still reported, so the test
  does check its result. It just reads like a skipped test. `RestoreExecutorTests.swift:193-197` does it right, by
  running the executor in a child task.
- **Fix:** use the same pattern as `RestoreExecutorTests`.
- **Size:** about 5 lines of test code.

### TD-18 Test setup is repeated across 10 files

- **Severity:** Low. **Confidence:** verified (counted).
- **What is repeated:**
  - `HistoryLog.folder(home: root.url, bundleID: ShuckKit.bundleID)` in 10 test files;
  - an executor with `FakeTrash(folder: root.url.appending(path: ".Trash"))` in 6;
  - the loop that collects a scan's items in 5 places: `LargeFilesPipelineTests`, `OldFilesPipelineTests`,
    `SubToolPipelineTests` (twice) and `SubToolIndependenceTests`.
  - `LargeFilesPipelineTests` and `OldFilesPipelineTests` are near copies of each other.
- **Fix:** helpers in `ShuckKitTestSupport` (`FixtureRoot.historyFolder`, `FixtureRoot.trashFolder`,
  `items(from:context:)`) and a factory in `ShuckExecutionTests` for an executor with a `FakeTrash`. M2's rule tests
  can then reuse them.
- **Size:** about 40 lines of test support.

### TD-19 No test names SAF-017 (NFR-QA-001)

- **Severity:** Low. **Confidence:** verified.
- **What is wrong:** searching all test code finds SAF-017 zero times. `scripts/static-checks-test.sh` tests the rule
  without naming its ID. SAF-003, SAF-006, SAF-009, SAF-010 and SAF-015 are M2 work, as `docs/progress.md` says.
- **Fix:** name SAF-017 in the self-test's `mutation` and `file-write` cases.
- **Size:** 1–3 lines.

### TD-20 UI tests depend on the Mac's language and region

- **Severity:** Low. **Confidence:** verified (read).
- **Locations:** `ShuckUITests/ShuckUITestCase.swift:36-44` launches without `-AppleLanguages` or `-AppleLocale`.
  Tests expect strings such as "10.5 MB reclaimable in total" (`FindWhatTakesSpaceUITests.swift:31`) and "1 item
  selected, 5.2 MB" (`:61`).
- **What is wrong:** on a Mac whose region writes "10,5 MB", or whose language is not English, every workflow fails.
- **Fix:** launch with `-AppleLanguages (en) -AppleLocale en_US`.
- **Size:** 2 lines of test code.

### TD-21 Project settings: no shared scheme, warnings don't fail, version set three times, unused setting

- **Severity:** Low. **Confidence:** verified (read and ran). **Needs an owner decision** (warnings as errors).
- **What the review found:**
  - No shared scheme. There is no `xcshareddata`, `xcodebuild -list` shows only autocreated schemes, and
    `scripts/test.sh` prints "Supported platforms for the buildables in the current scheme is empty".
  - Warnings don't fail the build: neither `project.xcproj:54-82` nor `Package.swift` treats warnings as errors.
  - `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` and `DEVELOPMENT_TEAM` are set in every target
    (`project.xcproj:60-61`, `71`, `100-104` and `136-139`), and `docs/releasing.md:8-10` tells the owner to change all
    three.
  - `REGISTER_APP_GROUPS = YES` (`:75`), although the app has no app groups.
  - The test bundle IDs, `me.nutabi.ShuckTests` and `me.nutabi.ShuckUITests` (`:105`, `:140`), are outside
    `me.nutabi.shuck.*` (D-21).
  - The app icon set has no images, only `Contents.json`. That is M5 polish.
- **Why now:** fresh builds have no warnings today, so this is the cheapest moment to make warnings fail CI. A shared
  scheme makes CI independent of autocreation and gives test options a home. One version setting removes a step from
  every release.
- **Fix:**
  - Commit a shared Shuck scheme.
  - Set `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` in the app, and `.treatAllWarnings(as: .error)` (SwiftPM 6.2) in the
    package.
  - Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` once, at project level.
  - Drop `REGISTER_APP_GROUPS`.
- **Size:** project files only, no Swift.

### TD-22 The app and the engine compile with different concurrency rules

- **Severity:** Low. **Confidence:** verified (read). **Needs an owner decision.**
- **Locations:** the app turns on `SWIFT_APPROACHABLE_CONCURRENCY = YES` (`project.xcproj:77`, `:108` and `:143`) and
  `MEMBER_IMPORT_VISIBILITY` (`:80`). `Packages/ShuckKit/Package.swift:15-25` has no `swiftSettings`.
- **What is wrong:** in the app, a `nonisolated` async function runs on its caller's actor, which is why
  `AppEnvironment` marks its runs `@concurrent`. In the engine, the same function runs on the global executor. Code
  that moves between the two changes where it runs, and a reviewer learning Swift concurrency (G-5) meets two sets of
  rules.
- **Fix:** turn on the same upcoming features in `Package.swift` (`NonisolatedNonsendingByDefault`,
  `InferIsolatedConformances`, `MemberImportVisibility`) and fix what surfaces, or record the difference in AGENTS.md.
- **Size:** about 5 lines, plus whatever the new rules flag.

### TD-23 Stale README, comments and one decision rationale

- **Severity:** Low. **Confidence:** verified (read). **Revisits D-58.**
- **What is stale:**
  - `README.md:15` says Shuck "doesn't do anything useful yet" and is "an empty app shell", after v0.1.0.
  - `Shuck/TrashReview.swift:9` says "The review sheet shows it (M1-T12, second pull request)".
  - `Shuck/LargeFilesView.swift:15` says the toggle isn't stored "so UI tests … write nothing to the real preferences".
    That reason no longer holds since D-70.
  - `Scanning/PersonalFilesScanner.swift:256` (see TD-14).
  - AGENTS.md describes the `ShuckExecutionTests` target as "added with the first executor (M1-T04)", which reads as
    future work.
- **Fix:** update the text. The owner decides whether to store the Group by Folder toggle now.
- **Size:** about 10 lines.

### TD-24 `realpath`, "item exists" and case-folding helpers are duplicated

- **Severity:** Low. **Confidence:** verified (read).
- **Where the copies are:**
  - `realpath` wrappers: `Safety/ResolvedPath.swift:44-48`, `ShuckExecution/RestoreExecutor.swift:156-160` and
    `ShuckKitTestSupport/FixtureRoot.swift:96-100`.
  - "Item exists" checks: `ResolvedPath.swift:33-35`, `RestoreExecutor.swift:151-153` and `FixtureRoot.swift:75-77`,
    plus an `lstat` in `Restorability.swift:124-128`.
  - Case folding: `PathGuard.swift:89` and `PersonalFilesScanner.swift:319`. D-79 says these two must stay the same.
- **Fix:** give `ResolvedPath` and one `fold` function `package` access (available since SwiftPM 5.9), so
  `ShuckExecution` and the scanner use the guard's own. Keep the harness's copy on purpose, as an independent check.
- **Size:** about 20 lines. It touches `ShuckExecution` trivially, so it goes with TD-04.

## Noted, not findings

- **Already tracked in `docs/progress.md`:** who owns `node_modules` (DEV-R06), and revisiting CodeQL.
- **A window between check and move:** between the guard's re-validation and the move, a parent folder could be
  swapped (`TrashExecutor.swift:64-72`). This is inherent to path-based APIs. M2's permanent Delete can close it by
  deleting relative to a validated folder descriptor (`openat` and `unlinkat` with `O_NOFOLLOW`). That is a design
  point for the Delete executor, not M1 debt.
- **Recorded decisions with no problem today:**
  - Restore doesn't compare the item's kind (D-52).
  - Items with another method are skipped without a log record (D-48; see TD-04).
  - Some initializers are public only so tests can stub runs (D-63, D-72).
- **History grows:** the history log grows without bound, and History reads it again on every visit
  (`HistoryModel.swift:71-77`, D-69). That is fine at M1 volumes. Watch it once Caches & Logs logs many items per run.

## Build, lint, static checks and tests

### Builds and checks

| Check | Result |
|---|---|
| App build: `xcodebuild build-for-testing` (app and both test bundles), a fresh `-derivedDataPath` | Succeeded. 0 compiler warnings; the only notices are 3 `appintentsmetadataprocessor` "Metadata extraction skipped" lines. |
| Engine build: `swift build --build-tests`, a fresh `--scratch-path` | Succeeded, 0 warnings. |
| `scripts/lint.sh` | OK |
| `scripts/static-checks.sh` | OK |
| `scripts/static-checks-test.sh` | OK |

### Tests

`scripts/test.sh --no-ui` passed, with no failures. UI tests were not run: in a sandboxed shell the app opens no window
(AGENTS.md).

| Suite | Tests | Result |
|---|---|---|
| `ShuckKitTests` | 136 tests in 14 suites | Passed |
| `ShuckExecutionTests` | 26 tests in 8 suites | Passed; one reported "cancelled" (TD-17) |
| App unit tests | 61 tests in 10 suites | Passed |

### Coverage

The engine gate counts `ShuckKit` and `ShuckExecution`: 96.0% of lines (1,351 of 1,408), against an 80% gate.

| Lowest-covered gated files | Coverage |
|---|---|
| `ShuckExecution/Trash.swift` (`SystemTrash`, untested by design, D-47) | 0.0% |
| `Safety/PathGuardConfiguration.swift` | 88.2% |
| `ShuckExecution/RestoreExecutor.swift` | 88.7% |
| `History/HistoryLog.swift` | 91.7% |
| `Scanning/FileIdentity.swift` | 92.3% |
| `Tools/OldFiles.swift` | 92.7% |

Test support is reported but not gated; its lowest file is `FixtureRoot.swift`, at 93.4%.

The app target, from its unit tests only, is at 32.2% (804 of 2,497 lines), from the xcresult bundle:

- Models are well covered: `FileCleanupModel` 96.0%, `TrashReview` 97.8%, `HistoryRestore` 92.5%, `HistoryModel`
  100%, `AppEnvironment` 84.7%.
- Views are left to the UI tests, which were not run here: `PersonalFilesTable`, `FileCleanupView`,
  `TrashReviewSheet`, `LargeFilesView` and `OldFilesView` are at 0%, `HistoryView` at 12.7% and
  `HistoryRestoreSheet` at 10.3%.

## Proposed pull requests

`docs/progress.md` lists M2-T01's pull requests, which follow this split. Each is about 200 changed lines of
production code or less. Safety and Execution changes are on their own. Whatever M2's new executors need comes before
M2's first executor.

| # | Pull request | Findings | Production lines | Notes |
|---|---|---|---|---|
| 1 | Restore ignores a Trash name that another run reused | TD-01 | ~10, or ~30 with the identity check | `ShuckKit/History`, decides what Restore moves; on its own. First, because it is a live bug in 0.1.0. |
| 2 | Static checks for M2, and test isolation | TD-02, TD-12, TD-19 | ~15 Swift (`AppEnvironment` home injection, `realpath`) + ~40 bash | Safety; on its own. Before any M2 code that uses `Process`. |
| 3 | Build settings and test helpers | TD-21, TD-22 (if approved), TD-17, TD-18, TD-20 | 0–10 Swift, plus project and package settings and ~60 test lines | Early, so later pull requests build with warnings as errors and reuse the helpers. |
| 4 | Scanner and History fixes | TD-03, TD-14, TD-15, TD-23 | ~40 (`ShuckKit/Scanning`, `ShuckKit/History`, docs) | Not Execution. |
| 5 | Run outcomes that say why | TD-05, and the engine side of TD-06 | ~90 (`ShuckExecution`, `ShuckKit`) + ~40 app adaptations | Execution; on its own. |
| 6 | One run loop for every executor | TD-04, TD-11, TD-24 | ~150 (`ShuckExecution`) | Execution; on its own, stacked on 5 (D-76). Lands before M2's Delete and Tool executors. |
| 7 | History wording in one place | The app side of TD-06, TD-08, TD-16 | ~120 (~30 `ShuckKit/History`, ~90 app) | Stacked on 5. |
| 8 | File Cleanup pages for any sub-tool | TD-07, TD-10, TD-13 | ~200 (app) | Timing is an owner decision; it could instead open M2's first sub-tool task. |
| 9 | A results list that doesn't re-sort | TD-09 | ~40 (app) | Independent; any time after 3. |

## Decisions

The owner decided four of these on 2026-11-03 (D-82). The others are proposals that each pull request makes, open for
the owner's review there.

1. **TD-01:** the trash result record also keeps the file's identity, and Restore checks it. Owner decision.
2. **TD-02:** only `ShuckExecution` may start a subprocess. Owner decision.
3. **TD-04:** one executor that dispatches by method, so a run can mix Delete and Tool items. Proposal. Items of another
   method then no longer occur, so D-48's unlogged skip goes away.
4. **TD-04 to TD-07:** the refactors that prepare M2 are part of M2-T01. Owner decision.
5. **TD-06:** stable reason codes in the log's `detail` that keep today's case names, which refines D-69. Proposal.
6. **TD-10:** a Stop button for scans, in M2-T01 with the page layout. Part of the owner's decision on TD-04 to TD-07.
7. **TD-11:** Logger categories per tool and sub-tool, as NFR-OBS-001 says. Owner decision.
8. **TD-13:** one main window (`Window`) instead of `WindowGroup`. Proposal.
9. **TD-21:** warnings as errors in the app and the engine, and a shared scheme. Proposal.
10. **TD-22:** the engine keeps its concurrency settings, and `AGENTS.md` records the difference. Proposal.
11. **TD-23:** whether to store the Group by Folder toggle (revisits D-58) is asked in its pull request.
