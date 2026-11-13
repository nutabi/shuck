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

    @Test func aConfirmedRestoreLoadsTheAgentAgainByItsLabelAPP011HIS005SAF006() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let plist = try plist()
        let item = try await trashed(plist)

        let report = try await restore([RestoreRequest(item: item, reenableAgentLabel: label)])

        let outcome = try #require(report.outcomes.first)
        #expect(outcome.result == .done(plist))
        #expect(outcome.reenable == .done(nil))
        #expect(FileManager.default.fileExists(atPath: plist.path))
        // `bootstrap` only, never `enable`: the user's own disabled override is left alone (D-NEXT-reenable).
        #expect(root.launchctlCalls == ["print \(target)", "bootstrap gui/\(getuid()) \(plist.path)"])

        // Its own intent and result records, by job label (SAF-006, HIS-002).
        let records = try launchctlRecords()
        #expect(records.map(\.path) == [label, label])
        #expect(records.map(\.status) == [nil, .ok])
        #expect(records.last?.detail == "bootstrap \(target): exit 0")
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
