import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Developer Junk's pip cache rule: `pip cache purge`, run through the safety pipeline against a fake `pip` inside the
/// fixture root (DEV-R08, DEV-002, DEV-003, DEV-004, SAF-010).
struct PipCacheTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let cache = "Library/Caches/pip"

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func scanned() async -> [ScanItem] {
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration(), toolRoot: root.url)
        return await items(from: DeveloperJunk(), context: context).filter { $0.method == .tool }
    }

    private func run(_ items: [ScanItem]) async throws -> RunReport {
        let plan = try Plan(subTool: DeveloperJunk(), items: items, pathGuard: pathGuard)
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        return await executor.run(plan)
    }

    @Test func itIsOneSelectedToolItemSizedFromTheCacheFolderDEVR08DEV003() async throws {
        let pip = try root.tool("opt/homebrew/bin/pip3", .reportsInvocation)
        try root.file("\(cache)/http-v2/a/b", size: 20_000)
        try root.file("\(cache)/wheels/c/d", size: 10_000)

        let items = await scanned()

        let item = try #require(items.first)
        #expect(items.count == 1)
        let rule = try #require(item.ruleMatch?.rule)
        #expect(rule.id == "DEV-R08" && rule.detection == .executable(pip.path))
        #expect(item.tier == .rebuildable && item.method == .tool && item.selection == .selected)
        #expect(item.category.id == "packages" && item.apps.isEmpty)
        guard case .command(let command) = item.target else {
            Issue.record("Not a command: \(item.target)")
            return
        }
        #expect(command.executable == pip.path && command.arguments == ["cache", "purge"])
        #expect(command.environment.count == 2 && command.environment.values.contains(root.url.path))
        #expect(item.allocatedSize >= 30_000)
        #expect(!root.aFakeToolRan, "Scanning started a tool")
    }

    @Test func aPipLinkIsPreferredToPip3AndNoToolOrCacheListsNothingDEV002() async throws {
        try root.file("\(cache)/http-v2/x", size: 100)
        #expect(await scanned().isEmpty, "Listed without pip")

        try root.tool("opt/homebrew/bin/pip3", .exits(0))
        let pip = try root.tool("usr/local/bin/pip", .exits(0))
        let rule = try #require(await scanned().first?.ruleMatch?.rule)
        #expect(rule.detection == .executable(pip.path))

        let other = try FixtureRoot()
        try other.tool("opt/homebrew/bin/pip3", .exits(0))
        let context = ScanContext(
            home: other.url, protection: other.pathGuardConfiguration(), toolRoot: other.url)
        #expect(await items(from: DeveloperJunk(), context: context).isEmpty, "Listed without a cache")
    }

    @Test func itRunsPipsOwnCommandAndShuckDeletesNoFileSAF010DEV004() async throws {
        try root.tool("opt/homebrew/bin/pip3", .reportsInvocation)
        let file = try root.file("\(cache)/wheels/x", size: 5000)

        let report = try await run(scanned())

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(root.aFakeToolRan)
        #expect(FileManager.default.fileExists(atPath: file.path))
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.allSatisfy { $0.operation == .tool && $0.tool == .developerJunk })
        let detail = try #require(records.last?.detail)
        for argument in ["cache", "purge"] { #expect(detail.contains("arg=\(argument)")) }
        #expect(try #require(LoggedCommand(logged: records[0].path)).commandLine == "pip3 cache purge")
        #expect(try HistoryLog.read(folder: root.historyFolder).entries().map(\.restorability) == [.permanent])
    }

    @Test func aFailingPipIsAFailureWithItsOutputInTheLogDEV004SAF011() async throws {
        try root.tool("opt/homebrew/bin/pip3", .exits(2, output: "ERROR: No matching packages"))
        try root.file("\(cache)/wheels/x", size: 100)

        let report = try await run(scanned())

        #expect(
            report.outcomes.map(\.result) == [
                .failed(ActionError(domain: "ShuckToolExit", code: 2, message: "exit status 2"))
            ])
        let item = try #require(try HistoryLog.read(folder: root.historyFolder).runs().first?.items.first)
        #expect(item.toolOutput == "ERROR: No matching packages")
    }

    /// DEV-002, SAF-016: Apple's own `pip3` is never used, so a scan cannot start the stub that installs the tools.
    @Test func applesOwnPip3IsNotUsedDEV002() async throws {
        try root.tool("usr/bin/pip3", .exits(0))
        try root.file("\(cache)/wheels/x", size: 100)

        #expect(await scanned().isEmpty)
    }
}
