import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Sub-tools are independent: a failure in one leaves another's scan and run unaffected (FCL-002).
struct SubToolIndependenceTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let healthy = FixtureSubTool(id: ToolID(rawValue: "TSA"))
    let broken = FixtureSubTool(id: ToolID(rawValue: "TSB"))

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test func failuresInOneSubToolLeaveAnothersScanAndRunUnaffectedFCL002() async throws {
        let wanted = [try root.file("Healthy/a.bin", size: 4_000), try root.file("Healthy/b.bin", size: 8_000)]
        let vanishing = try root.file("Broken/c.bin", size: 4_000)
        let key = try root.file(".ssh/id_ed25519", size: 10)
        let ownership = OwnershipMap(
            home: root.url,
            entries: [
                .init("Healthy", owners: [healthy.id]), .init("Broken", owners: [broken.id]),
                .init(".ssh", owners: [broken.id]),
            ])
        let context = ScanContext(home: root.url, ownership: ownership)

        // Both scans run at once, and each finds only what it owns.
        async let healthyScan = items(from: healthy, context: context)
        async let brokenScan = items(from: broken, context: context)
        let (healthyItems, brokenItems) = await (healthyScan, brokenScan)
        #expect(Set(healthyItems.map(\.url.path)) == Set(wanted.map(\.path)))
        #expect(Set(brokenItems.map(\.url.path)) == [vanishing.path, key.path])

        // Failure 1: the broken sub-tool found a protected file, so the path guard rejects its whole plan (SAF-007).
        #expect(throws: PlanError.self) { try Plan(subTool: broken, items: brokenItems, pathGuard: pathGuard) }

        // Failure 2: its file vanishes between review and run, while the healthy sub-tool runs at the same time.
        let brokenPlan = try Plan(
            subTool: broken, items: brokenItems.filter { $0.url == vanishing }, pathGuard: pathGuard)
        let healthyPlan = try Plan(subTool: healthy, items: healthyItems, pathGuard: pathGuard)
        try FileManager.default.removeItem(at: vanishing)
        let logFolder = HistoryLog.folder(home: root.url, bundleID: ShuckKit.bundleID)
        let executor = TrashExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: logFolder),
            trash: FakeTrash(folder: root.url.appending(path: ".Trash")))
        async let healthyRun = executor.run(healthyPlan)
        async let brokenRun = executor.run(brokenPlan)
        let (healthyReport, brokenReport) = await (healthyRun, brokenRun)

        #expect(brokenReport.outcomes.map(\.result) == [.skipped(.missing)])
        #expect(healthyReport.outcomes.allSatisfy { if case .trashed = $0.result { true } else { false } })
        #expect(wanted.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: key.path))
        let results = try HistoryLog.read(folder: logFolder).records.filter { $0.phase == .result }
        #expect(results.filter { $0.tool == healthy.id }.allSatisfy { $0.status == .ok })
        #expect(results.filter { $0.tool == healthy.id }.count == wanted.count)
    }

    private func items(from subTool: FixtureSubTool, context: ScanContext) async -> [ScanItem] {
        var items: [ScanItem] = []
        for await event in subTool.scan(context) {
            if case .item(let item) = event { items.append(item) }
        }
        return items
    }
}
