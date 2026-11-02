import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The runs the History view lists, built from the history log (HIS-002).
struct HistoryRunTests {
    let root: FixtureRoot
    let folder: URL
    /// A whole second, so records compare equal after the round trip through milliseconds.
    let timestamp = Date(timeIntervalSince1970: 1_793_577_600)

    init() throws {
        root = try FixtureRoot()
        folder = root.historyFolder
    }

    private func runs(_ records: [HistoryRecord]) async throws -> [HistoryRun] {
        let log = try HistoryLog(folder: folder)
        for record in records { try await log.append(record) }
        return try HistoryLog.read(folder: folder).runs()
    }

    /// The intent and result records of one trash, as `PlanExecutor` writes them.
    private func trash(
        _ path: String, run: UUID, status: HistoryRecord.Status = .ok, to trashedPath: String? = nil,
        detail: String? = nil
    ) -> [HistoryRecord] {
        [
            .intent(
                run: run, tool: .largeFiles, operation: .trash, path: path, tier: .yourData, bytes: 100,
                timestamp: timestamp),
            .result(
                run: run, tool: .largeFiles, operation: .trash, path: path, tier: .yourData, status: status,
                trashedPath: trashedPath, bytes: 100, detail: detail, timestamp: timestamp),
        ]
    }

    @Test func aRunListsEveryItemItLoggedWithItsOutcomeHIS002() async throws {
        let run = UUID()
        let inTrash = try root.file(".Trash/clip.mov", size: 100)
        let clip = try root.url("Movies/clip.mov").path
        let gone = try root.url("Movies/gone.mov").path
        let report = try root.url("Documents/report.pdf").path
        let emptied = try root.url(".Trash/report.pdf").path

        let runs = try await runs(
            trash(clip, run: run, to: inTrash.path) + trash(gone, run: run, status: .skipped, detail: "missing")
                + trash(report, run: run, to: emptied))

        #expect(runs.map(\.id) == [run])
        let history = try #require(runs.first)
        #expect(history.tool == .largeFiles)
        #expect(history.operation == .trash)
        #expect(history.started == timestamp)
        #expect(history.items.map(\.path) == [clip, gone, report])
        #expect(history.items.map(\.outcome) == [.succeeded, .skipped("missing"), .succeeded])
        #expect(history.succeededCount == 2)
        #expect(history.succeededBytes == 200)
        // A skipped item changed nothing, so there is nothing to restore (HIS-004).
        #expect(history.items[1].restorability == nil)
        #expect(history.items[2].restorability == .trashEmptied)
        guard case .restorable(let item) = history.items[0].restorability else {
            Issue.record("The clip is not restorable: \(String(describing: history.items[0].restorability))")
            return
        }
        #expect(item.trashedURL == inTrash)
    }

    @Test func anIntentWithoutAResultIsInterruptedHIS001() async throws {
        let run = UUID()
        let clip = try root.url("Movies/clip.mov").path
        let report = try root.url("Documents/report.pdf").path

        // The app stopped after the second intent record.
        let runs = try await runs(
            trash(clip, run: run, status: .failed, detail: "denied") + [trash(report, run: run)[0]])

        #expect(runs.first?.items.map(\.outcome) == [.failed("denied"), .interrupted])
        #expect(runs.first?.items.map(\.restorability) == [nil, nil])
        #expect(runs.first?.succeededCount == 0)
    }

    @Test func aRestoreIsARunOfItsOwnAndMarksTheItemItPutBackHIS002() async throws {
        let trashRun = UUID()
        let restoreRun = UUID()
        let inTrash = try root.url(".Trash/clip.mov").path
        let clip = try root.url("Movies/clip.mov").path

        let runs = try await runs(
            trash(clip, run: trashRun, to: inTrash) + [
                .intent(
                    run: restoreRun, tool: .history, operation: .restore, path: clip, tier: .yourData,
                    trashedPath: inTrash, bytes: 100, timestamp: timestamp),
                .result(
                    run: restoreRun, tool: .history, operation: .restore, path: clip, tier: .yourData, status: .ok,
                    trashedPath: inTrash, bytes: 100, timestamp: timestamp),
            ])

        #expect(runs.map(\.id) == [trashRun, restoreRun])
        #expect(runs.map(\.tool) == [.largeFiles, .history])
        #expect(runs.map(\.operation) == [.trash, .restore])
        #expect(runs[0].items.map(\.restorability) == [.restored])
        // A restore names where the item went and where it came from (D-52); it is not itself restorable.
        #expect(runs[1].items.map(\.path) == [clip])
        #expect(runs[1].items.map(\.trashedPath) == [inTrash])
        #expect(runs[1].items.map(\.restorability) == [nil])
    }

    @Test func aResultWithoutAnIntentIsStillListed() async throws {
        let run = UUID()
        let runs = try await runs([
            .result(
                run: run, tool: .cachesAndLogs, operation: .delete, path: "/a", tier: .rebuildable, status: .ok,
                bytes: 50, timestamp: timestamp)
        ])

        #expect(runs.first?.items.map(\.outcome) == [.succeeded])
        #expect(runs.first?.items.map(\.restorability) == [.permanent])
        #expect(runs.first?.succeededBytes == 50)
    }

    @Test func anEmptyLogHasNoRuns() throws {
        #expect(try HistoryLog.read(folder: folder).runs().isEmpty)
    }
}
