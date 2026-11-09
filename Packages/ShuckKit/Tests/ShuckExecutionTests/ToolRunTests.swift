import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Tool items run through the plan executor against fake tools inside the fixture root (DEV-004, SAF-006, SAF-010,
/// NFR-SEC-004). Only `ShuckExecution` starts a process (D-82), so every test starts one through the executor.
struct ToolRunTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let category = ItemCategory(id: "fixture", name: "Fixture tools")
    let environment = ["PATH": "/usr/bin:/bin", "FIXTURE_VALUE": "yes"]

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func rule(
        _ tool: URL, arguments: [String] = [], timeout: TimeInterval = 600, apps: Set<String> = []
    ) throws -> CleanupRule {
        let command = try ToolCommand(
            executable: tool.path, arguments: arguments, environment: environment, timeout: timeout)
        return try CleanupRule(
            id: "fixture-tool", name: "Fixture tool", description: "Fixture", category: category,
            detection: .executable(tool.path), action: .command(command), tier: .rebuildable, selection: .always,
            explanation: "Fixture command", documentation: #require(URL(string: "https://example.test/tool")),
            apps: apps)
    }

    private func plan(_ rules: [CleanupRule]) throws -> Plan {
        let items = try rules.map {
            try $0.scanItem(estimatedBytes: 4096, source: FixtureSubTool.id, runningApps: StubRunningApps())
        }
        return try Plan(
            subTool: FixtureSubTool(tier: .rebuildable, method: .tool), items: items, pathGuard: pathGuard)
    }

    private func run(
        _ plan: Plan, runner: ToolRunner? = nil, running: Set<String> = []
    ) async throws -> RunReport {
        let executor = try PlanExecutor(
            root: root, pathGuard: pathGuard, runningApps: StubRunningApps(running), toolRunner: runner)
        // The run gets a task of its own, so cancelling it from the test cancels no more than the run.
        return await Task { await executor.run(plan) }.value
    }

    private func results() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
    }

    private func quickGrace() -> ToolRunner {
        ToolRunner(executableRoots: [root.url], outputLimit: 2048, killGrace: .milliseconds(300))
    }

    // MARK: - Running and logging

    @Test func aToolThatSucceedsIsLoggedWithItsExitCodeAndOutputSAF006DEV004() async throws {
        let tool = try root.tool("tools/cleaner", .exits(0, output: "Removed 3 packages"))
        let rule = try rule(tool, arguments: ["clean"])
        let display = try ToolCommand(rule: rule).display
        let report = try await run(plan([rule]))

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.map(\.phase) == [.intent, .result])
        #expect(records.allSatisfy { $0.operation == .tool && $0.tier == .rebuildable && $0.bytes == 4096 })
        #expect(records.allSatisfy { $0.path == display })
        #expect(records.last?.status == .ok)
        #expect(records.last?.detail == "exit 0; output: Removed 3 packages")
        #expect(records.last?.trashedPath == nil && records.last?.identity == nil)
    }

    @Test func aToolThatFailsIsAFailureWithItsExitCodeAndOutputSAF011DEV004() async throws {
        let tool = try root.tool("tools/cleaner", .exits(3, output: "Cannot clean: cache is locked"))
        let report = try await run(plan([rule(tool)]))

        #expect(
            report.outcomes.map(\.result) == [
                .failed(ActionError(domain: "ShuckToolExit", code: 3, message: "exit status 3"))
            ])
        let detail = try #require(results().first?.detail)
        #expect(try results().first?.status == .failed)
        #expect(detail == "ShuckToolExit 3: exit status 3; output: Cannot clean: cache is locked")
        // History reads it back as an error with its code.
        #expect(ActionError(logged: detail)?.code == 3)
    }

    @Test func theToolGetsTheReviewedArgumentsAndOnlyTheReviewedEnvironmentNFRSEC004() async throws {
        let tool = try root.tool("tools/reporter", .reportsInvocation)
        // Characters a shell would act on stay plain text, as there is no shell (DEV-004).
        let arguments = ["clean", "two words", "$FIXTURE_VALUE; touch Marks/shell", "*"]
        _ = try await run(plan([rule(tool, arguments: arguments)]))

        let output = try #require(results().first?.detail)
        for argument in arguments { #expect(output.contains("arg=\(argument)")) }
        #expect(output.contains("FIXTURE_VALUE=yes"))
        #expect(output.contains("PATH=/usr/bin:/bin"))
        // Nothing of the app's own environment reaches the tool.
        #expect(!output.contains("HOME=") && !output.contains("USER="))
        #expect(!FileManager.default.fileExists(atPath: root.url.appending(path: "Marks/shell").path))
    }

    @Test func aToolsOutputIsCutToItsEndInTheLogDEV004() async throws {
        let tool = try root.tool("tools/chatty", .printsALot(bytes: 100_000, last: "FINISHED"))
        let report = try await run(plan([rule(tool)]), runner: quickGrace())

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        let detail = try #require(results().first?.detail)
        #expect(detail.hasPrefix("exit 0; output: …") && detail.hasSuffix("FINISHED"))
        #expect(detail.utf8.count < 2048 + 64)
    }

    // MARK: - Timeout and Stop

    @Test func aToolThatOutlastsItsTimeoutIsStoppedAndLoggedAsAFailureDEV004() async throws {
        let tool = try root.tool("tools/slow", .runsForever)
        let started = Date()
        let report = try await run(plan([rule(tool, timeout: 0.3)]), runner: quickGrace())

        #expect(
            report.outcomes.map(\.result) == [
                .failed(
                    ActionError(domain: "ShuckToolTimeout", code: 1, message: "no end within 1 seconds; stopped"))
            ])
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(try results().first?.status == .failed)
        #expect(try results().first?.detail?.hasPrefix("ShuckToolTimeout 1: ") == true)
    }

    @Test func aToolThatIgnoresTheRequestToEndIsKilledDEV004() async throws {
        let tool = try root.tool("tools/stubborn", .ignoresTerminate)
        let started = Date()
        let report = try await run(plan([rule(tool, timeout: 0.3)]), runner: quickGrace())

        guard case .failed(let error) = report.outcomes.first?.result else {
            Issue.record("The tool was not stopped: \(report.outcomes.map(\.result))")
            return
        }
        #expect(error.domain == "ShuckToolTimeout")
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func stoppingARunEndsTheToolAndSkipsTheRestSAF014() async throws {
        let slow = try root.tool("tools/slow", .runsForever)
        let other = try root.tool("tools/other", .exits(0))
        let plan = try plan([rule(slow), rule(other)])
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard, toolRunner: quickGrace())

        let running = Task { await executor.run(plan) }
        // Wait until the tool is running, as when the user clicks Stop in the middle of a command.
        for _ in 0..<200 where !root.aFakeToolRan { try await Task.sleep(for: .milliseconds(50)) }
        #expect(root.aFakeToolRan)
        running.cancel()
        let report = await running.value

        #expect(
            report.outcomes.map(\.result) == [
                .failed(ActionError(domain: "ShuckToolStopped", code: Int(SIGTERM), message: "stopped by the user")),
                .skipped(.cancelled),
            ])
        // The stopped tool's records say what happened; the item after it never started, so it has none.
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.map(\.phase) == [.intent, .result])
        #expect(records.last?.status == .failed && records.last?.detail?.hasPrefix("ShuckToolStopped") == true)
    }

    // MARK: - Re-validation

    @Test func aToolItemWithoutItsRuleNeverRunsSAF010() async throws {
        let tool = try root.tool("tools/reporter", .reportsInvocation)
        let command = try ToolCommand(executable: tool.path, arguments: [], environment: environment)
        let item = PlannedItem(command: command, allocatedSize: 1, tier: .rebuildable, category: category)
        let plan = try Plan(
            tool: FixtureSubTool.id, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)

        let report = try await run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.ruleChanged)])
        #expect(!root.aFakeToolRan)
        #expect(try results().first?.detail == "ruleChanged")
    }

    @Test func aToolThatDisappearedSinceTheScanIsSkippedDEV002() async throws {
        let tool = try root.tool("tools/reporter", .reportsInvocation)
        let plan = try plan([rule(tool)])
        try FileManager.default.removeItem(at: tool)

        let report = try await run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.ruleChanged)])
        #expect(!root.aFakeToolRan)
    }

    @Test func aToolOutsideTheFixtureRootNeverRunsSAF016() async throws {
        // The rule's detection is satisfied by a real tool; the runner in the fixture-root mode still refuses it.
        let command = try ToolCommand(executable: "/usr/bin/true", arguments: [], environment: environment)
        let rule = try CleanupRule(
            id: "real-tool", name: "Real tool", description: "Fixture", category: category,
            detection: .executable("/usr/bin/true"), action: .command(command), tier: .rebuildable,
            selection: .always, explanation: "Fixture", documentation: #require(URL(string: "https://example.test")))

        let report = try await run(plan([rule]))

        #expect(report.outcomes.map(\.result) == [.skipped(.toolUnavailable(.outsideRoots))])
        #expect(try results().first?.detail == "toolUnavailable: outsideRoots")
    }

    @Test func aLinkInsideTheRootToAToolOutsideItIsRefusedSAF016() throws {
        let link = try root.symlink("tools/true", to: URL(filePath: "/usr/bin/true"))
        let command = try ToolCommand(executable: link.path, arguments: [], environment: environment)
        #expect(ToolRunner(executableRoots: [root.url]).locate(command) == .failure(.outsideRoots))
        #expect(ToolRunner(executableRoots: nil).locate(command) != .failure(.outsideRoots))
    }

    @Test func onlyARunnableFileCountsAsAToolDEV002() throws {
        let plain = try root.file("tools/plain", size: 10, permissions: 0o644)
        let folder = try root.folder("tools/folder")
        let missing = root.url.appending(path: "tools/missing")
        let runner = ToolRunner(executableRoots: [root.url])
        for path in [plain, folder, missing] {
            let command = try ToolCommand(executable: path.path, arguments: [], environment: environment)
            #expect(runner.locate(command) == .failure(.notAnExecutable))
        }
        let tool = try root.tool("tools/real", .exits(0))
        #expect(
            try runner.locate(ToolCommand(executable: tool.path, arguments: [], environment: environment))
                == .success(tool))
    }

    @Test func aToolItemIsSkippedWhileItsAppRunsSAF009() async throws {
        let tool = try root.tool("tools/reporter", .reportsInvocation)
        let plan = try plan([rule(tool, apps: ["com.example.app"])])

        let report = try await run(plan, running: ["com.example.app"])

        #expect(report.outcomes.map(\.result) == [.skipped(.appRunning)])
        #expect(!root.aFakeToolRan)
    }
}

extension ToolCommand {
    /// The command of a rule that has one.
    fileprivate init(rule: CleanupRule) throws {
        guard case .command(let command) = rule.action else { throw ToolCommandError.invalidExecutable }
        self = command
    }
}
