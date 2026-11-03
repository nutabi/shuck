import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Large Files' items go through the whole safety pipeline: scan, plan, Trash, log (LRG-004, FCL-003).
struct LargeFilesPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test func largeFilesAreMovedToTheTrashAndLoggedForRestoreLRG004() async throws {
        let large = try root.file("Downloads/Installer.dmg", size: 1 << 20)
        let small = try root.file("Downloads/notes.txt", size: 10)
        let subTool = LargeFiles(minimumSize: 1 << 20)

        let items = await items(
            from: subTool, context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()))
        #expect(items.map(\.url.lastPathComponent) == [large.lastPathComponent])

        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.allSatisfy { if case .done = $0.result { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: large.path))
        #expect(FileManager.default.fileExists(atPath: small.path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.largeFiles])
        #expect(results.allSatisfy { $0.status == .ok && $0.trashedPath != nil })
    }

    @Test func aFileReplacedBetweenScanAndRunIsNotTrashedSAF008() async throws {
        let installer = try root.file("Downloads/Installer.dmg", size: 1 << 20)
        let subTool = LargeFiles(minimumSize: 1 << 20)
        let items = await items(
            from: subTool, context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()))
        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        #expect(plan.items.map(\.identity) == [FileIdentity.read(installer)])

        // The installer is downloaded again: another file of the same kind and size at the same path.
        try FileManager.default.removeItem(at: installer)
        try root.file("Downloads/Installer.dmg", size: 1 << 20)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.replaced)])
        #expect(FileManager.default.fileExists(atPath: installer.path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.status) == [.skipped])
        #expect(results.map(\.detail) == ["replaced"])
    }
}
