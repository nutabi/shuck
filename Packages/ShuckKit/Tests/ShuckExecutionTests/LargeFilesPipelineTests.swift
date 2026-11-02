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

        var items: [ScanItem] = []
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        for await event in subTool.scan(context) {
            if case .item(let item) = event { items.append(item) }
        }
        #expect(items.map(\.url.lastPathComponent) == [large.lastPathComponent])

        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        let logFolder = HistoryLog.folder(home: root.url)
        let trash = root.url.appending(path: ".Trash")
        let executor = TrashExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: logFolder), trash: FakeTrash(folder: trash))
        let report = await executor.run(plan)

        #expect(report.outcomes.allSatisfy { if case .trashed = $0.result { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: large.path))
        #expect(FileManager.default.fileExists(atPath: small.path))
        let results = try HistoryLog.read(folder: logFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.largeFiles])
        #expect(results.allSatisfy { $0.status == .ok && $0.trashedPath != nil })
    }
}
