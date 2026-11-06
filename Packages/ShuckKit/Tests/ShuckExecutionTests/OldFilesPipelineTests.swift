import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Old Files' items go through the whole safety pipeline: scan, plan, Trash, log (OLD-004, FCL-003).
struct OldFilesPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test func oldFilesAreMovedToTheTrashAndLoggedForRestoreOLD004() async throws {
        let yearsAgo = Date.now.addingTimeInterval(-2 * 365 * 86_400)
        let old = try root.file("Downloads/Installer.dmg", size: 1 << 20, modified: yearsAgo)
        let recent = try root.file("Downloads/Recent.dmg", size: 1 << 20)
        let subTool = OldFiles(minimumSize: 1 << 20) { _ in nil }

        let items = await items(
            from: subTool, context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()))
        #expect(items.compactMap { $0.url?.lastPathComponent } == [old.lastPathComponent])

        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.allSatisfy { if case .done = $0.result { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.oldFiles])
        #expect(results.allSatisfy { $0.status == .ok && $0.trashedPath != nil })
    }
}
