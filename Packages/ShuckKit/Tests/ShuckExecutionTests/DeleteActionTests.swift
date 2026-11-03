import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Permanent deletion of rebuildable items, through the plan executor, so every item is re-validated and logged as it
/// would be in a run (SAF-006 to SAF-008, SAF-011, CAC-004).
struct DeleteActionTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func planned(_ url: URL, scope: ItemScope = .item) throws -> PlannedItem {
        PlannedItem(
            url: url, tier: .rebuildable, method: .delete, snapshot: try #require(ItemSnapshot.read(url)), scope: scope)
    }

    private func plan(_ items: [PlannedItem]) throws -> Plan {
        try Plan(tool: .cachesAndLogs, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
    }

    private func run(_ items: [PlannedItem]) async throws -> RunReport {
        try await run(plan(items))
    }

    private func run(_ plan: Plan) async throws -> RunReport {
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        return await Task { await executor.run(plan) }.value
    }

    private func results() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
    }

    /// Whether anything, a broken symlink included, is at `url`.
    private func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    // MARK: - Deleting

    @Test func deletesFilesAndFoldersAndLogsThemAsNotRestorableSAF006() async throws {
        let log = try root.file("Library/Logs/app.log", size: 10_000)
        let derived = try root.folder("Library/Developer/Xcode/DerivedData/App-abc")
        try root.file("Library/Developer/Xcode/DerivedData/App-abc/Build/Products/App.app/App", size: 20_000)
        try root.file("Library/Developer/Xcode/DerivedData/App-abc/.hidden", size: 10)
        let items = try [planned(log), planned(derived)]

        let report = try await run(items)

        #expect(report.outcomes.map(\.result) == [.done(nil), .done(nil)])
        #expect(!exists(log) && !exists(derived))
        #expect(exists(try root.url("Library/Developer/Xcode/DerivedData")))
        let records = try HistoryLog.read(folder: root.historyFolder).records
        #expect(records.map(\.phase) == [.intent, .result, .intent, .result])
        #expect(records.allSatisfy { $0.operation == .delete && $0.tier == .rebuildable && $0.tool == .cachesAndLogs })
        #expect(records.allSatisfy { $0.trashedPath == nil && $0.identity == nil })
        #expect(try results().map(\.status) == [.ok, .ok])
        #expect(try results().map(\.bytes) == items.map(\.snapshot.allocatedSize))
        // History lists them as done and not restorable (HIS-004).
        let entries = try HistoryLog.read(folder: root.historyFolder).entries()
        #expect(entries.map(\.restorability) == [.permanent, .permanent])
    }

    @Test func aFolderWhoseContentsAreDeletedIsKeptCAC004() async throws {
        let cache = try root.folder("Library/Caches/com.example.app")
        try root.file("Library/Caches/com.example.app/cache.db", size: 10_000)
        try root.file("Library/Caches/com.example.app/fsCachedData/1A2B", size: 10_000)
        try root.file("Library/Caches/com.example.app/.lock", size: 10)

        let report = try await run([planned(cache, scope: .contents)])

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
        #expect(try results().map(\.status) == [.ok])
        #expect(try results().map(\.path) == [cache.path])
    }

    // MARK: - Nothing outside the target (SAF-007)

    @Test func aSymlinkIsDeletedButNotWhatItPointsToSAF007() async throws {
        let destination = try root.file("Library/Caches/real.db", size: 10_000)
        let link = try root.symlink("Library/Caches/link.db", to: destination)

        let report = try await run([planned(link)])

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(!exists(link) && exists(destination))
    }

    @Test func symlinksInsideTheTargetAreRemovedWithoutFollowingThemSAF007() async throws {
        // What the links point to is outside the root, where the guard would never allow a deletion.
        let outside = try FixtureRoot()
        let file = try outside.file("Documents/thesis.pages", size: 10_000)
        let folder = try outside.folder("Projects/App")
        try outside.file("Projects/App/main.swift", size: 10_000)
        let cache = try root.folder("Library/Caches/com.example.app")
        try root.symlink("Library/Caches/com.example.app/file", to: file)
        try root.symlink("Library/Caches/com.example.app/folder", to: folder)
        try root.symlink("Library/Caches/com.example.app/Nested/folder", to: folder)
        let derived = try root.folder("Library/Developer/Xcode/DerivedData/App-abc")
        try root.symlink("Library/Developer/Xcode/DerivedData/App-abc/SourcePackages", to: folder)

        let report = try await run([planned(cache, scope: .contents), planned(derived)])

        #expect(report.outcomes.map(\.result) == [.done(nil), .done(nil)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
        #expect(!exists(derived))
        #expect(try exists(file) && exists(folder) && exists(outside.url("Projects/App/main.swift")))
    }

    // MARK: - Failures and re-validation

    @Test func whatCannotBeDeletedFailsTheItemAndTheRestIsDeletedSAF011() async throws {
        let cache = try root.folder("Library/Caches/com.example.app")
        let removable = try root.file("Library/Caches/com.example.app/a.db", size: 10)
        let locked = try root.folder("Library/Caches/com.example.app/Locked")
        let kept = try root.file("Library/Caches/com.example.app/Locked/b.db", size: 10)
        let later = try root.file("Library/Caches/com.example.app/z.db", size: 10)
        let item = try planned(cache)
        // A folder without write permission keeps what is inside it.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)

        let report = try await run([item])

        let denied = ActionError(errno: EACCES)
        #expect(report.outcomes.map(\.result) == [.failed(denied)])
        #expect(!exists(removable) && !exists(later))
        #expect(exists(kept) && exists(cache))
        #expect(try results().map(\.status) == [.failed])
        #expect(try results().map(\.detail) == [denied.logged])
        #expect(try HistoryLog.read(folder: root.historyFolder).entries().isEmpty)
    }

    @Test func aDeleteItemThatChangedSinceTheScanIsNotDeletedSAF008() async throws {
        let cache = try root.folder("Library/Caches/com.example.app")
        try root.file("Library/Caches/com.example.app/a.db", size: 10_000)
        let gone = try root.file("Library/Logs/gone.log", size: 10)
        let items = try [planned(cache, scope: .contents), planned(gone)]
        try root.file("Library/Caches/com.example.app/big.db", size: 1_000_000)
        try FileManager.default.removeItem(at: gone)

        let report = try await run(items)

        guard case .skipped(.changed) = report.outcomes[0].result else {
            Issue.record("The grown cache was not skipped: \(report.outcomes[0].result)")
            return
        }
        #expect(report.outcomes[1].result == .skipped(.missing))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count == 2)
        #expect(try results().map(\.status) == [.skipped, .skipped])
    }

    @Test func aRebuildableFolderRecreatedSinceTheScanIsStillDeletedSAF008() async throws {
        // Its scan reads no file identity, as Xcode may rebuild a DerivedData folder between scan and run (D-103).
        let derived = try root.folder("Library/Developer/Xcode/DerivedData/App-abc")
        try root.file("Library/Developer/Xcode/DerivedData/App-abc/Build/App", size: 10_000)
        let item = try planned(derived)
        try FileManager.default.removeItem(at: derived)
        try root.file("Library/Developer/Xcode/DerivedData/App-abc/Build/App", size: 10_000)

        let report = try await run([item])

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(!exists(derived))
    }

    @Test func aDeleteItemTheGuardRejectsAtRunTimeIsNotDeletedSAF008() async throws {
        // Between plan and run, Caches is swapped for a symlink to a look-alike outside the root.
        let outside = try FixtureRoot()
        let lookalike = try outside.folder("com.example.app")
        try outside.file("com.example.app/cache.db", size: 10_000)
        let cache = try root.folder("Library/Caches/com.example.app")
        try root.file("Library/Caches/com.example.app/cache.db", size: 10_000)
        let plan = try plan([planned(cache, scope: .contents)])
        try FileManager.default.moveItem(at: root.url("Library/Caches"), to: root.url("Library/Moved"))
        try root.symlink("Library/Caches", to: outside.url)

        let report = try await run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.rejected(.outsideAllowedRoots(lookalike.path)))])
        #expect(exists(try outside.url("com.example.app/cache.db")))
        #expect(exists(try root.url("Library/Moved/com.example.app/cache.db")))
    }

    @Test func yourDataNeverReachesTheDeleteActionSAF004() throws {
        // `Plan` refuses this item, so the test asks the executor to act on it directly.
        let report = try root.file("Documents/report.pdf", size: 10)
        let item = PlannedItem(
            url: report, tier: .yourData, method: .delete, snapshot: try #require(ItemSnapshot.read(report)))
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)

        #expect(executor.act(on: item, allowedRoots: [root.url]).result == .skipped(.notAllowed(.delete)))
        #expect(exists(report))
    }
}
