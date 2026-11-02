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

        var items: [ScanItem] = []
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        for await event in subTool.scan(context) {
            if case .item(let item) = event { items.append(item) }
        }
        #expect(items.map(\.url.lastPathComponent) == [old.lastPathComponent])

        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        let logFolder = HistoryLog.folder(home: root.url, bundleID: ShuckKit.bundleID)
        let executor = TrashExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: logFolder),
            trash: FakeTrash(folder: root.url.appending(path: ".Trash")))
        let report = await executor.run(plan)

        #expect(report.outcomes.allSatisfy { if case .trashed = $0.result { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        let results = try HistoryLog.read(folder: logFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.oldFiles])
        #expect(results.allSatisfy { $0.status == .ok && $0.trashedPath != nil })
    }
}
