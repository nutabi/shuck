import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Developer Junk's unavailable simulators rule: `xcrun simctl delete unavailable`, run through the safety pipeline
/// against a fake `xcrun` inside the fixture root (DEV-R03, DEV-002, DEV-004, SAF-010, DEV-007).
struct UnavailableSimulatorsTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let devices = "Library/Developer/CoreSimulator/Devices"

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func scanned(toolRoot: URL? = nil, running: Set<String> = []) async -> [ScanItem] {
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running),
            toolRoot: toolRoot ?? root.url)
        return await items(from: DeveloperJunk(), context: context).filter { $0.method == .tool }
    }

    private func run(_ items: [ScanItem]) async throws -> RunReport {
        let plan = try Plan(subTool: DeveloperJunk(), items: items, pathGuard: pathGuard)
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        return await executor.run(plan)
    }

    @Test func itIsOneSelectedToolItemForXcrunWhenTheMacHasSimulatorsDEVR03() async throws {
        let xcrun = try root.xcrun(.exits(0))
        try root.file("\(devices)/ABCD-1234/device.plist", size: 10)

        let items = await scanned()

        let item = try #require(items.first)
        #expect(items.count == 1)
        let rule = try #require(item.ruleMatch?.rule)
        #expect(rule.id == "DEV-R03" && rule.detection == .executable(xcrun.path))
        #expect(item.tier == .rebuildable && item.method == .tool && item.selection == .selected)
        #expect(item.category.id == "xcode" && item.apps.isEmpty && item.source == .developerJunk)
        guard case .command(let command) = item.target else {
            Issue.record("Not a command: \(item.target)")
            return
        }
        // Exactly the PRD's command, with no shell, and an environment of two variables (DEV-004).
        #expect(command.executable == xcrun.path)
        #expect(command.arguments == ["simctl", "delete", "unavailable"])
        #expect(command.environment.count == 2 && command.environment.values.contains(root.url.path))
        // No size can be known without reading simctl's output, which never chooses what is removed (R-07).
        #expect(item.allocatedSize == 0 && item.snapshot == nil)
    }

    /// `/usr/bin/xcrun` is on every Mac. Without Xcode it has no `simctl` to run, and running it can raise the prompt
    /// to install the command line developer tools, so the rule is hidden (DEV-002).
    @Test func xcrunWithoutXcodesSimctlIsNotDetectionDEV002() async throws {
        try root.file("\(devices)/ABCD-1234/device.plist", size: 10)
        try root.tool("usr/bin/xcrun", .exits(0))
        #expect(await scanned().isEmpty, "Listed without Xcode")

        // Only the command line tools are selected: their folder has no simctl, whatever is in Applications.
        try root.tool(FixtureRoot.simctlPath, .exits(0))
        let commandLineTools = try root.folder("Library/Developer/CommandLineTools")
        try root.folder("var/db")
        try root.symlink("var/db/xcode_select_link", to: commandLineTools)
        #expect(await scanned().isEmpty, "Listed with only the command line tools selected")
    }

    @Test func theSelectedDeveloperFolderIsWhereSimctlIsLookedForDEV002() async throws {
        try root.file("\(devices)/ABCD-1234/device.plist", size: 10)
        try root.tool("usr/bin/xcrun", .exits(0))
        try root.tool("Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl", .exits(0))
        try root.folder("var/db")
        try root.symlink(
            "var/db/xcode_select_link", to: try root.url("Applications/Xcode-beta.app/Contents/Developer"))

        #expect(await scanned().count == 1)
    }

    @Test func withoutXcrunOrSimulatorsOrAToolRootNothingIsListedDEV002() async throws {
        try root.file("\(devices)/ABCD-1234/device.plist", size: 10)
        #expect(await scanned().isEmpty, "Listed without xcrun")

        try root.xcrun(.exits(0))
        let withoutSimulators = try FixtureRoot()
        try withoutSimulators.xcrun(.exits(0))
        let context = ScanContext(
            home: withoutSimulators.url, protection: withoutSimulators.pathGuardConfiguration(),
            toolRoot: withoutSimulators.url)
        #expect(await items(from: DeveloperJunk(), context: context).isEmpty, "Listed without simulators")

        // A scan that asks for no tools finds none, whatever is installed.
        let noTools = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        #expect(await items(from: DeveloperJunk(), context: noTools).isEmpty, "Listed without a tool root")
        // A tool outside the root is not the fixture's.
        #expect(await scanned(toolRoot: try root.folder("Elsewhere")).isEmpty, "Found a tool outside its root")
    }

    @Test func itRunsThroughTheToolAndTheDeviceDataStaysUntouchedSAF010DEV007() async throws {
        let xcrun = try root.xcrun(.reportsInvocation)
        let device = try root.file("\(devices)/ABCD-1234/device.plist", size: 10)

        let report = try await run(scanned())

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(root.aFakeToolRan)
        // No file operation: the devices are `simctl`'s, and the item is never a Delete (SAF-010).
        #expect(FileManager.default.fileExists(atPath: device.path))
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.map(\.phase) == [.intent, .result])
        #expect(records.allSatisfy { $0.operation == .tool && $0.tool == .developerJunk && $0.tier == .rebuildable })
        let command = try #require(LoggedCommand(logged: records[0].path))
        #expect(command.executable == xcrun.path && command.commandLine == "xcrun simctl delete unavailable")
        let detail = try #require(records.last?.detail)
        for argument in ["simctl", "delete", "unavailable"] { #expect(detail.contains("arg=\(argument)")) }
        #expect(detail.contains("HOME=\(root.url.path)"))
        #expect(detail.contains("PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(try HistoryLog.read(folder: root.historyFolder).entries().map(\.restorability) == [.permanent])
    }

    @Test func aFailingXcrunIsAFailureAndHistoryShowsTheCommandAndItsOutputDEV004SAF011() async throws {
        try root.xcrun(.exits(2, output: "xcrun: error: unable to find utility \"simctl\""))
        try root.file("\(devices)/ABCD-1234/device.plist", size: 10)

        let report = try await run(scanned())

        #expect(
            report.outcomes.map(\.result) == [
                .failed(ActionError(domain: "ShuckToolExit", code: 2, message: "exit status 2"))
            ])
        let item = try #require(try HistoryLog.read(folder: root.historyFolder).runs().first?.items.first)
        #expect(item.outcome == .failed("ShuckToolExit 2: exit status 2"))
        #expect(item.toolOutput == "xcrun: error: unable to find utility \"simctl\"")
        #expect(item.operation == .tool)
    }

    @Test func xcrunThatWentAwayAfterTheScanIsSkippedSAF010() async throws {
        let xcrun = try root.xcrun(.exits(0))
        try root.file("\(devices)/ABCD-1234/device.plist", size: 10)
        let items = await scanned()
        try FileManager.default.removeItem(at: xcrun)

        let report = try await run(items)

        #expect(report.outcomes.map(\.result) == [.skipped(.ruleChanged)])
        #expect(!root.aFakeToolRan)
    }
}
