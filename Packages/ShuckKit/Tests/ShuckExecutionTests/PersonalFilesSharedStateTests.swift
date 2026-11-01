import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Large Files and Old Files share one personal-files scan and its item state (FCL-006).
struct PersonalFilesSharedStateTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test func aFileTrashedThroughOneSubToolLeavesBothFCL006() async throws {
        let yearsAgo = Date.now.addingTimeInterval(-2 * 365 * 86_400)
        let bigAndOld = try root.file("Movies/holiday.mov", size: 64_000, modified: yearsAgo)
        let bigOnly = try root.file("Movies/recent.mov", size: 64_000)
        let oldOnly = try root.file("Documents/notes.txt", size: 10, modified: yearsAgo)

        var state = PersonalFilesState()
        let scanner = PersonalFilesScanner(
            context: ScanContext(home: root.url), protection: root.pathGuardConfiguration())
        for await event in scanner.scan() {
            state.apply(event)
        }
        // Stand-ins for the sub-tools' filters (M1-T09, M1-T11): both read the same state.
        func largeFiles() -> Set<URL> {
            Set(state.items.values.filter { $0.snapshot.allocatedSize >= 64_000 }.map(\.url))
        }
        func oldFiles() -> Set<URL> {
            Set(state.items.values.filter { ($0.modified ?? .now) < .now.addingTimeInterval(-365 * 86_400) }.map(\.url))
        }
        #expect(largeFiles() == [bigAndOld, bigOnly])
        #expect(oldFiles() == [bigAndOld, oldOnly])

        // Old Files trashes the file that both list.
        let item = try #require(state.items[bigAndOld]?.scanItem(source: .oldFiles, reason: "Not opened in 2 years"))
        let plan = try Plan(
            tool: .oldFiles, allowedRoots: [root.url],
            items: [PlannedItem(url: item.url, tier: item.tier, method: item.method, snapshot: item.snapshot)],
            pathGuard: pathGuard)
        let executor = TrashExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: HistoryLog.folder(home: root.url)),
            trash: FakeTrash(folder: root.url.appending(path: ".Trash")))
        let report = await executor.run(plan)
        state.remove(report.outcomes.filter { if case .trashed = $0.result { true } else { false } }.map(\.item.url))

        #expect(!FileManager.default.fileExists(atPath: bigAndOld.path))
        #expect(largeFiles() == [bigOnly])
        #expect(oldFiles() == [oldOnly])
    }
}
