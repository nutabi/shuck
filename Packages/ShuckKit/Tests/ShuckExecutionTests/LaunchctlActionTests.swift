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

    @Test func aLoadedAgentIsBootedOutByTheLabelInItsPropertyListAPP011() async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        // The file name differs from the label: the label comes from the property list, not from the name.
        let plist = try plist("some-other-name", label: "org.example.agent")
        let report = try await run(planned(plist))

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        let target = "\(domain)/org.example.agent"
        #expect(
            root.launchctlCalls == ["print \(target)", "bootout \(target)"],
            "calls: \(root.launchctlCalls), results: \(report.outcomes.map(\.result))")
        // The plist is not touched: its own Trash item moves it (APP-011).
        #expect(FileManager.default.fileExists(atPath: plist.path))
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

    @Test(arguments: [nil, "a/b"] as [String?])
    func aPropertyListWithoutALabelThatNamesOneJobFailsAndRunsNothingAPP011(label: String?) async throws {
        try root.tool("bin/launchctl", .launchctl(printStatus: 0))
        let plist = try plist(label: label)
        let report = try await run(planned(plist))

        guard case .failed(let error) = report.outcomes.first?.result else {
            Issue.record("Expected a failure")
            return
        }
        #expect(root.launchctlCalls.isEmpty)
        if label == nil {
            #expect(error.message.contains("Label"))
            // With no label to log, the intent names the property list.
            #expect(try records().first?.path == plist.path)
        }
    }

    /// A tool that is not there, and the real one, which a link inside the root reaches outside it (SAF-016, D-82).
    @Test(arguments: [false, true])
    func aLaunchctlThatCannotBeRunIsSkippedAsUnavailableSAF011NFRSEC004(isTheRealOne: Bool) async throws {
        if isTheRealOne { _ = try root.symlink("bin/launchctl", to: URL(filePath: "/bin/launchctl")) }
        let report = try await run(planned(plist()))

        #expect(
            report.outcomes.map(\.result) == [
                .skipped(.toolUnavailable(isTheRealOne ? .outsideRoots : .notAnExecutable))
            ])
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
