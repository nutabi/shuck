import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// A run that stops between a Trash move and its result record, as a quit or a crash does (HIS-001, SAF-005).
struct InterruptedRunTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    /// Runs a plan that trashes `url`, with a log that takes the intent record and fails on the result record, so the
    /// log ends as it would after a crash between the move and the result.
    private func interruptedRun(trashing url: URL, trash: FakeTrash? = nil) async throws {
        let plan = try Plan(
            tool: .largeFiles, allowedRoots: [root.url],
            items: [try root.planned(url, tier: .yourData, method: .trash)], pathGuard: pathGuard)
        let log = FailingLog(log: try HistoryLog(folder: root.historyFolder), recordsBeforeFailing: 1)
        let executor = PlanExecutor(
            pathGuard: pathGuard, log: log,
            actions: [.trash: TrashAction(trash: trash ?? FakeTrash(folder: root.trashFolder))])
        _ = await executor.run(plan)
    }

    private func history() throws -> [HistoryRun] {
        try HistoryLog.read(folder: root.historyFolder).runs(trashFolder: root.trashFolder)
    }

    private func restoreExecutor() throws -> RestoreExecutor {
        RestoreExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: root.historyFolder),
            trash: FakeTrash(folder: root.trashFolder))
    }

    @Test func anInterruptedTrashItemIsRestorableAndRestoreSendsItBackHIS001SAF005() async throws {
        let file = try root.file("Documents/report.pdf", size: 100)
        try await interruptedRun(trashing: file)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        let item = try #require(try history().first?.items.first)
        #expect(item.outcome == .interrupted)
        guard case .restorable(let trashed)? = item.restorability else {
            Issue.record("The interrupted item is not restorable: \(String(describing: item.restorability))")
            return
        }
        #expect(trashed.originalURL == file)
        #expect(trashed.trashedURL.deletingLastPathComponent().path == root.trashFolder.path)

        // Restore runs the same checks as for any item, including the identity.
        let report = await (try restoreExecutor()).run([RestoreRequest(item: trashed)])
        #expect(report.outcomes.map(\.result) == [.done(file)])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aFileThatTookTheTrashedNameIsNotRestoredHIS001SAF005() async throws {
        let file = try root.file("Documents/report.pdf", size: 100)
        try await interruptedRun(trashing: file)
        let item = try #require(try history().first?.items.first)
        guard case .restorable(let trashed)? = item.restorability else {
            Issue.record("The interrupted item is not restorable")
            return
        }
        // The user empties the Trash, and another file takes the name.
        try FileManager.default.removeItem(at: trashed.trashedURL)
        _ = try root.file(".Trash/" + trashed.trashedURL.lastPathComponent, size: 100)
        let report = await (try restoreExecutor()).run([RestoreRequest(item: trashed)])
        #expect(report.outcomes.map(\.result) == [.skipped(.otherItem)])
        #expect(try history().first?.items.first?.restorability == nil)
    }

    @Test func anInterruptedItemThatNeverMovedStaysInterruptedHIS001() async throws {
        let file = try root.file("Documents/report.pdf", size: 100)
        let failing = FakeTrash(folder: root.trashFolder) { _ in throw CocoaError(.fileWriteUnknown) }
        try await interruptedRun(trashing: file, trash: failing)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try history().first?.items.first?.restorability == nil)
        // Without a Trash folder to look in, nothing is claimed either.
        #expect(try HistoryLog.read(folder: root.historyFolder).runs().first?.items.first?.restorability == nil)
    }
}
