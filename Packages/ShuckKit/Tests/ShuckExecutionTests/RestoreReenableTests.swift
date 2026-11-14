import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Restore loads a restored LaunchAgent again only when the user confirmed it (APP-011, HIS-005), through a fake
/// `launchctl` inside the fixture root (SAF-016). The real one is never reachable (D-82).
struct RestoreReenableTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let trash: FakeTrash
    let label = "com.example.helper.job"
    let target: String

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        trash = FakeTrash(folder: root.trashFolder)
        target = "gui/\(getuid())/com.example.helper.job"
    }

    private func plist(label: String = "com.example.helper.job") throws -> URL {
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>Label</key><string>\(label)</string></dict></plist>
            """
        return try root.file("Library/LaunchAgents/com.example.helper.plist", text: text)
    }

    /// Trashes `url` with the Trash executor and returns it as the history log now lists it.
    private func trashed(_ url: URL) async throws -> TrashedItem {
        let item = try root.planned(url, tier: .yourData, method: .trash)
        let plan = try Plan(tool: .applications, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
        _ = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)
        let entries = try HistoryLog.read(folder: root.historyFolder).entries()
        return try #require(
            entries.compactMap { entry -> TrashedItem? in
                if case .restorable(let item) = entry.restorability { item } else { nil }
            }.first)
    }

    private func restore(_ requests: [RestoreRequest]) async throws -> RestoreReport {
        let executor = RestoreExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: root.historyFolder), trash: trash,
            toolRunner: ToolRunner(executableRoots: [root.url]))
        return await executor.run(requests)
    }

    private func launchctlRecords() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records.filter { $0.operation == .launchctl }
    }

    /// The whole journey of an uninstall: scan, review, run, History, Restore with the user's confirmation. Everything
    /// stays in the fixture root, with a fake `launchctl` (SAF-016).
    @Test func anUninstallIsReadInHistoryAndRestoredWithItsAgentAPP007APP011HIS005SAF006() async throws {
        let bundleID = "com.example.fixture"
        let agentTarget = "gui/\(getuid())/\(bundleID)"
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let bundle = try root.app("Applications/Fixture.app", bundleID: bundleID, name: "Fixture", size: 4096)
        let cache = try root.file("Library/Caches/\(bundleID)/data.bin", size: 2048).deletingLastPathComponent()
        let preferences = try root.file("Library/Preferences/\(bundleID).plist", text: "prefs")
        let agent = try root.file(
            "Library/LaunchAgents/\(bundleID).plist",
            text: "<plist version=\"1.0\"><dict><key>Label</key><string>\(bundleID)</string></dict></plist>")
        let originals = [bundle, cache, preferences, agent]

        // Scan the app and its leftovers, and keep what starts selected, as the page offers it (APP-002, APP-007).
        let applications = Applications(
            appFolders: [try root.url("Applications")], isSystemProtected: { _ in false }, lastUsedDate: { _ in nil },
            appGroups: { _ in [] }, owner: { _ in getuid() }, systemLibrary: try root.url("System Library"))
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps())
        var found: [InstalledApp] = []
        for await case .app(let app) in applications.scan(context) { found.append(app) }
        let app = try #require(found.first)
        #expect(app.bundleID == bundleID)
        var leftovers: [ScanItem] = []
        let byName = applications.bundleIDsByName(home: root.url)
        for await case .item(let item) in applications.leftovers(of: app, among: byName, context) {
            if item.selection == .selected { leftovers.append(item) }
        }
        #expect(Set(leftovers.compactMap(\.url?.lastPathComponent)) == [bundleID, "\(bundleID).plist"])
        let plan = try applications.uninstallPlan(for: app, leftovers: leftovers, pathGuard: pathGuard)

        // Run it: the agent is unloaded before its property list moves (APP-011).
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)
        #expect(report.outcomes.allSatisfy { $0.result.isDone }, "\(report.outcomes.map(\.result))")
        #expect(root.launchctlCalls == ["print \(agentTarget)", "bootout \(agentTarget)"])
        #expect(originals.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })

        // History shows one run, with each trashed item restorable and the unload logged by its job label (HIS-002).
        let runs = try HistoryLog.read(folder: root.historyFolder).runs(trashFolder: root.trashFolder)
        let uninstall = try #require(runs.first)
        #expect(runs.count == 1 && uninstall.tool == .applications && uninstall.id == report.run)
        #expect(uninstall.items.allSatisfy { $0.outcome == .succeeded })
        let unloaded = uninstall.items.filter { $0.operation == .launchctl }
        #expect(unloaded.map(\.path) == [bundleID])
        let trashed = uninstall.items.compactMap { item -> TrashedItem? in
            if case .restorable(let found)? = item.restorability { found } else { nil }
        }
        #expect(Set(trashed.map(\.originalURL.path)) == Set(originals.map(\.path)))

        // Restore everything, loading the agent again only because the user confirmed it (APP-011, HIS-005).
        // The agent is no longer loaded: the fake is replaced inside the root, as the uninstall unloaded the real one.
        try FileManager.default.removeItem(at: root.url("bin/launchctl"))
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let requests = trashed.map { item in
            RestoreRequest(item: item, reenableAgentLabel: item.originalURL == agent ? bundleID : nil)
        }
        let restored = try await restore(requests)
        #expect(restored.outcomes.count == 4 && restored.outcomes.compactMap(\.reenable) == [.done(nil)])
        #expect(restored.outcomes.allSatisfy { $0.result.isDone })
        #expect(originals.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        // `bootstrap` only, never `enable`: the user's own disabled override is left alone (D-199).
        #expect(
            root.launchctlCalls.dropFirst(2) == ["print \(agentTarget)", "bootstrap gui/\(getuid()) \(agent.path)"])

        // The restores and the re-enable are in the log, by the job label (SAF-006, HIS-002).
        let records = try launchctlRecords()
        #expect(records.suffix(2).map(\.path) == [bundleID, bundleID])
        #expect(records.suffix(2).map(\.status) == [nil, .ok])
        #expect(records.last?.detail == "bootstrap \(agentTarget): exit 0")
        let after = try HistoryLog.read(folder: root.historyFolder)
        #expect(after.records.filter { $0.operation == .restore && $0.phase == .result }.count == 4)
    }

    @Test func anAgentThatIsLoadedAlreadyIsNotBootstrappedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let item = try await trashed(try plist())

        let report = try await restore([RestoreRequest(item: item, reenableAgentLabel: label)])

        #expect(report.outcomes.first?.reenable == .done(nil))
        #expect(root.launchctlCalls == ["print \(target)"])
        #expect(try launchctlRecords().last?.detail == "already loaded: \(target)")
    }

    @Test func aFailedBootstrapFailsTheReenableButNotTheRestoreSAF011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus, bootstrapStatus: 5))
        let plist = try plist()
        let item = try await trashed(plist)

        let report = try await restore([RestoreRequest(item: item, reenableAgentLabel: label)])

        let outcome = try #require(report.outcomes.first)
        #expect(outcome.result == .done(plist))
        guard case .failed? = outcome.reenable else {
            Issue.record("expected a failed re-enable, got \(String(describing: outcome.reenable))")
            return
        }
        #expect(FileManager.default.fileExists(atPath: plist.path))
        #expect(try launchctlRecords().last?.status == .failed)
    }

    @Test func aStatusThatSaysNothingAboutLoadingFailsTheReenableSAF011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 1))
        let item = try await trashed(try plist())

        let report = try await restore([RestoreRequest(item: item, reenableAgentLabel: label)])

        guard case .failed? = report.outcomes.first?.reenable else {
            Issue.record("expected a failed re-enable")
            return
        }
        #expect(root.launchctlCalls == ["print \(target)"])
    }

    @Test func aRestoreThatIsSkippedSkipsTheReenableWithoutLaunchctlAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let plist = try plist()
        let item = try await trashed(plist)
        // Something else took the original path before the restore.
        try root.file("Library/LaunchAgents/com.example.helper.plist", text: "other")
        let taken = try await trashedAgain(item)

        let report = try await restore([RestoreRequest(item: taken, ifTaken: .skip, reenableAgentLabel: label)])

        let outcome = try #require(report.outcomes.first)
        #expect(outcome.result == .skipped(.originalTaken))
        #expect(outcome.reenable == .skipped(.dependencyNotDone(plist.path)))
        #expect(root.launchctlCalls.isEmpty)
        #expect(try launchctlRecords().last?.detail == "dependencyNotDone: \(plist.path)")
    }

    /// The item as the history log lists it now, which has its original path taken.
    private func trashedAgain(_ item: TrashedItem) async throws -> TrashedItem {
        let entries = try HistoryLog.read(folder: root.historyFolder).entries()
        return try #require(
            entries.compactMap { entry -> TrashedItem? in
                if case .restorable(let found) = entry.restorability { found } else { nil }
            }.first { $0.trashedURL == item.trashedURL })
    }

    @Test func aKeepBothCopyIsNeverLoadedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let plist = try plist()
        let item = try await trashed(plist)
        try root.file("Library/LaunchAgents/com.example.helper.plist", text: "other")
        let taken = try await trashedAgain(item)

        let report = try await restore([RestoreRequest(item: taken, ifTaken: .keepBoth, reenableAgentLabel: label)])

        let outcome = try #require(report.outcomes.first)
        guard case .done(let copy?) = outcome.result else {
            Issue.record("expected the copy to be restored")
            return
        }
        #expect(copy.lastPathComponent == "com.example.helper (restored).plist")
        guard case .skipped(.notTheUnloadedAgent)? = outcome.reenable else {
            Issue.record("expected a skip, got \(String(describing: outcome.reenable))")
            return
        }
        #expect(root.launchctlCalls.isEmpty)
    }

    @Test func aPropertyListWithAnotherLabelIsNeverLoadedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let item = try await trashed(try plist(label: "com.example.other"))

        let report = try await restore([RestoreRequest(item: item, reenableAgentLabel: label)])

        guard case .done? = report.outcomes.first?.result else {
            Issue.record("expected the restore to be done")
            return
        }
        guard case .skipped(.notTheUnloadedAgent)? = report.outcomes.first?.reenable else {
            Issue.record("expected a skip")
            return
        }
        #expect(root.launchctlCalls.isEmpty)
        #expect(try launchctlRecords().last?.status == .skipped)
    }

    @Test func aPropertyListOutsideLaunchAgentsIsNeverLoadedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let text = "<plist version=\"1.0\"><dict><key>Label</key><string>\(label)</string></dict></plist>"
        let item = try await trashed(try root.file("Documents/agent.plist", text: text))

        let report = try await restore([RestoreRequest(item: item, reenableAgentLabel: label)])

        guard case .skipped(.notTheUnloadedAgent)? = report.outcomes.first?.reenable else {
            Issue.record("expected a skip")
            return
        }
        #expect(root.launchctlCalls.isEmpty)
    }

    @Test func withoutAConfirmationRestoreNeverCallsLaunchctlAPP011HIS005() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let plist = try plist()
        let item = try await trashed(plist)

        // The default request, as the History page's automatic start and Restore All send it.
        let report = try await restore([RestoreRequest(item: item)])

        #expect(report.outcomes.first?.result == .done(plist))
        #expect(report.outcomes.first?.reenable == nil)
        #expect(root.launchctlCalls.isEmpty)
        #expect(try launchctlRecords().isEmpty)
        #expect(RestoreRequest(item: item).reenableAgentLabel == nil)
    }

    @Test func aMissingLaunchctlSkipsTheReenableSAF011() async throws {
        let item = try await trashed(try plist())

        let report = try await restore([RestoreRequest(item: item, reenableAgentLabel: label)])

        guard case .done? = report.outcomes.first?.result else {
            Issue.record("expected the restore to be done")
            return
        }
        guard case .skipped(.toolUnavailable)? = report.outcomes.first?.reenable else {
            Issue.record("expected a skip, got \(String(describing: report.outcomes.first?.reenable))")
            return
        }
    }
}
