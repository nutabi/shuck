import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Developer Junk's tool rules, `npm cache clean --force`, `brew cleanup`, `pip cache purge` and `xcrun simctl delete
/// unavailable`, run through the safety pipeline against fake tools inside the fixture root (DEV-R03, DEV-R07, DEV-R08,
/// DEV-R09, DEV-002, DEV-003, DEV-004, DEV-007, SAF-010). Every rule is a case of one table, so what holds for one tool
/// is checked for all of them.
struct ToolCommandTests {
    struct ToolCase: Sendable, CustomTestStringConvertible {
        let name: String
        let ruleID: String
        let category: String
        /// Writes the fake tool, behaving as asked, and returns where it lies.
        let installer: @Sendable (FixtureRoot, FakeTool) throws -> URL
        let arguments: [String]
        /// What History shows of the command.
        let commandLine: String
        /// The environment's variables beyond `HOME`, and how many it has in all (DEV-004, NFR-SEC-001).
        let settings: [String: String]
        let variables: Int
        /// The files the tool's folders hold, all of which stay when the fake tool deletes nothing.
        let filler: @Sendable (FixtureRoot) throws -> [URL]
        /// The folder the item is sized from, and the file inside it the tool removes. Homebrew's item has no size before
        /// the run (D-194); an unavailable simulators' item has no folder at all.
        let measured: (folder: String, removable: String)?
        let sizedByScan: Bool
        /// What it prints and how it ends when it fails.
        let failure: (status: Int32, output: String)
        /// Folders whose exclusion after the plan stops the command (SET-001, D-150).
        let exclusions: [String]

        var testDescription: String { name }

        @discardableResult
        func install(_ root: FixtureRoot, _ behavior: FakeTool) throws -> URL { try installer(root, behavior) }

        @discardableResult
        func fill(_ root: FixtureRoot) throws -> [URL] { try filler(root) }

        static let npm = ToolCase(
            name: "npm", ruleID: "DEV-R07", category: "packages",
            installer: { root, behavior in try root.tool("opt/homebrew/bin/npm", behavior) },
            arguments: ["cache", "clean", "--force"], commandLine: "npm cache clean --force",
            settings: ["NPM_CONFIG_UPDATE_NOTIFIER": "false", "NPM_CONFIG_OFFLINE": "true"], variables: 4,
            filler: { root in
                [
                    try root.file(".npm/_cacache/content-v2/a", size: 60_000),
                    try root.file(".npm/_cacache/content-v2/b", size: 30_000),
                ]
            },
            measured: (".npm/_cacache", ".npm/_cacache/content-v2/a"), sizedByScan: true,
            failure: (1, "npm error code EACCES"), exclusions: [".npm"])

        static let homebrew = ToolCase(
            name: "Homebrew", ruleID: "DEV-R09", category: "packages",
            installer: { root, behavior in try root.tool("opt/homebrew/bin/brew", behavior) },
            arguments: ["cleanup"], commandLine: "brew cleanup",
            settings: ["HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_NO_AUTO_UPDATE": "1"], variables: 5,
            filler: { root in
                [
                    try root.file("Library/Caches/Homebrew/downloads/a", size: 60_000),
                    try root.file("Library/Caches/Homebrew/downloads/b", size: 30_000),
                    // The Cellar is `brew`'s alone: Shuck never deletes in it, and its exclusion stops the command.
                    try root.file("opt/homebrew/Cellar/git/2.46.0/bin/git", size: 5000),
                    try root.file("opt/homebrew/Caskroom/app/1.0/app", size: 5000),
                    try root.file("Library/Logs/Homebrew/log", size: 5000),
                ]
            },
            measured: ("Library/Caches/Homebrew", "Library/Caches/Homebrew/downloads/a"), sizedByScan: false,
            failure: (1, "Error: Permission denied @ apply2files"),
            exclusions: ["opt/homebrew/Cellar", "opt/homebrew/Caskroom/app", "opt/homebrew", "Library/Logs/Homebrew"])

        static let pip = ToolCase(
            name: "pip", ruleID: "DEV-R08", category: "packages",
            installer: { root, behavior in try root.tool("opt/homebrew/bin/pip3", behavior) },
            arguments: ["cache", "purge"], commandLine: "pip3 cache purge",
            settings: ["PIP_DISABLE_PIP_VERSION_CHECK": "1", "PIP_NO_INPUT": "1"], variables: 4,
            filler: { root in
                [
                    try root.file("Library/Caches/pip/wheels/a", size: 60_000),
                    try root.file("Library/Caches/pip/wheels/b", size: 30_000),
                ]
            },
            measured: ("Library/Caches/pip", "Library/Caches/pip/wheels/a"), sizedByScan: true,
            failure: (2, "ERROR: No matching packages"), exclusions: [])

        static let xcrun = ToolCase(
            name: "xcrun simctl", ruleID: "DEV-R03", category: "xcode",
            installer: { root, behavior in try root.xcrun(behavior) },
            arguments: ["simctl", "delete", "unavailable"], commandLine: "xcrun simctl delete unavailable",
            settings: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"], variables: 2,
            filler: { root in
                [try root.file("Library/Developer/CoreSimulator/Devices/ABCD-1234/device.plist", size: 10)]
            },
            measured: nil, sizedByScan: false,
            failure: (2, "xcrun: error: unable to find utility \"simctl\""), exclusions: [])

        static let all = [npm, homebrew, pip, xcrun]
        static let measuredOnes = all.filter { $0.measured != nil }

        /// The tool's item, as a plan that a user excluded one of the tool's folders after making.
        var exclusionCases: [PlanToRunTests.Case] {
            exclusions.map { excluded in
                PlanToRunTests.Case(name: "\(name): the command, \(excluded) excluded") { root, pathGuard in
                    try install(root, .reportsInvocation)
                    try fill(root)
                    let plan = try Plan(
                        subTool: DeveloperJunk(), items: await ToolCommandTests.scanned(root), pathGuard: pathGuard)
                    return PlanToRunTests.Scenario(plan: plan, excluded: try root.url(excluded), isTool: true)
                }
            }
        }
    }

    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    static func scanned(_ root: FixtureRoot) async -> [ScanItem] {
        await Rig.tools(root).scan().filter { $0.method == .tool }
    }

    private func run(_ items: [ScanItem]) async throws -> RunReport {
        let plan = try Plan(subTool: DeveloperJunk(), items: items, pathGuard: pathGuard)
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        return await executor.run(plan)
    }

    private func records() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records
    }

    private func size(_ folder: String) throws -> Int64 {
        try #require(ItemSnapshot.read(try root.url(folder))).allocatedSize
    }

    // MARK: - Listing and running

    @Test(arguments: ToolCase.all)
    func
        aToolItemIsListedAndRunsTheToolsOwnCommandAndShuckDeletesNoFileDEVR03DEVR07DEVR08DEVR09DEV003DEV004DEV007SAF010(
            _ tool: ToolCase
        ) async throws
    {
        let executable = try tool.install(root, .reportsInvocation)
        let files = try tool.fill(root)

        let items = await Self.scanned(root)

        let item = try #require(items.first)
        #expect(items.count == 1)
        let rule = try #require(item.ruleMatch?.rule)
        #expect(rule.id == tool.ruleID && rule.detection == .executable(executable.path))
        #expect(item.tier == .rebuildable && item.method == .tool && item.selection == .selected)
        #expect(item.category.id == tool.category && item.apps.isEmpty && item.source == .developerJunk)
        guard case .command(let command) = item.target else {
            Issue.record("Not a command: \(item.target)")
            return
        }
        // Exactly the PRD's command, with no shell and only the reviewed environment (DEV-004).
        #expect(command.executable == executable.path && command.arguments == tool.arguments)
        #expect(command.environment.count == tool.variables && command.environment.values.contains(root.url.path))
        for (name, value) in tool.settings { #expect(command.environment[name] == value) }
        // The estimate is the measured folder, an upper bound for what the tool removes, or none: no size can be known
        // without reading the tool's output, which never chooses what is removed (R-07, DEV-R09, D-194).
        if tool.sizedByScan {
            #expect(item.allocatedSize >= 90_000)
        } else {
            #expect(item.allocatedSize == 0 && item.snapshot == nil)
        }
        // Scanning never starts a tool (R-07).
        #expect(!root.aFakeToolRan, "Scanning started a tool")

        let report = try await run(items)

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(root.aFakeToolRan)
        // The fake tool deletes nothing, so every file is as it was: Shuck deletes no file of the tool's, not the cache
        // and never what only the tool may change, such as the Cellar or the simulators' devices (SAF-010).
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let records = try records()
        #expect(records.map(\.phase) == [.intent, .result])
        #expect(records.allSatisfy { $0.operation == .tool && $0.tool == .developerJunk && $0.tier == .rebuildable })
        let logged = try #require(LoggedCommand(logged: records[0].path))
        #expect(logged.executable == executable.path && logged.commandLine == tool.commandLine)
        let detail = try #require(records.last?.detail)
        for argument in tool.arguments { #expect(detail.contains("arg=\(argument)")) }
        #expect(detail.contains("HOME=\(root.url.path)"))
        for (name, value) in tool.settings { #expect(detail.contains("\(name)=\(value)")) }
        #expect(try HistoryLog.read(folder: root.historyFolder).entries().map(\.restorability) == [.permanent])
    }

    @Test(arguments: ToolCase.all)
    func aFailingToolIsAFailureWithItsOutputInTheLogDEV004SAF011(_ tool: ToolCase) async throws {
        try tool.install(root, .exits(tool.failure.status, output: tool.failure.output))
        try tool.fill(root)

        let report = try await run(await Self.scanned(root))

        let status = Int(tool.failure.status)
        #expect(
            report.outcomes.map(\.result) == [
                .failed(ActionError(domain: "ShuckToolExit", code: status, message: "exit status \(status)"))
            ])
        let item = try #require(try HistoryLog.read(folder: root.historyFolder).runs().first?.items.first)
        #expect(item.outcome == .failed("ShuckToolExit \(status): exit status \(status)"))
        #expect(item.toolOutput == tool.failure.output && item.operation == .tool)
    }

    @Test(arguments: ToolCase.all)
    func aToolThatWentAwayAfterTheScanIsSkippedSAF010DEV002(_ tool: ToolCase) async throws {
        let executable = try tool.install(root, .reportsInvocation)
        try tool.fill(root)
        let items = await Self.scanned(root)
        try FileManager.default.removeItem(at: executable)

        let report = try await run(items)

        #expect(report.outcomes.map(\.result) == [.skipped(.ruleChanged)])
        #expect(!root.aFakeToolRan)
    }

    // MARK: - What a run removed

    /// What a tool item reports as removed is the folder it is sized from, measured before and after the command: not
    /// the scan's estimate and never the tool's output (DEV-003, SAF-011, R-07, D-184).
    @Test(arguments: ToolCase.all)
    func aToolItemReportsWhatItRemovedMeasuredFromItsFolderDEV003SAF011(_ tool: ToolCase) async throws {
        try tool.install(root, tool.measured.map { FakeTool.removes([$0.removable]) } ?? .exits(0))
        try tool.fill(root)
        let items = await Self.scanned(root)
        let before = try tool.measured.map { try size($0.folder) }

        let report = try await run(items)

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        guard let measured = tool.measured, let before else {
            // There is no folder to measure: an unavailable simulators' devices are `simctl`'s alone.
            #expect(report.outcomes.first?.removedBytes == nil)
            return
        }
        let removed = try #require(report.outcomes.first?.removedBytes)
        #expect(removed == before - (try size(measured.folder)))
        #expect(removed >= 60_000 && removed < before)
        #expect(!FileManager.default.fileExists(atPath: try root.url(measured.removable).path))
        // The intent keeps the estimate; the result has the measured size, which History shows (SAF-005, SAF-006).
        let records = try records()
        #expect(records.first { $0.phase == .intent }?.bytes == items.first?.allocatedSize)
        #expect(records.first { $0.phase == .result }?.bytes == removed)
    }

    enum Unreliable: CaseIterable, Sendable {
        /// It says it removed more than it did.
        case lies
        /// It removes something and then fails.
        case fails
    }

    @Test(arguments: ToolCase.measuredOnes, Unreliable.allCases)
    func aToolThatSaysItRemovedMoreOrFailsIsNotBelievedDEV003SAF011R07(_ tool: ToolCase, _ how: Unreliable) async throws
    {
        let measured = try #require(tool.measured)
        switch how {
        case .lies:
            try tool.install(root, .exits(0, output: "Removing: \(measured.removable)... (200 MB)"))
        case .fails:
            try tool.install(root, .removes([measured.removable], status: 1))
        }
        try tool.fill(root)
        let items = await Self.scanned(root)

        let report = try await run(items)

        let records = try records()
        let estimate = items.first?.allocatedSize
        #expect(records.first { $0.phase == .intent }?.bytes == estimate)
        switch how {
        case .lies:
            // Nothing was removed, whatever the tool said.
            #expect(report.outcomes.first?.removedBytes == 0)
            #expect(records.first { $0.phase == .result }?.bytes == 0)
        case .fails:
            // A failed run keeps the estimate and reports no measurement.
            #expect(report.outcomes.first?.removedBytes == nil)
            if case .failed = report.outcomes[0].result {} else { Issue.record("not a failure") }
            #expect(records.first { $0.phase == .result }?.bytes == estimate)
        }
    }

    // MARK: - Detection (DEV-002)

    @Test(arguments: ToolCase.all)
    func aMacWithoutTheToolOrItsCacheListsNothingDEV002(_ tool: ToolCase) async throws {
        try tool.fill(root)
        #expect(await Self.scanned(root).isEmpty, "Listed without the tool")

        let other = try FixtureRoot()
        try tool.install(other, .exits(0))
        #expect(await Self.scanned(other).isEmpty, "Listed without a cache")
    }

    /// Where a tool is found: in the second folder when the first has none, a `pip` link before `pip3`, and never
    /// Apple's own `pip3`, which a scan could start the stub that installs the tools with (SAF-016).
    struct Detection: Sendable, CustomTestStringConvertible {
        let name: String
        let tools: [String]
        let cache: String
        let found: String?

        var testDescription: String { name }
    }

    @Test(arguments: [
        Detection(
            name: "npm in the second folder", tools: ["usr/local/bin/npm"], cache: ".npm/_cacache/content-v2/x",
            found: "usr/local/bin/npm"),
        Detection(
            name: "a pip link before pip3", tools: ["opt/homebrew/bin/pip3", "usr/local/bin/pip"],
            cache: "Library/Caches/pip/wheels/x", found: "usr/local/bin/pip"),
        Detection(name: "Apple's own pip3", tools: ["usr/bin/pip3"], cache: "Library/Caches/pip/wheels/x", found: nil),
    ])
    func aToolIsFoundWhereItIsLookedForDEV002(_ detection: Detection) async throws {
        let paths = try detection.tools.map { try root.tool($0, .exits(0)).path }
        try root.file(detection.cache, size: 100)

        let rule = await Self.scanned(root).first?.ruleMatch?.rule

        let expected = detection.found.flatMap { found in detection.tools.firstIndex(of: found).map { paths[$0] } }
        #expect(rule?.detection == expected.map(CleanupRule.Detection.executable))
    }

    /// `/usr/bin/xcrun` is on every Mac. Without Xcode it has no `simctl` to run, and running it can raise the prompt to
    /// install the command line developer tools, so the rule is hidden; the selected developer folder is where `simctl`
    /// is looked for (DEV-002).
    @Test func xcrunIsDetectedOnlyWhenTheSelectedDeveloperFolderHasSimctlDEV002() async throws {
        try ToolCase.xcrun.fill(root)
        try root.tool("usr/bin/xcrun", .exits(0))
        #expect(await Self.scanned(root).isEmpty, "Listed without Xcode")

        // Only the command line tools are selected: their folder has no simctl, whatever is in Applications.
        try root.tool(FixtureRoot.simctlPath, .exits(0))
        let commandLineTools = try root.folder("Library/Developer/CommandLineTools")
        try root.folder("var/db")
        let link = try root.symlink("var/db/xcode_select_link", to: commandLineTools)
        #expect(await Self.scanned(root).isEmpty, "Listed with only the command line tools selected")

        try root.tool("Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl", .exits(0))
        try FileManager.default.removeItem(at: link)
        try root.symlink(
            "var/db/xcode_select_link", to: try root.url("Applications/Xcode-beta.app/Contents/Developer"))
        #expect(await Self.scanned(root).count == 1, "Not listed with Xcode selected")

        // A scan that asks for no tools finds none, whatever is installed, and a tool outside the root is not the
        // fixture's.
        let noTools = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        #expect(await items(from: DeveloperJunk(), context: noTools).isEmpty, "Listed without a tool root")
        let elsewhere = try root.folder("Elsewhere")
        let outside = ScanContext(home: root.url, protection: root.pathGuardConfiguration(), toolRoot: elsewhere)
        #expect(await items(from: DeveloperJunk(), context: outside).filter { $0.method == .tool }.isEmpty)
    }
}
