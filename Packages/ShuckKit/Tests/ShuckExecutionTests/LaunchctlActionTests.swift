import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Launchctl items run through the plan executor against a fake `launchctl` inside the fixture root (APP-011, STA-005,
/// SAF-005, SAF-006, SAF-011, NFR-SEC-004). The real `launchctl` is never reachable (SAF-016, D-82).
struct LaunchctlActionTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let domain = "gui/\(getuid())"

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func plist(_ name: String = "com.example.helper", label: String? = "com.example.helper.job") throws -> URL {
        let entry = label.map { "<key>Label</key><string>\($0)</string>" } ?? ""
        let text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>\(entry)<key>RunAtLoad</key><true/></dict></plist>
            """
        return try root.file("Library/LaunchAgents/\(name).plist", text: text)
    }

    private func run(_ item: PlannedItem) async throws -> RunReport {
        let plan = try Plan(tool: .applications, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        return await Task { await executor.run(plan) }.value
    }

    private func planned(_ url: URL) throws -> PlannedItem {
        try root.planned(url, tier: .yourData, method: .launchctl)
    }

    private func records() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records
    }

    @Test func aLoadedAgentIsBootedOutOfTheUsersDomainAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let plist = try plist()
        let report = try await run(planned(plist))

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        let target = "\(domain)/com.example.helper.job"
        #expect(root.launchctlCalls == ["print \(target)", "bootout \(target)"])
        // The plist is not touched: its own Trash item moves it (APP-011).
        #expect(FileManager.default.fileExists(atPath: plist.path))
    }

    @Test func anAgentThatIsNotLoadedIsDoneWithoutABootoutAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: LaunchctlAction.notLoadedStatus))
        let report = try await run(planned(plist()))

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(root.launchctlCalls == ["print \(domain)/com.example.helper.job"])
        #expect(try records().last?.detail?.hasPrefix("not loaded") == true)
        #expect(try records().last?.status == .ok)
    }

    @Test func aBootoutThatFailsIsAFailureWithItsStatusSAF011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0, bootoutStatus: 5))
        let report = try await run(planned(plist()))

        guard case .failed(let error) = report.outcomes.first?.result else {
            Issue.record("Expected a failure")
            return
        }
        #expect(error.domain == "ShuckToolExit" && error.code == 5)
        #expect(try records().last?.status == .failed)
        #expect(try records().last?.detail?.hasPrefix("bootout \(domain)/com.example.helper.job: ") == true)
    }

    @Test func aPrintThatFailsOtherwiseLeavesTheAgentLoadedAndFailsTheItemSAF011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 64))
        let report = try await run(planned(plist()))

        guard case .failed(let error) = report.outcomes.first?.result else {
            Issue.record("Expected a failure")
            return
        }
        #expect(error.code == 64)
        #expect(root.launchctlCalls.count == 1)
    }

    @Test func theLogRecordsIntentAndResultWithTheJobLabelSAF005SAF006() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        _ = try await run(planned(plist()))

        let records = try records()
        #expect(records.map(\.phase) == [.intent, .result])
        #expect(records.allSatisfy { $0.path == "com.example.helper.job" })
        #expect(records.allSatisfy { $0.operation == .launchctl && $0.tier == .yourData && $0.tool == .applications })
        #expect(records.last?.status == .ok)
        #expect(records.last?.trashedPath == nil && records.last?.identity == nil)
        let entries = try HistoryLog.read(folder: root.historyFolder).entries()
        #expect(entries.map(\.restorability) == [.reversedByOppositeAction])
    }

    @Test func aPropertyListWithoutALabelFailsAndRunsNothingAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let plist = try plist(label: nil)
        let report = try await run(planned(plist))

        guard case .failed(let error) = report.outcomes.first?.result else {
            Issue.record("Expected a failure")
            return
        }
        #expect(error.message.contains("Label"))
        #expect(root.launchctlCalls.isEmpty)
        // With no label to log, the intent names the property list.
        #expect(try records().first?.path == plist.path)
    }

    @Test func theLabelIsReadFromThePropertyListNotFromItsFileNameAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        _ = try await run(planned(plist("some-other-name", label: "org.example.agent")))

        #expect(root.launchctlCalls.first == "print \(domain)/org.example.agent")
    }

    @Test func aLabelThatCannotNameOneJobIsNotUsedAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let report = try await run(planned(plist(label: "a/b")))

        guard case .failed = report.outcomes.first?.result else {
            Issue.record("Expected a failure")
            return
        }
        #expect(root.launchctlCalls.isEmpty)
    }

    @Test func aMissingLaunchctlSkipsTheItemAsUnavailableSAF011() async throws {
        let report = try await run(planned(plist()))

        #expect(report.outcomes.map(\.result) == [.skipped(.toolUnavailable(.notAnExecutable))])
    }

    @Test func theRealLaunchctlIsNeverReachableFromAFixtureRootNFRSEC004() async throws {
        // A link inside the root to the real tool resolves outside it, so a fixture-root run refuses it.
        _ = try root.symlink("bin/launchctl", to: URL(filePath: "/bin/launchctl"))
        let report = try await run(planned(plist()))

        #expect(report.outcomes.map(\.result) == [.skipped(.toolUnavailable(.outsideRoots))])
    }

    @Test func anAgentChangedSinceTheScanIsSkippedAndNothingRunsSAF008() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let plist = try plist()
        let item = try planned(plist)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: plist.path)
        let report = try await run(item)

        #expect(report.outcomes.map(\.result) == [.skipped(.modifiedSinceScan)])
        #expect(root.launchctlCalls.isEmpty)
    }
}
