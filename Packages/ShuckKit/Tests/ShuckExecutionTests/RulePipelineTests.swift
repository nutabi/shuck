import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Synthetic rules through scan-item construction, planning, re-validation, Delete and History. Every path and
/// mutation stays inside the fixture root (SAF-016); no real rule, app or tool is run.
struct RulePipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let fixture: RuleFixture
    var cache: URL { fixture.cache }
    var now: Date { fixture.now }
    var stale: Date { fixture.stale }
    var category: ItemCategory { fixture.category }

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        fixture = try RuleFixture(root, pathGuard)
    }

    func rule(
        scope: ItemScope = .item, detection: CleanupRule.Detection? = nil, apps: Set<String> = []
    ) throws -> CleanupRule {
        try fixture.rule(scope: scope, detection: detection, apps: apps)
    }

    func scanned(_ url: URL, rule: CleanupRule, running: Set<String> = []) throws -> ScanItem {
        try fixture.scanned(url, rule: rule, running: running)
    }

    func plan(_ items: [ScanItem]) throws -> Plan {
        try fixture.plan(items)
    }

    func run(_ plan: Plan, running: Set<String> = []) async throws -> RunReport {
        await (try PlanExecutor(root: root, pathGuard: pathGuard, runningApps: StubRunningApps(running))).run(plan)
    }

    @Test func unchangedStaleAndExplicitlyChosenRecentItemsAreDeletedAndLoggedSAF006DEV005() async throws {
        let old = try root.file("Library/Caches/Fixture/old.cache", size: 4096, modified: stale)
        let recent = try root.file("Library/Caches/Fixture/recent.cache", size: 8192, modified: now)
        let rule = try rule()
        let items = try [scanned(old, rule: rule), scanned(recent, rule: rule)]
        #expect(items.map(\.selection) == [.selected, .unselected])
        let plan = try plan(items)
        #expect(plan.items.map(\.ruleMatch) == items.map(\.ruleMatch))
        #expect(plan.items.map(\.category) == [category, category])

        let report = try await run(plan)

        #expect(report.outcomes.map(\.result) == [.done(nil), .done(nil)])
        #expect(
            !FileManager.default.fileExists(atPath: old.path) && !FileManager.default.fileExists(atPath: recent.path))
        let history = try HistoryLog.read(folder: root.historyFolder)
        #expect(history.records.map(\.phase) == [.intent, .result, .intent, .result])
        #expect(history.records.allSatisfy { $0.operation == .delete && $0.trashedPath == nil })
        #expect(history.records.filter { $0.phase == .result }.map(\.bytes) == items.map(\.allocatedSize))
        #expect(history.entries().map(\.restorability) == [.permanent, .permanent])
    }

    @Test func aRunningAppDisablesItsRuleItemsAtScanTimeSAF009CAC003() throws {
        let folder = try root.folder("Library/Caches/Fixture/build.cache", modified: stale)
        let rule = try rule(apps: ["com.example.Fixture"])
        // Bundle IDs compare without case, as a folder named after one may differ in case from the app.
        let busy = try scanned(folder, rule: rule, running: ["COM.EXAMPLE.fixture", "com.example.Other"])
        #expect(busy.selection == .appIsRunning(nil) && busy.apps == ["com.example.Fixture"])
        #expect(busy.selection.disabledReason.map { String(localized: $0) } == "App is running")
        #expect(throws: PlanError.notSelectable(folder.path)) { try self.plan([busy]) }
        let other = try scanned(folder, rule: rule, running: ["com.example.Other"])
        #expect(other.selection == .selected)
        #expect(try plan([other]).items.map(\.apps) == [["com.example.Fixture"]])
        // A rule that names no app is never disabled for a running one, as personal files and tool rules are not.
        #expect(try scanned(folder, rule: self.rule(), running: ["com.example.Fixture"]).selection == .selected)
    }

    @Test func aRecreatedFolderMustStillMatchTheRuleAndUnchangedModificationDateSAF008() async throws {
        let folder = try root.folder("Library/Caches/Fixture/build.cache", modified: stale)
        let item = try scanned(folder, rule: rule())
        let plan = try plan([item])
        // Keep the original allocated so a recreated folder cannot reuse its inode. Delete deliberately does not
        // compare file identity (D-103), but still checks the rule and modification date.
        try FileManager.default.moveItem(at: folder, to: root.url("Library/Caches/Fixture/retired"))
        let recreated = try root.folder("Library/Caches/Fixture/build.cache", modified: stale)
        #expect(item.identity == nil && item.snapshot == ItemSnapshot.read(recreated))
        let report = try await run(plan)
        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(!FileManager.default.fileExists(atPath: recreated.path))
        #expect(FileManager.default.fileExists(atPath: try root.url("Library/Caches/Fixture/retired").path))
    }

    @Test func aContentsRuleKeepsItsFolderCAC004() async throws {
        let folder = try root.folder("Library/Caches/Fixture/app.cache")
        try root.file("Library/Caches/Fixture/app.cache/cache.db", size: 4096)
        let report = try await run(plan([scanned(folder, rule: rule(scope: .contents))]))
        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func vanishedDetectionSkipsWithoutDeletingTheTargetSAF008DEV002() async throws {
        let marker = try root.folder("Metadata/FixtureTool")
        let file = try root.file("Library/Caches/Fixture/old.cache", size: 4096, modified: stale)
        let rule = try rule(detection: .folder(marker))
        let plan = try plan([scanned(file, rule: rule)])
        try FileManager.default.removeItem(at: marker)
        #expect(throws: RuleItemError.unavailable) { try scanned(file, rule: rule) }
        let report = try await run(plan)
        #expect(report.outcomes.map(\.result) == [.skipped(.ruleChanged)])
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try HistoryLog.read(folder: root.historyFolder).records.last?.detail == "ruleChanged")
    }

    @Test func aWrongTargetOrScopeIsRejectedInPlanningAndExecutionSAF008() async throws {
        let innocent = try root.file("Library/Caches/Fixture/keep.txt", size: 4096, modified: stale)
        let rule = try rule()
        #expect(throws: RuleItemError.targetMismatch) { try scanned(innocent, rule: rule) }
        let item = PlannedItem(
            url: innocent, tier: .rebuildable, method: .delete, snapshot: try #require(ItemSnapshot.read(innocent)),
            ruleMatch: RuleMatch(rule: rule, modified: stale))
        #expect(throws: PlanError.ruleMismatch(innocent.path)) {
            try Plan(tool: .cachesAndLogs, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
        }
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        #expect(await executor.act(on: item, allowedRoots: [root.url]).result == .skipped(.ruleChanged))
        #expect(PlanError.ruleMismatch(innocent.path).path == innocent.path)
        #expect(FileManager.default.fileExists(atPath: innocent.path))
        #expect(!rule.accepts(.path(innocent), tier: .yourData, method: .trash, scope: .item))
        let folder = try root.folder("Library/Caches/Fixture/app.cache")
        #expect(!rule.accepts(.path(folder), tier: .rebuildable, method: .delete, scope: .contents))
        let file = try root.file("Library/Caches/Fixture/file.cache", size: 4096, modified: stale)
        #expect(throws: RuleItemError.targetMismatch) { try scanned(file, rule: self.rule(scope: .contents)) }
        let undated = PlannedItem(
            url: file, tier: .rebuildable, method: .delete, snapshot: try #require(ItemSnapshot.read(file)),
            ruleMatch: RuleMatch(rule: rule, modified: nil))
        #expect(throws: PlanError.ruleMismatch(file.path)) {
            try Plan(tool: .cachesAndLogs, allowedRoots: [root.url], items: [undated], pathGuard: pathGuard)
        }
        #expect(await executor.act(on: undated, allowedRoots: [root.url]).result == .skipped(.ruleChanged))
    }

    @Test func ruleMatchingNeverBypassesThePathGuardSAF007() throws {
        let key = try root.file(".ssh/key.cache", size: 4096, modified: stale)
        let rule = try CleanupRule(
            id: "fixture", name: "Fixture", description: "Fixture", category: category,
            detection: .folder(root.url),
            action: .paths([RulePath(root: root.url, pattern: ".ssh/*")], method: .delete),
            tier: .rebuildable, selection: .always, explanation: "Fixture",
            documentation: #require(URL(string: "https://example.test/cache")))
        let item = try scanned(key, rule: rule)
        #expect(
            throws: PlanError.rejected(
                key.path, .protectedLocation(key.path, protected: root.url.appending(path: ".ssh").path))
        ) {
            try plan([item])
        }
    }

    @Test func aToolRuleBuildsOneCommandItemAndItsRunIsLoggedSAF001SAF006SAF010() async throws {
        let executable = try root.tool("tools/cleaner", .exits(0))
        let command = try ToolCommand(executable: executable.path, arguments: ["clean"], environment: ["PATH": "/bin"])
        let rule = try CleanupRule(
            id: "fixture", name: "Fixture", description: "Fixture", category: category,
            detection: .executable(executable.path),
            action: .command(command), tier: .rebuildable, selection: .always, explanation: "Fixture command",
            documentation: #require(URL(string: "https://example.test/cache")))
        let item = try rule.scanItem(
            estimatedBytes: 12_345, source: FixtureSubTool.id, runningApps: StubRunningApps(), now: now)
        #expect(item.url == nil && item.snapshot == nil && item.selection == .selected)
        #expect(rule.accepts(item.target, tier: item.tier, method: item.method, scope: item.scope))
        #expect(!rule.accepts(.path(executable), tier: .rebuildable, method: .tool, scope: .item))
        #expect(throws: RuleItemError.invalidEstimate) {
            try rule.scanItem(estimatedBytes: -1, source: FixtureSubTool.id, runningApps: StubRunningApps())
        }
        #expect(throws: RuleItemError.targetMismatch) {
            try self.rule().scanItem(estimatedBytes: 1, source: FixtureSubTool.id, runningApps: StubRunningApps())
        }
        let disabled = try rule.scanItem(
            estimatedBytes: 1, source: FixtureSubTool.id, runningApps: StubRunningApps(),
            disabledReason: "Fixture tool is busy")
        #expect(!disabled.selection.isSelectable)
        let report = try await run(plan([item]))
        #expect(report.outcomes.map(\.result) == [.done(nil)])
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.allSatisfy { $0.path == command.display && $0.bytes == 12_345 && $0.operation == .tool })
        #expect(records.map(\.phase) == [.intent, .result])
    }
}
