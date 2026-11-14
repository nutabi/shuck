import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// An item that depends on an earlier item of its run is skipped, with its reason, if that item was not done: a failed
/// `bootout` leaves the agent's property list alone (APP-011), and a bundle that does not move leaves its leftovers
/// (APP-005). A dependency only ever turns an action into that skip (SAF-005, SAF-006, SAF-011, D-198).
struct ItemDependencyTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private let label = "com.example.helper.job"
    private var target: String { "gui/\(getuid())/\(label)" }

    /// What a loaded agent's `bootout` calls: the check, then the `bootout`.
    private func calls() -> [String] { ["print \(target)", "bootout \(target)"] }

    private func agent(label: String = "com.example.helper.job") throws -> URL {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>Label</key><string>\(label)</string></dict></plist>
            """
        return try root.file("Library/LaunchAgents/\(label).plist", text: text)
    }

    private func plan(_ items: [PlannedItem]) throws -> Plan {
        try Plan(tool: .applications, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
    }

    private func run(_ plan: Plan, beforeMove: @escaping @Sendable (URL) throws -> Void = { _ in }) async throws
        -> RunReport
    {
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard, beforeMove: beforeMove)
        return await Task { await executor.run(plan) }.value
    }

    private func records() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The agent's two items: its `bootout`, then its property list's move to the Trash, which depends on it.
    private func bootoutThenTrash(_ plist: URL) throws -> [PlannedItem] {
        let bootout = try root.planned(plist, tier: .yourData, method: .launchctl)
        let trash = try root.planned(
            plist, tier: .yourData, method: .trash, dependency: ItemDependency(bootout))
        return [bootout, trash]
    }

    // MARK: - APP-011

    @Test func aFailedBootoutSkipsTheAgentsPlistAndLogsWhyAPP011SAF011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0, bootoutStatus: 5))
        let plist = try agent()
        let report = try await run(plan(bootoutThenTrash(plist)))

        guard case .failed(let error) = report.outcomes[0].result else {
            Issue.record("Expected the bootout to fail")
            return
        }
        #expect(error.domain == "ShuckToolExit" && error.code == 5)
        #expect(
            root.launchctlCalls == calls(), "calls: \(root.launchctlCalls), results: \(report.outcomes.map(\.result))")
        #expect(report.outcomes[1].result == .skipped(.dependencyNotDone(label)))
        #expect(exists(plist))
        // Both items have an intent and a result record; the skip names what it needed.
        let records = try records()
        #expect(records.map(\.operation) == [.launchctl, .launchctl, .trash, .trash])
        #expect(records.map(\.phase) == [.intent, .result, .intent, .result])
        #expect(records.compactMap(\.status) == [.failed, .skipped])
        #expect(records[1].detail?.hasPrefix("bootout \(target): ") == true)
        #expect(records.last?.detail == "dependencyNotDone: \(label)")
        #expect(records.last?.detail.flatMap(SkipCode.init(detail:)) == .dependencyNotDone)
    }

    @Test func anAgentThatIsNotLoadedIsStillTrashedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let plist = try agent()
        let report = try await run(plan(bootoutThenTrash(plist)))

        #expect(report.outcomes.map(\.result.isDone) == [true, true])
        #expect(!exists(plist))
        // Nothing is booted out, and the log says why.
        #expect(root.launchctlCalls == ["print \(target)"])
        let records = try records()
        #expect(records[1].detail?.hasPrefix("not loaded") == true && records[1].status == .ok)
    }

    @Test func aBootoutThatWorksLetsThePlistBeTrashedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let plist = try agent()
        let report = try await run(plan(bootoutThenTrash(plist)))

        #expect(report.outcomes.map(\.result.isDone) == [true, true])
        #expect(!exists(plist))
        #expect(
            root.launchctlCalls == ["print \(target)", "bootout \(target)"],
            "calls: \(root.launchctlCalls), results: \(report.outcomes.map(\.result))")
        #expect(try records().compactMap(\.status) == [.ok, .ok])
    }

    // MARK: - APP-005

    @Test func aBundleThatFailsToMoveLeavesItsLeftoversAloneAPP005() async throws {
        let bundle = try root.folder("Applications/Fixture.app")
        let cache = try root.folder("Library/Caches/com.example.fixture")
        let prefs = try root.file("Library/Preferences/com.example.fixture.plist", size: 10)
        let other = try root.file("Library/Application Support/Unrelated/data", size: 10)
        let bundleItem = try root.planned(bundle, tier: .yourData, method: .trash)
        let dependency = ItemDependency(bundleItem)
        let plan = try plan([
            bundleItem,
            root.planned(cache, tier: .yourData, method: .trash, dependency: dependency),
            root.planned(prefs, tier: .yourData, method: .trash, dependency: dependency),
            root.planned(other, tier: .yourData, method: .trash),
        ])
        let report = try await run(plan) { url in
            if url.lastPathComponent == "Fixture.app" { throw ActionError(domain: "Test", code: 1, message: "busy") }
        }

        guard case .failed = report.outcomes[0].result else {
            Issue.record("Expected the bundle to fail")
            return
        }
        #expect(report.outcomes[1].result == .skipped(.dependencyNotDone(bundle.path)))
        #expect(report.outcomes[2].result == .skipped(.dependencyNotDone(bundle.path)))
        #expect(report.outcomes[3].result.isDone)
        #expect(exists(bundle) && exists(cache) && exists(prefs) && !exists(other))
        #expect(report.outcomes.count == 4)
        #expect(
            try records().filter { $0.phase == .result }.compactMap(\.status) == [.failed, .skipped, .skipped, .ok])
    }

    @Test func aBundleThatMovesLetsItsLeftoversMoveAPP005() async throws {
        let bundle = try root.folder("Applications/Fixture.app")
        let cache = try root.folder("Library/Caches/com.example.fixture")
        let bundleItem = try root.planned(bundle, tier: .yourData, method: .trash)
        let report = try await run(
            plan([
                bundleItem,
                root.planned(cache, tier: .yourData, method: .trash, dependency: ItemDependency(bundleItem)),
            ]))

        #expect(report.outcomes.map(\.result.isDone) == [true, true])
        #expect(!exists(bundle) && !exists(cache))
    }

    @Test func anItemDependingOnASkippedItemIsSkippedToo() async throws {
        let first = try root.file("Downloads/first.bin", size: 10)
        let second = try root.file("Downloads/second.bin", size: 10)
        let third = try root.file("Downloads/third.bin", size: 10)
        let firstItem = try root.planned(first, tier: .yourData, method: .trash)
        let secondItem = try root.planned(
            second, tier: .yourData, method: .trash, dependency: ItemDependency(firstItem))
        let thirdItem = try root.planned(
            third, tier: .yourData, method: .trash, dependency: ItemDependency(secondItem))
        // The first item changed since the scan, so it is skipped, and the chain after it follows.
        try Data(count: 5000).write(to: first)
        let report = try await run(plan([firstItem, secondItem, thirdItem]))

        #expect(report.outcomes[1].result == .skipped(.dependencyNotDone(first.path)))
        #expect(report.outcomes[2].result == .skipped(.dependencyNotDone(second.path)))
        #expect(exists(first) && exists(second) && exists(third))
    }

    @Test func stoppingTheRunLeavesDependentsUntouchedWithAnOutcomeEachSAF011() async throws {
        let bundle = try root.folder("Applications/Fixture.app")
        let cache = try root.folder("Library/Caches/com.example.fixture")
        let bundleItem = try root.planned(bundle, tier: .yourData, method: .trash)
        let plan = try plan([
            bundleItem,
            root.planned(cache, tier: .yourData, method: .trash, dependency: ItemDependency(bundleItem)),
        ])
        // The stop arrives as the bundle is about to move, so the bundle is done and the run then sees the stop.
        let report = try await run(plan) { _ in withUnsafeCurrentTask { $0?.cancel() } }

        #expect(report.outcomes.count == 2)
        #expect(report.outcomes[1].result == .skipped(.cancelled))
        #expect(exists(cache))
    }

    // MARK: - The invariant

    @Test func anItemWithoutADependencyActsAsBeforeSAF011() async throws {
        let first = try root.file("Downloads/first.bin", size: 10)
        let second = try root.file("Downloads/second.bin", size: 10)
        let report = try await run(
            plan([
                root.planned(first, tier: .yourData, method: .trash),
                root.planned(second, tier: .yourData, method: .trash),
            ]))
        #expect(report.outcomes.map(\.result.isDone) == [true, true])
        #expect(!exists(first) && !exists(second))
    }
}
