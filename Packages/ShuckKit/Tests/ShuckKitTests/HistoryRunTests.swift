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
        #expect(history.operations == [.trash])
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
        #expect(runs.map(\.operations) == [[.trash], [.restore]])
        #expect(runs[0].items.map(\.restorability) == [.restored])
        // A restore names where the item went and where it came from (D-52); it is not itself restorable.
        #expect(runs[1].items.map(\.path) == [clip])
        #expect(runs[1].items.map(\.trashedPath) == [inTrash])
        #expect(runs[1].items.map(\.restorability) == [nil])
    }

    /// What the run logged before it trashed the property list at `path`.
    struct AgentCase: Sendable, CustomTestStringConvertible {
        var testDescription: String
        var detail = "bootout gui/501/com.example.job: exit 0"
        var status = HistoryRecord.Status.ok
        var path = "Library/LaunchAgents/job.plist"
        /// A trash of something else between the unload and the property list's trash.
        var otherInBetween = false
        var withHome = true
        var expected: String?
    }

    /// APP-011, HIS-005: a trashed LaunchAgent property list carries the job label the same run unloaded just before,
    /// only when the `bootout` ran and the file is directly inside `~/Library/LaunchAgents`.
    @Test(arguments: [
        AgentCase(testDescription: "unloaded just before", expected: "com.example.job"),
        AgentCase(testDescription: "not loaded at the uninstall", detail: "not loaded: gui/501/com.example.job"),
        AgentCase(testDescription: "bootout failed", status: .failed),
        AgentCase(testDescription: "another item in between", otherInBetween: true),
        AgentCase(testDescription: "outside LaunchAgents", path: "Documents/job.plist"),
        AgentCase(testDescription: "in a folder inside LaunchAgents", path: "Library/LaunchAgents/sub/job.plist"),
        AgentCase(testDescription: "without a home folder", withHome: false),
    ])
    func aTrashedAgentPropertyListIsPairedWithTheJobUnloadedBeforeItAPP011HIS005(_ test: AgentCase) async throws {
        let run = UUID()
        let inTrash = try root.file(".Trash/job.plist", size: 10).path
        let other = try root.file(".Trash/other.txt", size: 10).path
        let unload = HistoryRecord.result(
            run: run, tool: .applications, operation: .launchctl, path: "com.example.job", tier: .yourData,
            status: test.status, detail: test.detail, timestamp: timestamp)
        let records =
            [unload] + (test.otherInBetween ? trash("/Applications/Other.app", run: run, to: other) : [])
            + trash(try root.url(test.path).path, run: run, to: inTrash)
        let log = try HistoryLog(folder: folder)
        for record in records { try await log.append(record) }

        let runs = try HistoryLog.read(folder: folder).runs(home: test.withHome ? root.url : nil)

        let items = try #require(runs.first).items.compactMap(\.restorability).compactMap { restorability in
            if case .restorable(let item) = restorability, item.trashedURL.path == inTrash { item } else { nil }
        }
        #expect(items.map(\.unloadedAgentLabel) == [test.expected])
    }

    @Test func aResultWithoutAnIntentIsStillListedAndEachItemKeepsItsOperationHIS002() async throws {
        #expect(try HistoryLog.read(folder: folder).runs().isEmpty)
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

    /// HIS-002, SAF-006: a plan may mix methods (D-89), so each item keeps its own operation, and the run lists each
    /// operation once, in the order its items first used it.
    @Test func eachItemOfAMixedRunKeepsItsOperationHIS002SAF006() async throws {
        let run = UUID()
        let records = [(HistoryRecord.Operation.delete, "/a"), (.tool, "npm"), (.delete, "/b")].map { operation, path in
            HistoryRecord.result(
                run: run, tool: .developerJunk, operation: operation, path: path, tier: .rebuildable, status: .ok,
                bytes: 10, timestamp: timestamp)
        }

        let runs = try await runs(records)
        #expect(runs.first?.items.map(\.operation) == [.delete, .tool, .delete])
        #expect(runs.first?.operations == [.delete, .tool])
    }
}
