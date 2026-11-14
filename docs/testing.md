# Testing

How to write and run Shuck's tests. The rules are in `AGENTS.md`; this file holds the detail.

## What a test checks

Fewer tests that each follow real use catch more than many that each check one line (owner preference, 2026-11-14,
#241). Before adding a test, look for one that already sets up the same thing.

- **Check each claim once, at the lowest level that shows it.** A rule's cases belong in engine tests; what a view
  model does with them in the app's unit tests; what a user sees in a UI workflow. Don't check an engine rule again
  in a view model test, or a view model's logic again in a UI step.
- **Same shape, one test.** Tests that differ only in their input are one `@Test(arguments:)` test. A rule every
  sub-tool follows, such as skipping an item changed since the scan (SAF-008), an app that starts after the scan
  (SAF-009) or a folder excluded after the plan (SET-001), is one test whose arguments are every sub-tool, never a
  sample of them.
- **A pipeline is a scenario.** A test of a sub-tool's run scans a fixture root, plans, runs, then reads History, and
  Restore where the method allows it, instead of one test per stage with the same setup.
- **No test of a constant, a raw value, wording, or of test support itself.** The fixture root's refusal to write
  outside itself (SAF-016) is the exception. Wording a user reads is checked in the UI workflow that shows it.
- **No wall-clock races.** A test never passes only because something happened within a time it doesn't control,
  such as a timeout under load or a cancel before a task starts. It waits for an event the code under test records
  (a marker file, a stream event, a hook), with a generous limit that only a broken build reaches. Delete a test that
  can't be made so, if another test asserts the same claim.
- **Keep the requirement IDs.** A merged test keeps every requirement ID the tests it replaces named, and every Must
  SAF ID stays named in a test (`scripts/static-checks.sh`). A pull request that removes a test lists it, with where
  its claim is checked now.
- **A slow test is a bug.** No unit test takes more than about a second. A test of the main actor blocks every other
  main-actor test while it runs.

## Test support

- `ShuckKitTestSupport` is shared by engine tests and the app's UI tests. Its helpers are `FixtureRoot` with `historyFolder` and `trashFolder`, and `items(from:context:)`, which collects a sub-tool's scan, and `app(_:bundleID:…)`, which writes a fake app bundle with a real `Info.plist`, and `tool(_:_:)`, which writes a fake tool (a script that exits, prints, sleeps or ignores SIGTERM) inside the root. `xcrun(_:)` writes the fake `xcrun` together with a fake Xcode's `simctl`, without which Developer Junk hides its `xcrun simctl` rule (DEV-002, D-157). Execution tests build a plan executor for a fixture root with `PlanExecutor(root:pathGuard:)`, whose tool runner finds tools only inside the root; a test never starts a process itself (D-82, D-114).
- Tests for `ShuckExecution` go in its own test target, `Tests/ShuckExecutionTests/`.

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
- A workflow that needs apps in Applications launches with `launch(appFolders:)`, whose paths are relative to the
  fixture root (`Applications`). Without it the app lists no apps and never reads the real `/Applications` (SAF-016).
  Last-opened dates are stubbed to none, so no UI test can show last-opened order; a unit test covers it.
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
- On a page with a search field in the toolbar (`.searchable`), XCUITest reports a table's column headers as not
  hittable, although they are visible, and its click fails after trying to scroll them into view. Click the header's
  center with `coordinate(withNormalizedOffset:)` instead, then check the order it gives (`UninstallAppUITests`).
- A SwiftUI `Text` with an `.accessibilityIdentifier` exposes its text as the element's `value`, and its `label` is
  empty. Read it with a small helper such as `element.label.isEmpty ? element.value as? String ?? "" : element.label`
  (`text(_:)` in `UninstallAppUITests`).
- `firstMatch` does not find a SwiftUI `DisclosureGroup` row's combined accessibility element, such as a run on the History page. Use `.element` on a query that matches exactly one element.
- `scripts/test.sh` prints only each suite's time. Per-test times are in the result bundles in `build/DerivedData/Logs/Test/`, which CI uploads only when a run fails (D-34). `xcrun xcresulttool get test-results tests --path <bundle>` lists each test's duration, and `xcrun xcresulttool get test-results activities --test-id "<Class>/<method>()" --path <bundle>` lists one test's steps with their start times.
