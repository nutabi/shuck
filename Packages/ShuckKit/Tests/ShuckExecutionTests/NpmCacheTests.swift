import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Developer Junk's npm cache rule: `npm cache clean --force`, run through the safety pipeline against a fake `npm`
/// inside the fixture root (DEV-R07, DEV-002, DEV-003, DEV-004, SAF-010).
struct NpmCacheTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let cache = ".npm/_cacache"

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

    @Test func itIsOneSelectedToolItemSizedFromTheCacheFolderDEVR07DEV003() async throws {
        let npm = try root.tool("opt/homebrew/bin/npm", .reportsInvocation)
        try root.file("\(cache)/content-v2/sha512/ab/cd", size: 20_000)
        try root.file("\(cache)/index-v5/ef/gh", size: 10_000)

        let items = await scanned()

        let item = try #require(items.first)
        #expect(items.count == 1)
        let rule = try #require(item.ruleMatch?.rule)
        #expect(rule.id == "DEV-R07" && rule.detection == .executable(npm.path))
        #expect(item.tier == .rebuildable && item.method == .tool && item.selection == .selected)
        #expect(item.category.id == "packages" && item.apps.isEmpty)
        guard case .command(let command) = item.target else {
            Issue.record("Not a command: \(item.target)")
            return
        }
        #expect(command.executable == npm.path)
        #expect(command.arguments == ["cache", "clean", "--force"])
        // PATH and HOME, and the two settings that keep npm off the network (DEV-004, NFR-SEC-001).
        #expect(command.environment.count == 4 && command.environment.values.contains(root.url.path))
        #expect(command.environment["NPM_CONFIG_UPDATE_NOTIFIER"] == "false")
        #expect(command.environment["NPM_CONFIG_OFFLINE"] == "true")
        // The estimate is the measured folder: at least the files' sizes, an upper bound for what npm removes.
        #expect(item.allocatedSize >= 30_000)
        // Scanning never starts a tool (R-07).
        #expect(!root.aFakeToolRan)
    }

    @Test func aMacWithoutNpmOrItsCacheListsNothingDEV002() async throws {
        try root.file("\(cache)/content-v2/x", size: 100)
        #expect(await scanned().isEmpty, "Listed without npm")

        let other = try FixtureRoot()
        try other.tool("opt/homebrew/bin/npm", .exits(0))
        let context = ScanContext(
            home: other.url, protection: other.pathGuardConfiguration(), toolRoot: other.url)
        #expect(await items(from: DeveloperJunk(), context: context).isEmpty, "Listed without a cache")
    }

    @Test func npmIsFoundInTheSecondFolderWhenTheFirstHasNoneDEV002() async throws {
        let npm = try root.tool("usr/local/bin/npm", .exits(0))
        try root.file("\(cache)/content-v2/x", size: 100)

        let rule = try #require(await scanned().first?.ruleMatch?.rule)

        #expect(rule.detection == .executable(npm.path))
    }

    @Test func itRunsNpmsOwnCommandAndShuckDeletesNoFileSAF010DEV004() async throws {
        try root.tool("opt/homebrew/bin/npm", .reportsInvocation)
        let file = try root.file("\(cache)/content-v2/x", size: 5000)

        let report = try await run(scanned())

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(root.aFakeToolRan)
        // The fake tool deletes nothing, so the cache is as it was: Shuck deletes no file of the tool's (SAF-010).
        #expect(FileManager.default.fileExists(atPath: file.path))
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.allSatisfy { $0.operation == .tool && $0.tool == .developerJunk && $0.tier == .rebuildable })
        #expect(records.map(\.phase) == [.intent, .result])
        let detail = try #require(records.last?.detail)
        for argument in ["cache", "clean", "--force"] { #expect(detail.contains("arg=\(argument)")) }
        #expect(detail.contains("HOME=\(root.url.path)"))
        #expect(try #require(LoggedCommand(logged: records[0].path)).commandLine == "npm cache clean --force")
        #expect(try HistoryLog.read(folder: root.historyFolder).entries().map(\.restorability) == [.permanent])
    }

    @Test func aFailingNpmIsAFailureWithItsOutputInTheLogDEV004SAF011() async throws {
        try root.tool("opt/homebrew/bin/npm", .exits(1, output: "npm error code EACCES"))
        try root.file("\(cache)/content-v2/x", size: 100)

        let report = try await run(scanned())

        #expect(
            report.outcomes.map(\.result) == [
                .failed(ActionError(domain: "ShuckToolExit", code: 1, message: "exit status 1"))
            ])
        let item = try #require(try HistoryLog.read(folder: root.historyFolder).runs().first?.items.first)
        #expect(item.toolOutput == "npm error code EACCES")
    }
}
