import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Which logged operations Restore can undo (HIS-003, HIS-004).
struct RestorabilityTests {
    let root: FixtureRoot
    let folder: URL
    let run = UUID()
    /// A whole second, so records compare equal after the round trip through milliseconds.
    let timestamp = Date(timeIntervalSince1970: 1_793_577_600)

    init() throws {
        root = try FixtureRoot()
        folder = HistoryLog.folder(home: root.url)
    }

    private func trashed(_ original: String, to trashed: URL, status: HistoryRecord.Status = .ok) throws
        -> HistoryRecord
    {
        .result(
            run: run, tool: .largeFiles, operation: .trash, path: try root.url(original).path, tier: .yourData,
            status: status, trashedPath: trashed.path, bytes: 100, timestamp: timestamp)
    }

    private func entries(_ records: [HistoryRecord]) async throws -> [HistoryEntry] {
        let log = try HistoryLog(folder: folder)
        for record in records { try await log.append(record) }
        return try HistoryLog.read(folder: folder).entries()
    }

    @Test func anItemStillInTheTrashIsRestorableHIS003() async throws {
        let inTrash = try root.file(".Trash/clip.mov", size: 100)
        let record = try trashed("Movies/clip.mov", to: inTrash)

        let entries = try await entries([
            .intent(run: run, tool: .largeFiles, operation: .trash, path: record.path, tier: .yourData), record,
        ])

        let item = TrashedItem(
            run: run, tool: .largeFiles, tier: .yourData, originalURL: try root.url("Movies/clip.mov"),
            trashedURL: inTrash, bytes: 100)
        #expect(entries == [HistoryEntry(record: record, restorability: .restorable(item))])
        #expect(!item.originalIsTaken)
        try root.file("Movies/clip.mov")
        #expect(item.originalIsTaken)
    }

    @Test func anItemNoLongerInTheTrashIsNotRestorableHIS004() async throws {
        let entries = try await entries([try trashed("Movies/clip.mov", to: try root.url(".Trash/clip.mov"))])
        #expect(entries.map(\.restorability) == [.trashEmptied])
    }

    @Test func aTrashShuckMayNotReadIsReportedAsNotAccessibleSAF012() async throws {
        try root.folder(".Trash", permissions: 0o000)
        let entries = try await entries([try trashed("Movies/clip.mov", to: try root.url(".Trash/clip.mov"))])
        #expect(entries.map(\.restorability) == [.notAccessible])
    }

    @Test func deletionsToolRunsAndLaunchctlChangesAreNotRestorableHIS004() async throws {
        let entries = try await entries([
            .result(run: run, tool: .cachesAndLogs, operation: .delete, path: "/a", tier: .rebuildable, status: .ok),
            .result(run: run, tool: .developerJunk, operation: .tool, path: "brew", tier: .rebuildable, status: .ok),
            .result(run: run, tool: .startupItems, operation: .launchctl, path: "com.a", tier: .yourData, status: .ok),
            .result(run: run, tool: .largeFiles, operation: .trash, path: "/b", tier: .yourData, status: .ok),
        ])
        #expect(entries.map(\.restorability) == [.permanent, .permanent, .reversedByOppositeAction, .unknownLocation])
    }

    @Test func skippedAndFailedOperationsChangedNothingAndAreLeftOut() async throws {
        let inTrash = try root.file(".Trash/clip.mov", size: 100)
        let entries = try await entries([
            try trashed("Movies/clip.mov", to: inTrash, status: .skipped),
            try trashed("Movies/clip.mov", to: inTrash, status: .failed),
        ])
        #expect(entries.isEmpty)
    }

    @Test func aRestoredItemIsMarkedRestoredAndAReusedTrashNameIsRestorableAgain() async throws {
        let inTrash = try root.file(".Trash/report.pdf", size: 100)
        let first = try trashed("Downloads/report.pdf", to: inTrash)
        let restore = HistoryRecord.result(
            run: UUID(), tool: .history, operation: .restore, path: first.path, tier: .yourData, status: .ok,
            trashedPath: inTrash.path)
        let failedRestore = HistoryRecord.result(
            run: UUID(), tool: .history, operation: .restore, path: first.path, tier: .yourData, status: .failed,
            trashedPath: inTrash.path)
        // Later, another report.pdf goes to the Trash under the same name.
        let second = try trashed("Documents/report.pdf", to: inTrash)

        let entries = try await entries([first, failedRestore, restore, second])

        #expect(entries.map(\.record) == [first, second])
        #expect(entries[0].restorability == .restored)
        guard case .restorable(let item) = entries[1].restorability else {
            Issue.record("The second item is not restorable: \(entries[1].restorability)")
            return
        }
        #expect(item.originalURL == (try root.url("Documents/report.pdf")))
    }
}
