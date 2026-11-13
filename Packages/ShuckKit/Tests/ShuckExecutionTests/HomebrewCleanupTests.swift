import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Developer Junk's Homebrew rule: `brew cleanup`, run through the safety pipeline against a fake `brew` inside the
/// fixture root (DEV-R09, DEV-002, DEV-003, DEV-004, DEV-007, SAF-010).
struct HomebrewCleanupTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let cache = "Library/Caches/Homebrew"
    let cellar = "opt/homebrew/Cellar"

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

    @Test func itIsOneSelectedToolItemSizedFromTheDownloadCacheDEVR09DEV003() async throws {
        let brew = try root.tool("opt/homebrew/bin/brew", .reportsInvocation)
        try root.file("\(cache)/downloads/abc--git-2.47.tar.gz", size: 30_000)

        let items = await scanned()

        let item = try #require(items.first)
        #expect(items.count == 1)
        let rule = try #require(item.ruleMatch?.rule)
        #expect(rule.id == "DEV-R09" && rule.detection == .executable(brew.path))
        #expect(item.tier == .rebuildable && item.method == .tool && item.selection == .selected)
        #expect(item.category.id == "packages" && item.apps.isEmpty)
        guard case .command(let command) = item.target else {
            Issue.record("Not a command: \(item.target)")
            return
        }
        #expect(command.executable == brew.path && command.arguments == ["cleanup"])
        // PATH and the home folder, and no analytics and no automatic update: no connection of its own accord.
        #expect(command.environment.count == 5 && command.environment.values.contains(root.url.path))
        #expect(command.environment["HOMEBREW_NO_ANALYTICS"] == "1")
        #expect(command.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        // No size before the run: the cache is not what the command removes (DEV-R09, DEV-003, D-NEXT-brew-size).
        #expect(item.allocatedSize == 0)
        #expect(!root.aFakeToolRan, "Scanning started a tool")
    }

    @Test func aMacWithoutBrewOrItsCacheListsNothingDEV002() async throws {
        try root.file("\(cache)/downloads/x", size: 100)
        #expect(await scanned().isEmpty, "Listed without Homebrew")

        let other = try FixtureRoot()
        try other.tool("opt/homebrew/bin/brew", .exits(0))
        let context = ScanContext(
            home: other.url, protection: other.pathGuardConfiguration(), toolRoot: other.url)
        #expect(await items(from: DeveloperJunk(), context: context).isEmpty, "Listed without a cache")
    }

    @Test func itRunsBrewsOwnCommandAndNeverTouchesTheCellarSAF010DEV007() async throws {
        try root.tool("opt/homebrew/bin/brew", .reportsInvocation)
        let download = try root.file("\(cache)/downloads/x", size: 5000)
        let keg = try root.file("\(cellar)/git/2.46.0/bin/git", size: 5000)

        let report = try await run(scanned())

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(root.aFakeToolRan)
        // Shuck deletes no file: not the cache, and never the Cellar, which only `brew` may change.
        #expect(FileManager.default.fileExists(atPath: download.path))
        #expect(FileManager.default.fileExists(atPath: keg.path))
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.allSatisfy { $0.operation == .tool && $0.tool == .developerJunk })
        let detail = try #require(records.last?.detail)
        #expect(detail.contains("arg=cleanup") && detail.contains("HOMEBREW_NO_AUTO_UPDATE=1"))
        #expect(try #require(LoggedCommand(logged: records[0].path)).commandLine == "brew cleanup")
        #expect(try HistoryLog.read(folder: root.historyFolder).entries().map(\.restorability) == [.permanent])
    }

    @Test func aFailingBrewIsAFailureWithItsOutputInTheLogDEV004SAF011() async throws {
        try root.tool("opt/homebrew/bin/brew", .exits(1, output: "Error: Permission denied @ apply2files"))
        try root.file("\(cache)/downloads/x", size: 100)

        let report = try await run(scanned())

        #expect(
            report.outcomes.map(\.result) == [
                .failed(ActionError(domain: "ShuckToolExit", code: 1, message: "exit status 1"))
            ])
        let item = try #require(try HistoryLog.read(folder: root.historyFolder).runs().first?.items.first)
        #expect(item.toolOutput == "Error: Permission denied @ apply2files")
    }
}

/// SET-001, SAF-008, D-150: `brew cleanup` is re-checked against every folder it changes just before it runs.
extension HomebrewCleanupTests {
    @Test(arguments: ["opt/homebrew/Cellar", "opt/homebrew/Caskroom/app", "opt/homebrew", "Library/Logs/Homebrew"])
    func brewCleanupIsSkippedWhenAFolderItCleansIsExcludedAfterThePlanSET001SAF008(excluded: String) async throws {
        try root.tool("opt/homebrew/bin/brew", .reportsInvocation)
        try root.file("\(cache)/downloads/x", size: 5000)
        try root.file("\(cellar)/git/2.46.0/bin/git", size: 5000)
        try root.file("opt/homebrew/Caskroom/app/1.0/app", size: 5000)
        try root.file("Library/Logs/Homebrew/log", size: 5000)
        let plan = try Plan(subTool: DeveloperJunk(), items: await scanned(), pathGuard: pathGuard)
        let folder = try root.url(excluded)
        let excluding = PathGuard(configuration: root.pathGuardConfiguration(userExclusions: [folder]))

        let report = try await PlanExecutor(root: root, pathGuard: excluding).run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.userExclusion(folder.path))])
        #expect(!root.aFakeToolRan)
    }
}
