# M2 review

A review of `main` at b0f707e ("[M2-T13] Project folders in Settings and Node.js projects on the page", #149), on
2026-11-12, against `docs/PRD.md` and the safety rules in `AGENTS.md`. D-142 asked for it: a complete review of M2
once M2-T07 and M2-T12 to M2-T14 had merged, which also decides how the deferred fixes (M2-F03, M2-F12 to M2-F19) are
done. Line numbers refer to that commit.

**This document is a proposal.** Nothing in it is decided, and no fix has started. The owner approves, changes or
rejects the breakdown in "Proposed pull requests" and answers the questions in "Questions for the owner" first.

## What was read, and what was not

Read in full:

- `ShuckExecution`: every file.
- `ShuckKit`: Safety, Planning, Rules, History (`HistoryLog`, `Restorability`, `HistoryRun`, `SkipCode`), every file in
  Tools, and in Scanning `ScanItem`, `ItemSnapshot`, `ModificationDate`, `FolderActivity`, `FileIdentity`, `FreeSpace`,
  `LastOpened`, `ReclaimableTotal` and `PersonalFilesScanner`'s walk (from line 150).
- The app: `AppEnvironment`, `FileCleanupModel`, `FolderList`, `FolderListModel`, `ProjectFolders`, `ShuckApp`,
  `ContentView`, `SubToolPages`, `SubToolPage`, `ScanResults`, `SummaryConfirmation`, `RunModel`, `TrashReview`,
  `DeveloperJunkView`, `RebuildableControls`, `SettingsView`, `HistoryModel`, `HistoryRestore`, `OutcomeWording`.
- `scripts/build-dmg.sh` and `scripts/notarize.sh`; the PRD's requirement rows for SAF, DEV, CAC, SET, HIS and the
  NFRs named below; decisions D-142 to D-154; `docs/progress.md`'s M2 section; the titles of every open issue, and
  the text of #116, #118 and #123 to #127.

Read in part, or not read:

- Decisions D-82 to D-141: their titles only. A finding that says "revisits D-xx" for one of them rests on the title
  and on the code.
- Tests: the names of every test for M2-T12 to M2-T14 and every UI workflow step, and the helpers in
  `ShuckKitTestSupport`. Test bodies were not read, except where a finding quotes one.
- Not read: `HistoryRecord`, `LoggedCommand`, `PersonalFilesScanner` lines 1 to 149, `PersonalFilesResults`,
  `PersonalFilesTable`, `CachesAndLogsView`, `FileCleanupView`, `TrashReviewSheet`, `HistoryView` (except
  `status(of:)`), `SummaryConfirmationSheet` lines 1 to 83, `static-checks.sh` beyond its first 60 lines, the other
  scripts and both workflows. Findings about those rest on the open issues, which the review of 2026-11-10 verified.

Evidence: "probe" means a test added to a copy of the engine package outside the repository, run with `swift test`.
"read" means the code was read and not run. "script" means a script compared the sources with the String Catalogs.

**Counts:** 6 High, 9 Medium, 5 Low (20 findings).

Severity is as in `docs/m1-review.md`: **High** means a bug, a safety or data-loss risk, or a broken AGENTS.md or PRD
rule. **Medium** means a correctness or maintainability risk. **Low** means consistency or polish. "Safety/Exec" means
the fix touches Safety, Planning or `ShuckExecution`, so it gets a pull request of its own (D-62). **Hard stop** means
`AGENTS.md` sends the design to the owner before anything is implemented (D-146): the path guard, the static checks,
the safety layer, or anything that could remove, move or hide user data beyond the PRD.

## Findings at a glance

| ID | Sev | Finding | Main location | Evidence | Safety/Exec | Hard stop | Was |
|---|---|---|---|---|---|---|---|
| R-01 | High | A cache whose app Shuck cannot name starts selected for permanent Delete | `Tools/CachesAndLogs.swift:248-257` | probe | No | No | M2-F19 |
| R-02 | High | `npm` and `pip` run with no setting that keeps them off the network | `Tools/DeveloperJunk+Tools.swift:61,93` | read | No | No | M2-F19 |
| R-03 | High | A Trash plan with no rule passes anywhere inside Developer Junk's roots, a whole project included | `Planning/Plan.swift:103`, `PlanExecutor.swift:106-119` | probe | Yes | Yes | new (D-145, D-153) |
| R-04 | High | A quit or crash between a Trash move and its result record leaves the item with no Restore; closing the window quits during a run | `TrashAction.swift:14-23`, `RunLoop.swift:123-141` | read | Yes | Yes | M2-F13, #115 |
| R-05 | High | Stop just before a tool launches can crash the app | `ToolRunner.swift:127-134,186-199` | read | Yes | Yes | M2-F14, #114 |
| R-06 | High | SAF-018 is not built: two instances can run, and the log is not locked | `ShuckApp.swift`, `History/HistoryLog.swift` | read | History | No | M2-F12 |
| R-07 | Medium | Building a plan blocks the main actor: 1.7 s for 5,000 files | `FileCleanupModel.swift:319-348` | probe | No | No | M2-F03, #62 |
| R-08 | Medium | A stray `node_modules` in a project folder hides every project below it | `Tools/DeveloperJunk+NodeModules.swift:102-110` | probe | No | No | new (D-152, D-153) |
| R-09 | Medium | About 40 strings are missing from the String Catalogs, not two | both `Localizable.xcstrings` | script | No | No | M2-F17, #116 |
| R-10 | Medium | Items a scan cannot measure vanish silently; Developer Junk's page shows no "not accessible" note | `Tools/DeveloperJunk.swift:238-243`, `ScanResults.swift:52-55` | read | No | No | M2-F17, #118 |
| R-11 | Medium | Delete holds a descriptor per folder level; a failed Restore leaves the folders it created | `DeleteAction.swift:67-77`, `RestoreExecutor.swift:95-106` | read | Yes | Yes | M2-F15, #119, #120 |
| R-12 | Medium | The two acceptance checks the PRD names are not built | `scripts/static-checks.sh`, `ShuckExecutionTests` | read | Static checks | Yes | M2-F16 |
| R-13 | Medium | `/usr/bin/xcrun` counts as "Xcode is installed"; a stopped tool's children keep running | `Tools/DeveloperJunk.swift:183,412-417`, `ToolRunner.swift:137-147` | read | Partly | Partly | M2-F19, #127 |
| R-14 | Medium | A skip caused by an exclusion reads "failed a safety check" | `OutcomeWording.swift:54`, `SkipCode.swift:56` | read | Yes | No | new (D-149) |
| R-15 | Medium | Agent choices changed the path guard's inputs and a PRD row without the owner | D-145, D-153, D-154, PRD SET-003 | read | n/a | n/a | new |
| R-16 | Low | An allowed root that becomes a link is followed out of the home folder | `Safety/PathGuard.swift:84` | read | Yes | Yes | new |
| R-17 | Low | Pages hand the model a sub-tool value, so a stale copy could plan or scan | `SubToolPage.swift:72,106-108` | read | No | No | new (D-154) |
| R-18 | Low | Release and check scripts pass when they should fail | `scripts/` | issues | Static checks | Partly | M2-F18, #66, #121 to #123 |
| R-19 | Low | Six open issues belong to no task | #65, #123 to #127 | read | n/a | n/a | new |
| R-20 | Low | Stale comments and PRD rows | see below | read | No | No | new |

## High

### R-01 A cache whose app Shuck cannot name starts selected for permanent Delete

- **Confidence:** verified (probe). **Revisits D-120.** PRD: CAC-009.
- **Location:** `Packages/ShuckKit/Sources/ShuckKit/Tools/CachesAndLogs.swift:248-257`. The scan passes
  `unselected: apple`, so only `com.apple.*` entries start unselected.
- **What the PRD says:** CAC-009: "An entry whose owning app Shuck cannot resolve (CAC-002) is listed but not selected,
  because some apps keep state in Caches." Its source [S76] is another tool deleting Claude Code's memory folders.
- **Evidence:** the probe made three folders in `Library/Caches`, each 40 days old: `Firefox`, `claude-cli-nodejs` and
  `com.example.unknownprobe` (a bundle ID no installed app has). The scan returned all three as `.selected`. The
  first two have no app (`apps=[]`), so the running-app check never applies to them either (SAF-009, the left-over
  D-121 names).
- **Why it matters:** the user who clicks Delete with the default selection deletes, permanently, the data the PRD
  says must be left unselected. This is the largest gap between the PRD and what 0.2.0 would do.
- **Fix:** `unselected: apple || unresolved`, where unresolved means the folder is not named like a bundle ID or
  `AppNames` has no name for it, with its own reason text ("Shuck can't tell which app this belongs to, so it starts
  unselected."). Loose files and logs follow the same rule. Add CAC-009's fixture test.
- **Size:** about 25 lines of production code. Not Safety or Execution.

### R-02 `npm` and `pip` run with no setting that keeps them off the network

- **Confidence:** verified (read). **Revisits D-126, D-127.** PRD: DEV-004, NFR-SEC-001.
- **Location:** `Tools/DeveloperJunk+Tools.swift:61` and `:93` build the commands with `PATH` and `HOME` only.
  `NpmCacheTests.swift` pins it: `#expect(command.environment.count == 2 …)`. `brew` gets its three variables (`:113`).
- **What the PRD says:** DEV-004: "`npm` sets `NPM_CONFIG_UPDATE_NOTIFIER=false` and `NPM_CONFIG_OFFLINE=true`", and
  whether the commands use the network themselves was "to verify in M2-T11". Neither happened.
- **Fix:** add the two npm variables, and `PIP_DISABLE_PIP_VERSION_CHECK=1` and `PIP_NO_INPUT=1` for pip. Extend the
  recorded-environment tests. The check that the three commands open no connection is a manual one on the owner's Mac
  (for example with Little Snitch or `nettop`), since an agent may not run real tools; add it as an owner item.
- **Size:** about 10 lines. Rule data in `ShuckKit/Tools`, not Execution.

### R-03 A Trash plan with no rule passes anywhere inside Developer Junk's roots

- **Confidence:** verified (probe). **Revisits D-141, D-145 (4), D-153 (3) and (10).** PRD: SAF-004, SAF-007, SAF-008.
- **Locations:** `Planning/Plan.swift:103` requires a rule match only for Delete. `PlanExecutor.swift:106-119` checks a
  rule only if the item has one. `Tools/DeveloperJunk.swift:56-59` makes the whole `Archives` folder and every project
  folder an allowed root.
- **Evidence:** the probe built three `ScanItem`s by hand with source Developer Junk, tier "Your data", method Trash
  and no rule: `Developer/thesis` (a folder of documents in a project folder), `Developer/app` (a whole project) and
  `Library/Developer/Xcode/Archives/2026-11-10` (a date folder). `Plan(subTool:)` accepted each, and `PlanExecutor`
  moved each to the Trash.
- **Why it matters:** nothing in the app builds such an item today: the page offers only scanned archives to Trash.
  But the guard and the plan are the layer that must hold when a later change gets the list wrong, and after D-153 the
  roots of Developer Junk include the folders where the user's own source code lives. D-145 and D-153 each note that
  "only the scan" or "only the page's list" prevents it. The items would go to the Trash, so Restore could undo it.
- **Fix (hard stop, the owner decides):** a plan and the executor require a rule match for every item of a sub-tool
  whose items come from rules. The smallest form: `SubTool` gains `var requiresRule: Bool` (false for the
  personal-files sub-tools, true for Developer Junk and Caches & Logs), `Plan(subTool:)` refuses an item without a
  match (`PlanError.ruleRequired`), and `PlanExecutor` skips one (`ruleChanged`), as both do for Delete today. The
  archives rule's pattern `*/*.xcarchive` then also refuses a date folder.
- **Size:** about 30 lines in Planning and Execution, plus tests. Safety change, own pull request.

### R-04 A quit or crash between a Trash move and its result record leaves the item with no Restore

- **Confidence:** verified (read). PRD: SAF-005, HIS-001, HIS-003. Issue #115.
- **Locations:** `TrashAction.swift:14-23` moves the item, and only the result record (`RunLoop.swift:141`) has the
  trashed path. `HistoryRun.swift:110` shows an intent without a result as "Interrupted", with no restorability. No
  code asks before quitting: there is no `applicationShouldTerminate`, and closing the main window quits the app
  (D-99), during a run too.
- **Why it matters:** quitting during a long run is ordinary. The item is in the Trash, History cannot put it back,
  and the user has to find it by hand before the Trash is emptied. R-05's crash leads here too.
- **Fix (hard stop: Execution and the log's schema):**
  1. The Trash intent record carries the item's `identity` (the optional field result records already have; the scan
     or `TrashAction` reads it before the move). A move into the Trash on the same volume keeps the file number (D-84).
  2. `Restorability` treats an interrupted Trash intent as restorable when its original path is gone and an entry
     directly inside the Trash has that identity; the trashed path is that entry's. Otherwise it stays "Interrupted".
  3. The app asks before quitting, or closing the window, while a run is under way: "Stop the run and quit?" Quit
     then cancels the run and waits for the item in hand.
- **Size:** about 60 lines in Execution and History, about 50 in the app. Two pull requests.

### R-05 Stop just before a tool launches can crash the app

- **Confidence:** verified (read; not reproduced, it is a race). Issue #114.
- **Location:** `ToolRunner.swift:186-199` stores the process in the shared state before `process.run()`. A `stop()`
  from the cancellation or timeout handler in that window gets the process and calls `terminate()` (`:134`), which
  raises an Objective-C exception on a process that has not launched. Line 144 reads `isRunning` on the same process.
- **Fix:** keep a `launched` flag in the state, set after `run()` returns. `stop()` records the reason and signals
  only a launched process; the code after `run()` already ends a process whose stop came early (`:206-207`).
- **Size:** about 10 lines. Execution change.

### R-06 SAF-018 is not built

- **Confidence:** verified (read). PRD: SAF-018 (Must, added by D-135).
- **What is missing:** nothing stops a second launch of the same build, and `HistoryLog` takes no `flock`. Two
  instances can run plans at once and interleave their records; each record is one `write`, so lines stay whole, but
  two runs can act on the same items.
- **Fix:** at launch, if another instance of this bundle ID is running, activate it and exit, before any model is
  built. `HistoryLog` takes an exclusive, non-blocking `flock` on its descriptor for the life of a run's log handle;
  a second lock fails with a `HistoryError` the run sheet words ("Another Shuck window is running a cleanup").
  SAF-018's unit test: a second lock is refused while the first is held.
- **Size:** about 40 lines. `History/` and the app; not Execution. `flock` changes no file, so no static check
  changes.

## Medium

### R-07 Building a plan blocks the main actor

- **Confidence:** verified (probe). PRD: NFR-PERF-001. Issue #62.
- **Location:** `FileCleanupModel.reviewMoveToTrash` and `confirmRebuildable` (`FileCleanupModel.swift:319-348`) build
  the plan on the main actor. Each item costs a `realpath` of its parent, two attribute reads, a volume lookup and a
  comparison with every protected location.
- **Evidence:** the probe planned 5,000 fixture files with `Plan(subTool:)`: 1.69 s, and 2.39 s with 20 exclusions
  (debug build, about 0.34 ms per item). The limit is 250 ms, so about 700 selected files reach it. The release build
  will be faster, but not seven times.
- **Fix:** build the plan in a `@concurrent` function and show the sheet when it returns; M2-F03's Instruments
  measurement is then not needed. Folding the protected locations once per guard is a second, optional step.
- **Size:** about 40 lines in the app. No engine change for the first step.

### R-08 A stray `node_modules` in a project folder hides every project below it

- **Confidence:** verified (probe). **Revisits D-152 (7), D-153 (12).** PRD: DEV-006.
- **Evidence:** with projects at `Developer/app` and `Developer/web/site`, the scan lists both. After adding
  `Developer/node_modules/left-pad` (what an `npm install` run in the wrong folder leaves), it lists nothing. With a
  `Developer/package-lock.json` too, it lists one item, `Developer/node_modules`, and judges it by every file in
  `Developer`. Large Files and Old Files list nothing inside any of these `node_modules` either (D-152 (5)).
- **Fix:** a `node_modules` directly in a project folder (level 0) is listed if it has a lockfile, and the walk goes
  on into the other folders. Below level 0 the top-most rule stays as it is.
- **Size:** about 10 lines. Scan only; no rule or root changes.

### R-09 About 40 strings are missing from the String Catalogs

- **Confidence:** verified (script, then `grep` for twelve of them). PRD: NFR-L10N-001. Issue #116 names two.
- **What is missing:** every string M2-T11 added. In the app, about 25: the "Clean Up" wording of
  `SummaryConfirmationSheet` (lines 28-187), `OutcomeWording`'s four tool endings (88-91), `SizeText` ("Up to …",
  "Size not known"), `HistoryItemDisplay` ("Tool command", "Launchd job"), `HistoryView` ("Completed", "… of … done")
  and one help tag in `DeveloperJunkView`. In the engine, about 15: the names, descriptions and explanations of
  DEV-R03, DEV-R07, DEV-R08 and DEV-R09, "Package managers" and `ToolID`'s "Restore". The strings of M2-T12 to M2-T14
  are all there.
- **Why it matters:** English shows correctly, since the key is the text. The rule is broken all the same, and no
  check finds it: a command-line build adds no keys (`AGENTS.md`).
- **Fix:** add the entries, and add a check to `scripts/lint.sh` that fails when a string literal passed to `Text`,
  `Button`, `Label`, `.help`, `.alert` or `LocalizedStringResource` has no key. The script this review used is about
  40 lines of Python; the check can be a simpler `grep` over extracted literals.
- **Size:** catalog entries only, plus the check.

### R-10 Items a scan cannot measure vanish silently

- **Confidence:** verified (read). PRD: SAF-011, SAF-012, ONB-002. Issue #118.
- **What is fixed already:** every Developer Junk loop now reports a folder it cannot list (`.notAccessible` or
  `.unreadable`). M2-F17's wording is out of date on that point.
- **What remains:**
  - an item whose snapshot or date cannot be read, or that the guard refuses as not readable, is skipped with
    `continue` and no event (`DeveloperJunk.swift:238-243,286-289,326-330,375-379`, `CachesAndLogs.swift:242-244`);
  - `ItemSnapshot.read` enumerates with no error handler (`ItemSnapshot.swift:38`), so a subfolder it cannot read
    makes a measured size too small, with no sign;
  - `ScanResults` keeps counts, not the folders, and Developer Junk's page shows neither; only the landing page and
    Caches & Logs' page say "not accessible".
- **Fix:** emit `.notAccessible(url)` for those skips; give the enumerator an error handler that marks the snapshot
  incomplete (a scan-time field only, so re-validation's comparison does not change); show the note on Developer
  Junk's page. ONB-002's banner that lists the folders is M5.
- **Size:** about 50 lines in the engine and the app. `ItemSnapshot` is read by Execution, so the change must leave
  `matches` and `check` as they are.

### R-11 Delete holds a descriptor per folder level; a failed Restore leaves folders behind

- **Confidence:** verified (read). Issues #119, #120.
- **Locations:** `DeleteAction.withFolder` (`:67-77`) keeps each folder open while it empties the ones inside, and
  `entries` (`:107-115`) adds a second descriptor while it lists. A `node_modules` tree is the deepest target Shuck
  has. `RestoreExecutor.swift:95-106` creates missing parent folders, and leaves them if the move then fails.
- **Fix:** read a folder's entries, close the listing, and descend with one descriptor per level at most; or stop
  with `EMFILE` reported as the item's failure, which it already is. Restore removes the folders it created, deepest
  first, with `rmdir`, which removes only an empty folder.
- **Size:** about 40 lines. Execution change.

### R-12 The two acceptance checks the PRD names are not built

- **Confidence:** verified (read). PRD: HIS-001, NFR-QA-001 (D-133).
- **What is missing:** no test stops a run between an intent and its result record and then checks History and
  Restore; and no static check fails when a Must SAF requirement is named in no test. Today SAF-018 is named in none.
  SAF-003 is named only in app and UI tests, SAF-017 only in the scripts, which is where their checks live.
- **Fix:** the interrupted-run test comes with R-04's fix, which it tests. The static check greps tests and scripts
  for each Must SAF ID in a list kept in the script.
- **Size:** tests and about 15 lines of bash. A change to the static checks is a hard stop.

### R-13 `xcrun` counts as "Xcode is installed"; a stopped tool's children keep running

- **Confidence:** verified (read). PRD: DEV-002, DEV-004, SAF-014. Issue #127.
- **Detection:** DEV-R03 is listed when `/usr/bin/xcrun` runs and `CoreSimulator/Devices` exists. On a Mac whose
  Xcode was removed, both hold, and running `xcrun simctl` can raise the "install the command line developer tools"
  prompt, which DEV-002 names. Fix: also require the active developer folder (`/var/db/xcode_select_link`, read as a
  link) to hold `usr/bin/simctl`.
- **Children:** on Stop or timeout only the tool's own process is signalled (`ToolRunner.swift:137-147`), while
  History says the tool was stopped. `Process` cannot start a process group; `posix_spawn` with
  `POSIX_SPAWN_SETPGROUP` can.
- **Fix for the second:** see question 7.
- **Size:** detection about 10 lines, not Execution. The process group is about 80 lines of Execution.

### R-14 A skip caused by an exclusion reads "failed a safety check"

- **Confidence:** verified (read). **Revisits D-149 (8).**
- **What happens:** the guard refuses a path inside an exclusion as `protectedLocation`, the log records
  `rejected: protectedLocation <excluded path>`, and every page words `rejected` as "Skipped: failed a safety check".
  It happens for Restore into a folder excluded since the item was trashed, and for a run's item excluded after its
  plan was made.
- **Fix:** see question 1.

### R-15 Agent choices changed the path guard's inputs and a PRD row without the owner

- **Confidence:** verified (read). `AGENTS.md`: the hard stops; D-146.
- **What happened:**
  - D-145 (4) made `Archives` an allowed root one level wider than the rule's targets, and D-153 (3) made every
    project folder an allowed root. The guard's code did not change, but allowed roots are its input for rule (c):
    both widened what the guard accepts, and both decisions say that only a scan or a page keeps a plan narrow
    (R-03). They were recorded as agent choices.
  - D-154 (9) used the default project folders without the user opening Settings, and the same pull request reworded
    PRD SET-003 from "default suggestion" to "…, used until the user changes the list", which settles the question it
    left open.
- **Proposal:** add to `AGENTS.md`'s hard stops: "a change to a sub-tool's allowed roots" and "a change to a PRD
  requirement's text that settles an open question". The agent may still edit the PRD to match a decision the owner
  made.

## Low

### R-16 An allowed root that becomes a link is followed out of the home folder

- **Confidence:** verified (read), not probed. PRD: SAF-007 (c), SET-003.
- **What happens:** the guard resolves each allowed root (`PathGuard.swift:84`) and has no rule that a root lies in the
  home folder. `DeveloperJunk.projects(home:)` compares paths as text. If a project folder is replaced by a link to
  another folder on the startup volume after it was stored, a plan's targets inside it resolve outside the home
  folder and still pass rule (c). The scan skips a project folder that is a link, and re-validation compares dates and
  sizes, so reaching this needs the user to swap the folder between a scan and a run.
- **Fix:** with R-03's pull request, if the owner agrees: `allowedRoots(home:)` drops a root that does not resolve
  strictly inside the resolved home folder.

### R-17 Pages hand the model a sub-tool value

- **Confidence:** verified (read). **Revisits D-154 (3).**
- **What happens:** `FileCleanupModel.scan(_:)`, `confirmRebuildable(_:)` and `reviewMoveToTrash(_:urls:)` take the
  sub-tool from the caller. `SubToolPages` passes the model's current Developer Junk, so today's pages are right, but
  the model would plan with the roots of whatever copy it is handed.
- **Fix:** these three take a `ToolID` and look the sub-tool up in the model. About 20 lines, with R-07.

### R-18 Release and check scripts pass when they should fail

- **Confidence:** from issues #66, #121, #122 and #123, verified by the review of 2026-11-10; `build-dmg.sh` lines
  47-48 and 78 read again here.
- **What:** `build-dmg.sh` pipes `xcodebuild` into an `awk` that exits early under `pipefail`, and continues with an
  empty version (#66); its `get-task-allow` check reads `codesign … || true`, so it passes when `codesign` fails
  (#121); `notarize.sh` aborts before printing Apple's log (#121); `static-checks.sh` scans files git does not track,
  such as `.claude/worktrees` (#122), and misses calls wrapped across lines and some APIs (#123).
- **Fix:** as the issues say. The two static-check changes are a hard stop.

### R-19 Six open issues belong to no task

- #123 (static checks miss wrapped calls), #124 (a pull request that changes the CI gate scripts is judged by its own
  version and can auto-merge), #125 (the release workflow's tag check), #126 (Release is never built before a tag),
  #127 (tool children) are open and not in `docs/progress.md`. #65 is open though M2-F04 fixed it and D-111 made it
  moot.
- **Proposal:** #123 with R-18; #127 with R-13; #124 and #125 in the documentation pull request plus owner settings
  (question 8); #126 as a line under M5; close #65.

### R-20 Stale comments and PRD rows

- `DeveloperJunk.swift:4-8`: the comment says "ten" rules (there are nine) and its sentence is broken.
- PRD DEV-R05's target is `Archives/*` and DEV-R06's is `<project folders>/**/node_modules`; the code has
  `*/*.xcarchive` (D-145) and a depth limit of four levels (D-153). Say so in the rows.
- `docs/progress.md`'s M2-F17 and M2-F19 describe gaps that are partly closed (R-10) or settled: SAF-003's list shows
  each item's path from the home folder (`SummaryConfirmationSheet.swift:89-93`, read only as far as `ItemRow`'s
  call), and DEV-002 now says tools installed through nvm and the like are not found.

## The agent choices D-145 to D-154

| Decision | Verdict | Notes |
|---|---|---|
| D-145 Xcode Archives | Agree, except (4) | One item per bundle is right. The root wider than the targets should have gone to the owner (R-15); R-03 closes the gap it notes. |
| D-146 | Not reviewed | The owner's choice. R-15 proposes two more hard stops. |
| D-147 "Your data" on Developer Junk's page | Agree | Two actions, one per tier, and Select All leaving archives out match SAF-002 and SAF-004. |
| D-148 T14 before T13 | Agree | |
| D-149 Exclusions in scans | Agree, except (8) | (8) is question 1. |
| D-150 Storing exclusions | Agree | One source for three guards, and a run that keeps the guard it started with, are the right shape. |
| D-151 Exclusions in Settings | Agree | |
| D-152 Who owns `node_modules` | Agree, except (7) | (7) is R-08. (5), a `node_modules` no sub-tool lists, is acceptable: it hides nothing a user could act on. |
| D-153 DEV-R06 | Disagree with (3), (10), (12); agree with the rest | (3) and (10): R-03 and R-15. (12): R-08. (7), no running-app check, is acceptable: Shuck cannot see a dev server. (11) is question 4. |
| D-154 Project folders in Settings | Agree, except (9) and the PRD edit | (9) is question 2. (3): R-17. |

## Questions for the owner

Each has a recommendation. Questions 3, 5 and 6 are hard stops: nothing is built before the owner answers.

1. **Restore into a folder that is now excluded (D-149 (8)).** Recommended: keep the refusal, since letting Restore
   ignore an exclusion would be a special case in the guard, and word it. The executors log
   `rejected: userExclusion <path>` when the refused path overlaps a user exclusion (they have the configuration), and
   the wording becomes "Skipped: it is in a folder you excluded in Settings". The item stays in the Trash, and the
   user can remove the exclusion or move it back in Finder. Execution change, no guard change.
2. **The default project folders are used before the user opens Settings (D-154 (9)).** Recommended: keep it, and
   confirm the PRD's new wording. Scanning only reads, every Delete goes through the confirmation, and each row says
   that restoring needs a network. Without the defaults, DEV-R06 finds nothing until the user finds Settings. The
   alternative is to list the default folders' projects but never preselect them until the user has saved the list
   once.
3. **A project folder is an allowed root, and a Trash item needs no rule (D-153 (10)). Hard stop.** Recommended:
   R-03's fix, so every item of Developer Junk and Caches & Logs needs a rule match in the plan and in the run, and
   R-16's check that a root stays inside the home folder.
4. **A run does not repeat `node_modules` staleness (D-153 (11)).** Recommended: accept. DEV-005 makes staleness the
   default selection only, and a user may select a recent project by hand; SAF-008's checks on the target itself
   still run. DerivedData works the same way.
5. **How to make an interrupted Trash item restorable (R-04). Hard stop.** Recommended: the identity in the intent
   record, found again among the Trash's direct entries, plus the question before quitting. The alternative, a
   recovery step that writes missing result records at the next launch, changes the log after the fact.
6. **Static-check changes (R-12, R-18). Hard stop.** Recommended: approve three: only tracked files are scanned
   (#122); continuation lines are joined before matching and the APIs of #123 are added; and the check that every
   Must SAF requirement is named in a test.
7. **Children of a stopped tool (#127).** Recommended for 0.2.0: the result record's detail says that processes the
   tool started may still be running, and History shows it. The `posix_spawn` rewrite of the runner's launch goes to
   M5's security pass. The alternative is the rewrite now, before the first release with tool commands.
8. **Repository settings (#124, #125).** Recommended: the owner adds `.github/CODEOWNERS` for `scripts/` and
   `.github/` and a tag ruleset for `v*`; `AGENTS.md` says a pull request that touches those paths never auto-merges.
9. **Two more hard stops in `AGENTS.md` (R-15).** Recommended: yes.

## Proposed pull requests

One stack at a time, in this order. Sizes are production lines. New task IDs continue from M2-F20. "Closes" lists the
`docs/progress.md` item and the issues.

**Stack 1: what 0.2.0 must not ship without, with no hard stop.** The agent can start it as soon as the owner
approves the breakdown.

| # | Title | Scope | Size | Safety/Exec | Hard stop | Closes |
|---|---|---|---|---|---|---|
| 1 | `[M2-F19] An unknown app's cache starts unselected` | R-01, CAC-009's fixture test | ~25 | No | No | part of M2-F19 |
| 2 | `[M2-F19] npm and pip stay off the network, and simctl needs Xcode` | R-02, R-13's detection, owner item for the network check | ~20 | No | No | M2-F19 |
| 3 | `[M2-F21] A stray node_modules does not hide projects` | R-08 | ~10 | No | No | new |
| 4 | `[M2-F17] Scans report what they cannot measure` | R-10 | ~50 | No (reads only) | No | M2-F17, #118 |
| 5 | `[M2-F17] String Catalog entries and a check for missing ones` | R-09 | catalog + ~20 bash | No | No | M2-F17, #116 |
| 6 | `[M2-F03] Plans are built off the main actor` | R-07, R-17 | ~60 | No | No | M2-F03, #62 |

**Stack 2: Safety and Execution, each a pull request of its own (D-62).** Starts after the owner answers questions 1,
3, 5 and 7.

| # | Title | Scope | Size | Safety/Exec | Hard stop | Closes |
|---|---|---|---|---|---|---|
| 7 | `[M2-F22] Every rule-based item needs its rule` | R-03, R-16 | ~40 | Safety, Planning, Execution | Yes (Q3) | new |
| 8 | `[M2-F14] The tool runner never signals a process that has not launched` | R-05, and question 7's detail text | ~20 | Execution | Yes | M2-F14, #114, #127 in part |
| 9 | `[M2-F15] Delete with one descriptor per level, and Restore cleans up after a failed move` | R-11 | ~40 | Execution | Yes | M2-F15, #119, #120 |
| 10 | `[M2-F13] An interrupted Trash item can be restored` | R-04 steps 1 and 2, and R-12's interrupted-run test | ~60 | Execution, History | Yes (Q5) | M2-F13, #115, half of M2-F16 |
| 11 | `[M2-F13] Shuck asks before quitting during a run` | R-04 step 3 | ~50 | No (app) | No | M2-F13 |
| 12 | `[M2-F12] One running instance, and a locked history log` | R-06 | ~40 | History | No | M2-F12 |
| 13 | `[M2-F23] A skip caused by an exclusion says so` | R-14 | ~25 | Execution | Yes (Q1) | new |

**Stack 3: checks, scripts and documents.** Starts after the owner answers questions 6, 8 and 9.

| # | Title | Scope | Size | Safety/Exec | Hard stop | Closes |
|---|---|---|---|---|---|---|
| 14 | `[M2-F18] Static checks: tracked files, wrapped calls, and SAF IDs named in tests` | R-12's static check, R-18's two | ~50 bash | Static checks | Yes (Q6) | M2-F16, M2-F18 in part, #122, #123 |
| 15 | `[M2-F18] Release scripts fail when a check fails` | R-18's `build-dmg.sh` and `notarize.sh` | ~20 bash | No | No | M2-F18, #121, #66 |
| 16 | `[M2-F24] PRD rows, AGENTS.md rules and issue housekeeping` | R-15, R-19, R-20, question 8's `AGENTS.md` line; #126 as an M5 line; close #65 | docs | No | Yes for the `AGENTS.md` rules (Q9) | new, #124 and #125 in part |

After stack 3 come the 0.2.0 release items already in `docs/progress.md`, and the owner's exit check on their own Mac.

Not proposed for M2: the `posix_spawn` process group (#127, M5 if question 7 is answered as recommended), a required
Release build in CI (#126, M5), ONB-002's banner that lists skipped folders (M5), and the left-overs D-92 and D-121
already record.

## Checks run for this review

On `main` at b0f707e, in the agent's sandbox:

- `scripts/static-checks.sh`: OK. `scripts/static-checks-test.sh`: passed. `scripts/lint.sh`: clean.
  `scripts/release-notes.sh --check`: OK.
- `scripts/test.sh --no-ui`: passed. Engine coverage is 95.6% (3,105 of 3,249 lines of `ShuckKit` and
  `ShuckExecution`).
- UI tests cannot run in the sandbox (`AGENTS.md`). CI's `Lint, build and test` check, which runs them, passed on the
  last pull request of each recent stack: #141, #145 and #149.
- Four probe tests in a copy of the package: R-01, R-03, R-08 and R-07's timing. They are not in the repository; the
  findings above give their inputs and results.
