import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Caches & Logs items go through the whole safety pipeline: scan, plan, Delete of a folder's contents, log
/// (CAC-004, SAF-004 to SAF-009).
struct CachesAndLogsPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let longAgo = Date.now.addingTimeInterval(-40 * 86_400)
    /// The apps this Mac is taken to have: a cache whose app is unknown is never selected (CAC-009).
    let names = StubAppNames(["com.example.Notes": "Notes", "com.example.Mail": "Mail", "com.example.Recent": "Recent"])

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func scanned(running: Set<String> = []) async -> [ScanItem] {
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running))
        return await items(from: CachesAndLogs(appNames: names), context: context)
    }

    private func plan(_ items: [ScanItem]) throws -> Plan {
        try Plan(subTool: CachesAndLogs(appNames: names), items: items, pathGuard: pathGuard)
    }

    @discardableResult
    private func staleFolder(_ path: String) throws -> URL {
        try root.file("\(path)/data.db", size: 4096, modified: longAgo)
        try root.file("\(path)/sub/more.db", size: 4096, modified: longAgo)
        // Creating a file changes its folder's date, so the folders' dates are set last.
        let folder = try root.url(path)
        for url in [folder.appending(path: "sub"), folder] {
            try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: url.path)
        }
        return folder
    }

    @Test func aCacheKeepsItsFolderAndLosesItsContentsCAC004() async throws {
        let cache = try staleFolder("Library/Caches/com.example.Notes")
        let container = try staleFolder("Library/Containers/com.example.Mail/Data/Library/Caches")
        let recent = try root.file("Library/Caches/com.example.Recent/data.db", size: 4096)

        let selected = await scanned().filter { $0.selection == .selected }
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan(selected))

        #expect(selected.count == 2)
        #expect(report.outcomes.map(\.result) == [.done(nil), .done(nil)])
        for folder in [cache, container] {
            #expect(FileManager.default.fileExists(atPath: folder.path), "The folder stays, as the app expects it")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
        #expect(FileManager.default.fileExists(atPath: recent.path))
        let history = try HistoryLog.read(folder: root.historyFolder)
        let results = history.records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.cachesAndLogs, .cachesAndLogs])
        #expect(results.allSatisfy { $0.operation == .delete && $0.tier == .rebuildable && $0.status == .ok })
        #expect(history.entries().map(\.restorability) == [.permanent, .permanent])
    }

    @Test func staleLogsAreDeletedAndRecentOnesStayCAC005() async throws {
        let old = try root.file("Library/Logs/old.log", size: 4096, modified: longAgo)
        let recent = try root.file("Library/Logs/new.log", size: 4096)
        let folder = try staleFolder("Library/Logs/Tool")

        let selected = await scanned().filter { $0.selection == .selected }
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan(selected))

        #expect(report.outcomes.map(\.result) == [.done(nil), .done(nil)])
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        // The log folder stays, with nothing in it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.url.appending(path: "Library/Logs").path))
    }

    @Test func anAppStartingAfterTheScanSkipsItsCacheSAF009() async throws {
        let cache = try staleFolder("Library/Caches/com.example.Notes")
        let plan = try await plan(scanned())

        let report = await
            (try PlanExecutor(root: root, pathGuard: pathGuard, runningApps: StubRunningApps(["com.example.notes"])))
            .run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.appRunning)])
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "data.db").path))
    }

    @Test func aDisabledCacheCannotBePlannedWhileItsAppRunsSAF009CAC003() async throws {
        try staleFolder("Library/Caches/com.example.Notes")
        let items = await scanned(running: ["com.example.Notes"])
        #expect(throws: PlanError.self) { try self.plan(items) }
    }

    @Test func aCacheUsedAgainAfterTheScanIsSkippedSAF008() async throws {
        let cache = try staleFolder("Library/Caches/com.example.Notes")
        let plan = try await plan(scanned())
        // The app wrote a new file, which changes the folder's own date.
        try root.file("Library/Caches/com.example.Notes/new.db", size: 10)

        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.modifiedSinceScan)])
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "data.db").path))
    }

    @Test func dockersContainerCachesCannotBePlannedByAnySubToolDEV007() throws {
        let folder = try staleFolder("Library/Containers/com.docker.docker/Data/Library/Caches")
        let item = ScanItem(
            url: folder, snapshot: try #require(ItemSnapshot.read(folder)), tier: .rebuildable, method: .delete,
            reason: "Not a rule's target", source: .cachesAndLogs, scope: .contents, selection: .selected)

        #expect(throws: PlanError.self) { try self.plan([item]) }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "data.db").path))
    }

    @Test func aFolderOutsideTheSubToolsRootsCannotBePlannedCAC008SAF007() throws {
        let folder = try staleFolder("Library/Application Support/Notes")
        let item = ScanItem(
            url: folder, snapshot: try #require(ItemSnapshot.read(folder)), tier: .rebuildable, method: .delete,
            reason: "Not a rule's target", source: .cachesAndLogs, scope: .contents, selection: .selected)

        #expect(throws: PlanError.self) { try self.plan([item]) }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "data.db").path))
    }
}
