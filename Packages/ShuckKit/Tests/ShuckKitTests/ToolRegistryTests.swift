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

    @Test func toolsAreInSidebarOrder() {
        #expect(ToolRegistry.standard.tools.map(\.info.id) == [.fileCleanup, .applications, .startupItems])
    }

    @Test func fileCleanupHasFourSubToolsFCL001() {
        let fileCleanup = ToolRegistry.standard.tools.first { $0.info.id == .fileCleanup }
        #expect(fileCleanup?.subTools.map(\.id) == [.largeFiles, .oldFiles, .developerJunk, .cachesAndLogs])
        #expect(ToolRegistry.standard.subTools.count == 4)
    }

    @Test func idsAreUnique() {
        let ids = ToolRegistry.standard.tools.map(\.info.id) + ToolRegistry.standard.subTools.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func infoFindsToolsAndSubTools() {
        #expect(ToolRegistry.standard.info(.fileCleanup)?.symbolName == "folder")
        #expect(ToolRegistry.standard.info(.cachesAndLogs)?.symbolName == "tray.full")
        #expect(ToolRegistry.standard.info(FixtureSubTool.id) == nil)
    }

    @Test func namesAndSummariesComeFromTheEngineCatalog() {
        let largeFiles = ToolRegistry.standard.subTool(.largeFiles)
        #expect(largeFiles.map { String(localized: $0.info.name) } == "Large Files")
        #expect(largeFiles.map { String(localized: $0.info.summary) } == "What is taking the most space?")
    }

    @Test func personalFilesSubToolsAreYourDataOnly() {
        for id in [ToolID.largeFiles, .oldFiles] {
            #expect(ToolRegistry.standard.subTool(id)?.tiers == [.yourData])
        }
    }

    @Test func largeFilesIsAvailableWithTheMinimumSizeTheAppPassesSET002() {
        let standard = ToolRegistry.standard.subTool(.largeFiles) as? LargeFiles
        #expect(standard?.info.availability == .available)
        #expect(standard?.minimumSize == LargeFiles.defaultMinimumSize)

        let custom = ToolRegistry.standard(largeFiles: LargeFiles(minimumSize: 1_000)).subTool(.largeFiles)
        #expect((custom as? LargeFiles)?.minimumSize == 1_000)
    }

    @Test func oldFilesIsAvailableWithThePeriodAndMinimumSizeTheAppPassesSET002() {
        let standard = ToolRegistry.standard.subTool(.oldFiles) as? OldFiles
        #expect(standard?.info.availability == .available)
        #expect(standard?.periodMonths == OldFiles.defaultPeriodMonths)
        #expect(standard?.minimumSize == OldFiles.defaultMinimumSize)

        let custom = ToolRegistry.standard(oldFiles: OldFiles(periodMonths: 3, minimumSize: 0)).subTool(.oldFiles)
        #expect((custom as? OldFiles)?.periodMonths == 3)
        #expect((custom as? OldFiles)?.minimumSize == 0)
    }

    @Test func aTestSubToolRegistersAndIsFoundByIDFCL003() {
        let registry = ToolRegistry(tools: [Tool(info: FixtureSubTool().info, subTools: [FixtureSubTool()])])
        #expect(registry.subTool(FixtureSubTool.id)?.id == FixtureSubTool.id)
        #expect(registry.subTool(.largeFiles) == nil)
    }

    // MARK: - Planned sub-tools

    @Test func aPlannedSubToolFindsNothing() async throws {
        let cachesAndLogs = try #require(ToolRegistry.standard.subTool(.cachesAndLogs))
        #expect(cachesAndLogs.info.availability == .planned(milestone: "M2"))
        try root.file("Library/Caches/com.example.App/cache.db", size: 10)

        var events: [ScanEvent] = []
        for await event in cachesAndLogs.scan(ScanContext(home: root.url)) {
            events.append(event)
        }
        #expect(events.isEmpty)
    }

    @Test func aPlannedSubToolCannotPlanAnythingSAF007() throws {
        let developerJunk = try #require(ToolRegistry.standard.subTool(.developerJunk))
        let item = try scanItem("Library/Developer/Xcode/DerivedData/App", source: .developerJunk, tier: .rebuildable)
        let error = #expect(throws: PlanError.self) {
            try Plan(subTool: developerJunk, items: [item], pathGuard: pathGuard)
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
        #expect(error == .otherSubTool(item.url.path, .largeFiles))
    }

    @Test func aPlanRejectsATierTheSubToolDoesNotUse() throws {
        let item = try scanItem("Downloads/a.zip", source: FixtureSubTool.id, tier: .rebuildable, method: .delete)
        let error = #expect(throws: PlanError.self) {
            try Plan(subTool: FixtureSubTool(tiers: [.yourData]), items: [item], pathGuard: pathGuard)
        }
        #expect(error == .tierNotAllowed(item.url.path, .rebuildable))
    }

    private func scanItem(
        _ path: String, source: ToolID, tier: Tier = .yourData, method: ActionMethod? = nil
    ) throws -> ScanItem {
        let file = try root.file(path, size: 10)
        return ScanItem(
            url: file, snapshot: try #require(ItemSnapshot.read(file)), tier: tier,
            method: method ?? (tier == .yourData ? .trash : .delete), reason: "Test", source: source)
    }
}
