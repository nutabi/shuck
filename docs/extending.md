# Adding a sub-tool or a cleanup rule

**A new File Cleanup sub-tool** (FCL-003):

1. Implement the `SubTool` protocol in `ShuckKit`: its `ToolInfo` (ID, name, summary, symbol), tiers, allowed roots, and a scan that streams items. Put its name and summary in `ShuckKit`'s String Catalog, loaded with `#bundle`.
2. Register it in `ToolRegistry.standard`, replacing its `PlannedSubTool` placeholder if it has one. The sidebar and the File Cleanup landing page are built from the registry; do not edit them by hand.
3. Build its page on `SubToolPage` and add it to `SubToolPages`, by tool ID; `ContentView` needs no change (D-91). `SubToolPage` gives the toolbar with Scan and Stop, the scan when the page opens if the sub-tool has not scanned yet (`FileCleanupModel.scanIfNotScanned`), the message that stands in for an empty list (D-61) and the review sheet (D-77). The page gives its subtitle, messages, own toolbar controls and list. `FileCleanupModel` keeps its items in a `ScanResults` of its own.
4. Add its locations to `OwnershipMap.standardEntries`. Within File Cleanup, each location has exactly one owner (FCL-005), the most specific pattern wins, and the ownership test must still pass. Its scan skips anything the map does not give it.
5. Its scan hides anything inside or holding one of the user's exclusions (SET-001, D-149): check each path item with the
   guard, as Caches & Logs does. Add the sub-tool's fixtures to `ExclusionsTests`, which fails if a sub-tool that scans
   is left out.
6. Add fixture tests for its scan and for a full run through the safety pipeline, plus a UI smoke test for its main path (NFR-QA-003): a step in the UI workflow where a user would take that path, or a new workflow (see [testing.md](testing.md)). List it in `ShuckUITestCase`'s documentation comment (D-75).
7. Its ID goes in the history log's `tool` field (PRD section 8.5). Add it to the PRD.

A sub-tool must not require changes to other sub-tools or to the safety layer. If it does, that is a design change: the advisor decides it (`AGENTS.md`).

**A new Developer Junk or Caches & Logs rule** (DEV-001):

1. Add the rule as data in the engine: ID, name, description, detection, targets or tool command, tier, staleness rule, explanation, documentation link, and the bundle IDs of the apps that use its data (`apps`, D-110). Its scanner builds items with `CleanupRule.scanItem(…runningApps: context.runningApps…)`, which disables them while one of those apps runs (SAF-009).
2. Targets must lie inside the allowed roots. Data owned by a tool is cleaned with that tool's documented command, never deleted directly (SAF-010). Tool commands follow DEV-004.
3. Add the rule's locations to `OwnershipMap.standardEntries` (FCL-005).
4. A tool command's item is hidden when the folder it is sized from is, or holds, an exclusion: add the rule to
   `DeveloperJunk.toolFolder` and to the test in `ExclusionsTests` (SET-001, D-149).
5. Add a fixture test for a path rule, or a recorded-output test with a fake tool executable for a tool rule. Never parse tool output to choose deletion targets (R-07).
6. One rule per pull request. A rule that is not in the PRD's rule table (section 9.1.3) needs the advisor's decision first.
