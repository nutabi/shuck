import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The tools registry, the sub-tool interface and the scan item model (FCL-001, FCL-003, SAF-001).
struct ToolRegistryTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    // MARK: - Registry (FCL-001)

    @Test func fileCleanupHasFourAvailableSubToolsFCL001FCL003() {
        let fileCleanup = ToolRegistry.standard.tools.first { $0.info.id == .fileCleanup }
        #expect(fileCleanup?.subTools.map(\.id) == [.largeFiles, .oldFiles, .developerJunk, .cachesAndLogs])
        #expect(ToolRegistry.standard.subTools.count == 4)
        #expect(ToolRegistry.standard.subTools.allSatisfy { $0.info.availability == .available })
    }

    @Test func theSubToolsTakeTheLimitsTheAppPassesSET002() {
        let standard = ToolRegistry.standard
        #expect((standard.subTool(.largeFiles) as? LargeFiles)?.minimumSize == LargeFiles.defaultMinimumSize)
        let oldFiles = standard.subTool(.oldFiles) as? OldFiles
        #expect(oldFiles?.periodMonths == OldFiles.defaultPeriodMonths)
        #expect(oldFiles?.minimumSize == OldFiles.defaultMinimumSize)

        let custom = ToolRegistry.standard(
            largeFiles: LargeFiles(minimumSize: 1_000), oldFiles: OldFiles(periodMonths: 3, minimumSize: 0))
        #expect((custom.subTool(.largeFiles) as? LargeFiles)?.minimumSize == 1_000)
        #expect((custom.subTool(.oldFiles) as? OldFiles)?.periodMonths == 3)
        #expect((custom.subTool(.oldFiles) as? OldFiles)?.minimumSize == 0)
    }

    @Test func theRegistryFindsToolsAndSubToolsAndAPlannedSubToolDoesNothingSAF007() async throws {
        #expect(ToolRegistry.standard.info(.fileCleanup)?.symbolName == "folder")
        #expect(ToolRegistry.standard.info(.cachesAndLogs)?.symbolName == "tray.full")
        #expect(ToolRegistry.standard.info(FixtureSubTool.id) == nil)

        // No sub-tool is planned any more, so the test makes one: it finds nothing and cannot plan anything.
        let planned = PlannedSubTool(
            info: ToolInfo(
                id: .cachesAndLogs, name: "Planned", summary: "Comes later.", symbolName: "clock",
                availability: .planned(milestone: "M9")),
            tiers: [.rebuildable])
        try root.file("Library/Caches/com.example.Other/cache.db", size: 10)
        var events: [ScanEvent] = []
        for await event in planned.scan(ScanContext(home: root.url)) { events.append(event) }
        #expect(events.isEmpty)

        let item = try scanItem("Library/Caches/com.example.App", source: .cachesAndLogs, tier: .rebuildable)
        let error = #expect(throws: PlanError.self) {
            try Plan(subTool: planned, items: [item], pathGuard: pathGuard)
        }
        guard case .rejected(_, .outsideAllowedRoots) = error else {
            Issue.record("Expected an allowed-roots rejection, got \(String(describing: error))")
            return
        }
    }

    // MARK: - Scan items (SAF-001)

    @Test func aScanItemCarriesEveryFieldSAF001() throws {
        let file = try root.file("Movies/clip.mov", size: 50_000)
        let snapshot = try #require(ItemSnapshot.read(file))
        let item = ScanItem(
            url: file, snapshot: snapshot, tier: .yourData, method: .trash, reason: "Larger than 500 MB",
            source: .largeFiles, confidence: .high)

        #expect(item.tier == .yourData && item.method == .trash)
        #expect(item.allocatedSize == snapshot.allocatedSize && item.allocatedSize > 0)
        #expect(String(localized: item.reason) == "Larger than 500 MB")
        #expect(item.source == .largeFiles && item.confidence == .high)
    }

    // MARK: - Plans from a sub-tool (FCL-002)

    @Test func aPlanTakesTheSubToolsIDAndRoots() throws {
        let item = try scanItem("Downloads/a.zip", source: FixtureSubTool.id)
        let plan = try Plan(subTool: FixtureSubTool(), items: [item], pathGuard: pathGuard)
        #expect(plan.tool == FixtureSubTool.id)
        #expect(plan.allowedRoots == [root.url])
        #expect(plan.items.map(\.url) == [item.url])
    }

    @Test func aPlanRejectsAnItemFromAnotherSubToolFCL002() throws {
        let item = try scanItem("Downloads/a.zip", source: .largeFiles)
        let error = #expect(throws: PlanError.self) {
            try Plan(subTool: FixtureSubTool(), items: [item], pathGuard: pathGuard)
        }
        #expect(error == .otherSubTool(item.target.description, .largeFiles))
    }

    @Test func aPlanRejectsATierTheSubToolDoesNotUse() throws {
        let item = try scanItem("Downloads/a.zip", source: FixtureSubTool.id, tier: .rebuildable, method: .delete)
        let error = #expect(throws: PlanError.self) {
            try Plan(subTool: FixtureSubTool(tiers: [.yourData]), items: [item], pathGuard: pathGuard)
        }
        #expect(error == .tierNotAllowed(item.target.description, .rebuildable))
    }

    private func scanItem(
        _ path: String, source: ToolID, tier: Tier = .yourData, method: ActionMethod? = nil
    ) throws -> ScanItem {
        let file = try root.file(path, size: 10)
        let method = method ?? (tier == .yourData ? .trash : .delete)
        // A plan refuses a Delete without a rule before it asks the guard (D-132).
        let rule = method == .delete ? RuleMatch(rule: try root.fixtureRule(for: file), modified: .now) : nil
        return ScanItem(
            url: file, snapshot: try #require(ItemSnapshot.read(file)), tier: tier, method: method, reason: "Test",
            source: source, ruleMatch: rule)
    }
}
