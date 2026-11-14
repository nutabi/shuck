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

    private let bundleID = "com.example.fixture"

    /// The uninstall plan the app builds for the fixture app and `leftovers`, so these scenarios run the plan a user
    /// would review (APP-005, APP-007, APP-011). `removability` is what the scan saw: `.removable` even when the run
    /// then finds a folder it cannot change, as it would for a missing App Management permission.
    private func uninstall(_ bundle: URL, leftovers: [URL]) throws -> Plan {
        let app = InstalledApp(
            url: bundle, name: "Fixture", bundleID: bundleID, snapshot: try #require(ItemSnapshot.read(bundle)),
            modified: try #require(ModificationDate.read(at: bundle)))
        let items = try leftovers.map { url in
            ScanItem(
                url: url, snapshot: try #require(ItemSnapshot.read(url)), tier: .yourData, method: .trash,
                reason: "Fixture", source: .applications, modified: ModificationDate.read(at: url))
        }
        return try Applications(appFolders: [root.url("Applications")]).uninstallPlan(
            for: app, leftovers: items, pathGuard: pathGuard)
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

    // MARK: - APP-011

    @Test func aFailedBootoutSkipsTheAgentsPlistAndLogsWhyAPP011SAF011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0, bootoutStatus: 5))
        let bundle = try root.app("Applications/Fixture.app", bundleID: bundleID)
        let plist = try agent()
        let report = try await run(uninstall(bundle, leftovers: [plist]))

        // The bundle is trashed first; then the agent's bootout fails, which leaves its plist alone.
        #expect(report.outcomes.map(\.item.method) == [.trash, .launchctl, .trash])
        guard case .failed(let error) = report.outcomes[1].result else {
            Issue.record("Expected the bootout to fail")
            return
        }
        #expect(error.domain == "ShuckToolExit" && error.code == 5)
        #expect(
            root.launchctlCalls == calls(), "calls: \(root.launchctlCalls), results: \(report.outcomes.map(\.result))")
        #expect(report.outcomes[0].result.isDone)
        #expect(report.outcomes[2].result == .skipped(.dependencyNotDone(label)))
        #expect(exists(plist) && !exists(bundle))
        // Each item has an intent and a result record; the skip names what it needed.
        let records = try records()
        #expect(records.map(\.operation) == [.trash, .trash, .launchctl, .launchctl, .trash, .trash])
        #expect(records.map(\.phase) == [.intent, .result, .intent, .result, .intent, .result])
        #expect(records.compactMap(\.status) == [.ok, .failed, .skipped])
        #expect(records[3].detail?.hasPrefix("bootout \(target): ") == true)
        #expect(records.last?.detail == "dependencyNotDone: \(label)")
        #expect(records.last?.detail.flatMap(SkipCode.init(detail:)) == .dependencyNotDone)
    }

    @Test func anAgentThatIsNotLoadedIsStillTrashedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let bundle = try root.app("Applications/Fixture.app", bundleID: bundleID)
        let plist = try agent()
        let report = try await run(uninstall(bundle, leftovers: [plist]))

        #expect(report.outcomes.map(\.result.isDone) == [true, true, true])
        #expect(!exists(plist))
        // Nothing is booted out, and the log says why.
        #expect(root.launchctlCalls == ["print \(target)"])
        let records = try records()
        #expect(records[3].detail?.hasPrefix("not loaded") == true && records[3].status == .ok)
    }

    @Test func aLoadedAgentIsBootedOutBeforeItsPlistIsTrashedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let bundle = try root.app("Applications/Fixture.app", bundleID: bundleID)
        let plist = try agent()
        let report = try await run(uninstall(bundle, leftovers: [plist]))

        #expect(report.outcomes.map(\.result.isDone) == [true, true, true])
        #expect(!exists(plist) && !exists(bundle))
        #expect(
            root.launchctlCalls == calls(), "calls: \(root.launchctlCalls), results: \(report.outcomes.map(\.result))")
        #expect(try records().compactMap(\.status) == [.ok, .ok, .ok])
    }

    // MARK: - APP-005

    @Test func aBundleThatFailsToMoveLeavesItsLeftoversAndAgentsAloneAPP005() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let bundle = try root.app("Applications/Fixture.app", bundleID: bundleID)
        let cache = try root.folder("Library/Caches/com.example.fixture")
        let prefs = try root.file("Library/Preferences/com.example.fixture.plist", size: 10)
        let plist = try agent()
        let report = try await run(uninstall(bundle, leftovers: [cache, prefs, plist])) { url in
            if url.lastPathComponent == "Fixture.app" { throw ActionError(domain: "Test", code: 1, message: "busy") }
        }

        guard case .failed = report.outcomes[0].result else {
            Issue.record("Expected the bundle to fail")
            return
        }
        // Every leftover is skipped, and the agent is never unloaded for an app that stays.
        // The plist's Trash item needed its bootout, which was itself skipped, so it names the agent's label.
        let needed = report.outcomes.dropFirst().map(\.result)
        #expect(
            needed == Array(repeating: .skipped(.dependencyNotDone(bundle.path)), count: 3) + [
                .skipped(.dependencyNotDone(label))
            ])
        #expect(exists(bundle) && exists(cache) && exists(prefs) && exists(plist))
        #expect(root.launchctlCalls.isEmpty)
        #expect(
            try records().filter { $0.phase == .result }.compactMap(\.status)
                == [.failed, .skipped, .skipped, .skipped, .skipped])
    }

    /// The bundle's folder cannot be changed, which the scan could not see, as with a missing App Management
    /// permission: macOS refuses the move, so the bundle is skipped with its reason and the run goes on (S78, R-16).
    @Test func aBundleMacOSWillNotMoveIsSkippedAndItsLeftoversWaitAPP005() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let bundle = try root.app("Applications/Locked/Fixture.app", bundleID: bundleID)
        let folder = bundle.deletingLastPathComponent()
        let cache = try root.folder("Library/Caches/com.example.fixture")
        let plist = try agent()
        let plan = try uninstall(bundle, leftovers: [cache, plist])
        try #require(chmod(folder.path, 0o555) == 0)
        // Restore the mode whatever happens, so the fixture root can be cleaned up.
        defer { chmod(folder.path, 0o755) }

        let executor = try PlanExecutor(
            pathGuard: pathGuard, log: HistoryLog(folder: root.historyFolder),
            trash: FolderTrash(folder: root.trashFolder), runningApps: StubRunningApps(),
            toolRunner: ToolRunner(executableRoots: [root.url]))
        let report = await Task { await executor.run(plan) }.value

        guard case .skipped(.notPermitted(let error)) = report.outcomes[0].result else {
            Issue.record("Expected a skip, got \(report.outcomes[0].result)")
            return
        }
        #expect(error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError)
        let needed = report.outcomes.dropFirst().map(\.result)
        #expect(
            needed == Array(repeating: .skipped(.dependencyNotDone(bundle.path)), count: 2) + [
                .skipped(.dependencyNotDone(label))
            ])
        #expect(exists(bundle) && exists(cache) && exists(plist))
        #expect(root.launchctlCalls.isEmpty)
        // The log keeps the error, so History can say why (SAF-011).
        let first = try #require(try records().first { $0.phase == .result })
        #expect(first.status == .skipped && first.detail == "notPermitted: \(error.logged)")
    }

    /// Another app's container is refused with the same error. Only that item is skipped, and the run goes on.
    @Test func aContainerMacOSWillNotMoveIsSkippedAndTheRestIsRemovedAPP005() async throws {
        let bundle = try root.app("Applications/Fixture.app", bundleID: bundleID)
        let cache = try root.folder("Library/Caches/com.example.fixture")
        let container = try root.folder("Library/Containers/com.example.fixture")
        let prefs = try root.file("Library/Preferences/com.example.fixture.plist", size: 10)
        let report = try await run(uninstall(bundle, leftovers: [cache, container, prefs])) { url in
            if url.lastPathComponent == "com.example.fixture"
                && url.deletingLastPathComponent().lastPathComponent == "Containers"
            {
                throw CocoaError(.fileWriteNoPermission)
            }
        }

        let results = report.outcomes.map(\.result)
        guard case .skipped(.notPermitted) = results[2] else {
            Issue.record("Expected a skip, got \(results[2])")
            return
        }
        #expect([0, 1, 3].allSatisfy { results[$0].isDone })
        #expect(!exists(bundle) && !exists(cache) && !exists(prefs) && exists(container))
        #expect(try records().filter { $0.phase == .result }.compactMap(\.status) == [.ok, .ok, .skipped, .ok])
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
