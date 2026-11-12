import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// What an executor writes, History reads back: the codes and errors in the log's `detail` are the ones the app puts
/// into words (SAF-011, HIS-002, D-88; a test M2-T01 left, D-93).
struct HistoryReadBackTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test func aRunsSkipsAndFailuresReadBackAsTheCodesAndErrorsItReportedSAF011() async throws {
        let done = try root.file("Downloads/done.zip", size: 10_000)
        let gone = try root.file("Downloads/gone.zip", size: 10_000)
        let grown = try root.file("Downloads/grown.log", size: 10_000)
        let locked = try root.file("Downloads/locked.dat", size: 10_000)
        let plan = try Plan(
            tool: .largeFiles, allowedRoots: [root.url],
            items: [done, gone, grown, locked].map { try root.planned($0, tier: .yourData, method: .trash) },
            pathGuard: pathGuard)
        try FileManager.default.removeItem(at: gone)
        try Data(count: 1_000_000).write(to: grown)
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard) { url in
            if url.lastPathComponent == "locked.dat" { throw POSIXError(.EACCES) }
        }

        // The run gets a task of its own, as in the other executor tests (TD-17).
        let report = await Task { await executor.run(plan) }.value

        let history = try #require(try HistoryLog.read(folder: root.historyFolder).runs().first)
        #expect(history.id == plan.run)
        #expect(history.items.map(\.path) == plan.items.map(\.target.description))
        #expect(report.outcomes.count == history.items.count)
        var kinds: [String] = []
        for (outcome, item) in zip(report.outcomes, history.items) {
            switch (outcome.result, item.outcome) {
            case (.done, .succeeded):
                kinds.append("succeeded")
            case (.skipped(let reason), .skipped(let detail?)):
                kinds.append("skipped")
                // The app words a skip by this code; an unknown one would show as logged text.
                #expect(SkipCode(detail: detail) == reason.code, "\(detail)")
            case (.failed(let error), .failed(let detail?)):
                kinds.append("failed")
                #expect(ActionError(logged: detail) == error)
            default:
                Issue.record("\(outcome.result) was read back as \(item.outcome)")
            }
        }
        #expect(kinds == ["succeeded", "skipped", "skipped", "failed"])
    }
}
