import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The Trash executor, run against a fake Trash inside the fixture root (D-47).
struct TrashExecutorTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let logFolder: URL
    let trashFolder: URL

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        logFolder = HistoryLog.folder(home: root.url)
        trashFolder = root.url.appending(path: ".Trash")
    }

    private func planned(_ url: URL, tier: Tier = .yourData, method: ActionMethod = .trash) throws -> PlannedItem {
        PlannedItem(url: url, tier: tier, method: method, snapshot: try #require(ItemSnapshot.read(url)))
    }

    private func plan(_ items: [PlannedItem]) throws -> Plan {
        try Plan(tool: .largeFiles, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
    }

    private func run(_ plan: Plan, beforeMove: @escaping @Sendable (URL) throws -> Void = { _ in }) async throws
        -> RunReport
    {
        let executor = TrashExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: logFolder),
            trash: FakeTrash(folder: trashFolder, beforeMove: beforeMove))
        return await executor.run(plan)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Trashing and logging

    @Test func trashesEveryItemAndLogsWhereItWentSAF005() async throws {
        let movie = try root.file("Movies/clip.mov", size: 50_000)
        let image = try root.file("Downloads/installer.dmg", size: 20_000)
        let package = try root.folder("Documents/Old.pages")
        try root.file("Documents/Old.pages/Index.zip", size: 8_000)
        let plan = try plan([planned(movie), planned(image), planned(package)])

        let report = try await run(plan)

        #expect(report.run == plan.run)
        #expect(report.outcomes.map(\.item) == plan.items)
        let records = try HistoryLog.read(folder: logFolder).records
        #expect(records.map(\.phase) == [.intent, .result, .intent, .result, .intent, .result])
        for (outcome, result) in zip(report.outcomes, records.filter { $0.phase == .result }) {
            guard case .trashed(let trashed) = outcome.result else {
                Issue.record("Not trashed: \(outcome)")
                continue
            }
            #expect(!exists(outcome.item.url))
            #expect(exists(trashed))
            #expect(result.status == .ok)
            #expect(result.path == outcome.item.url.path)
            #expect(result.trashedPath == trashed.path)
            #expect(result.bytes == outcome.item.snapshot.allocatedSize)
            #expect(result.run == plan.run && result.tool == .largeFiles && result.tier == .yourData)
        }
    }

    @Test func aNameAlreadyInTheTrashIsLoggedWithItsNewNameSAF005() async throws {
        let first = try root.file("Downloads/report.pdf", size: 10)
        let second = try root.file("Documents/report.pdf", size: 10)
        let report = try await run(try plan([planned(first), planned(second)]))

        let trashedPaths = try HistoryLog.read(folder: logFolder).records.compactMap(\.trashedPath)
        #expect(trashedPaths == [".Trash/report.pdf", ".Trash/report 2.pdf"].map { root.url.appending(path: $0).path })
        #expect(report.outcomes.map(\.result) == trashedPaths.map { .trashed(URL(filePath: $0)) })
    }

    // MARK: - Re-validation

    @Test func skipsItemsThatChangedSinceTheScanSAF008() async throws {
        let gone = try root.file("Downloads/gone.zip", size: 10_000)
        let grown = try root.file("Downloads/grown.log", size: 10_000)
        let replaced = try root.file("Downloads/replaced.dat", size: 10_000)
        let unchanged = try root.file("Downloads/unchanged.iso", size: 10_000)
        let plan = try plan([planned(gone), planned(grown), planned(replaced), planned(unchanged)])

        try FileManager.default.removeItem(at: gone)
        try Data(count: 1_000_000).write(to: grown)
        try FileManager.default.removeItem(at: replaced)
        try root.folder("Downloads/replaced.dat")

        let report = try await run(plan)

        let results = report.outcomes.map(\.result)
        #expect(results[0] == .skipped(.missing))
        guard case .skipped(.changed(let grownNow)) = results[1], case .skipped(.changed(let replacedNow)) = results[2]
        else {
            Issue.record("Expected the changed items to be skipped: \(results)")
            return
        }
        #expect(grownNow.kind == .file && grownNow.allocatedSize >= 1_000_000)
        #expect(replacedNow.kind == .folder)
        guard case .trashed = results[3] else {
            Issue.record("The unchanged item was not trashed: \(results[3])")
            return
        }
        #expect(exists(grown) && exists(replaced))
        let statuses = try HistoryLog.read(folder: logFolder).records.compactMap(\.status)
        #expect(statuses == [.skipped, .skipped, .skipped, .ok])
    }

    @Test func skipsAnItemTheGuardRejectsAtRunTimeSAF008() async throws {
        // Between plan and run, Downloads is swapped for a symlink to a look-alike outside the root.
        let other = try FixtureRoot()
        let lookalike = try other.file("installer.dmg", size: 10_000)
        let installer = try root.file("Downloads/installer.dmg", size: 10_000)
        let plan = try plan([planned(installer)])
        try FileManager.default.moveItem(at: root.url("Downloads"), to: root.url("Moved"))
        try root.symlink("Downloads", to: other.url)

        let report = try await run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.rejected(.outsideAllowedRoots(lookalike.path)))])
        #expect(exists(lookalike))
        #expect(exists(try root.url("Moved/installer.dmg")))
    }

    // MARK: - Outcomes

    @Test func everyItemEndsWithAnOutcomeSAF011() async throws {
        let ok = try root.file("Downloads/ok.zip", size: 10)
        let locked = try root.file("Downloads/locked.zip", size: 10)
        let gone = try root.file("Downloads/gone.zip", size: 10)
        let plan = try plan([planned(ok), planned(locked), planned(gone)])
        try FileManager.default.removeItem(at: gone)

        let report = try await run(plan) { url in
            if url.lastPathComponent == "locked.zip" { throw CocoaError(.fileWriteNoPermission) }
        }

        #expect(report.outcomes.count == 3)
        guard case .trashed = report.outcomes[0].result, case .failed = report.outcomes[1].result else {
            Issue.record("Unexpected outcomes: \(report.outcomes.map(\.result))")
            return
        }
        #expect(report.outcomes[2].result == .skipped(.missing))
        #expect(exists(locked))
        let results = try HistoryLog.read(folder: logFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.status) == [.ok, .failed, .skipped])
        #expect(results.allSatisfy { $0.detail != nil || $0.status == .ok })
    }

    @Test func itemsWithAnotherMethodAreSkippedWithoutActingOrLogging() async throws {
        let item = try planned(try root.file("Downloads/image.raw", size: 10), method: .tool)
        let report = try await run(try plan([item]))
        #expect(report.outcomes.map(\.result) == [.skipped(.unsupportedMethod(.tool))])
        #expect(exists(item.url))
        #expect(try HistoryLog.read(folder: logFolder).records.isEmpty)
    }

    // MARK: - Crash and cancellation

    @Test func theLogMatchesTheDiskAtEveryMomentOfARunHIS001() async throws {
        // A kill can happen at any moment. Records are on disk as soon as they are written, so the moment just
        // before each move is the state a kill would leave: intents for every item so far, results for every item
        // before the current one, and those items already in the Trash.
        let files = try (1...4).map { try root.file("Downloads/file\($0).bin", size: 10) }
        let logFolder = logFolder
        let report = try await run(try plan(files.map { try planned($0) })) { url in
            let index = try #require(files.firstIndex(of: url))
            let records = try HistoryLog.read(folder: logFolder).records
            #expect(records.filter { $0.phase == .intent }.map(\.path) == files[...index].map(\.path))
            let results = records.filter { $0.phase == .result }
            #expect(results.map(\.path) == files[..<index].map(\.path))
            for result in results {
                #expect(!FileManager.default.fileExists(atPath: result.path))
                #expect(FileManager.default.fileExists(atPath: try #require(result.trashedPath)))
            }
            #expect(files[index...].allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
        #expect(report.outcomes.count == 4)
    }

    @Test func cancellingStopsBeforeTheNextItemSAF014() async throws {
        let files = try (1...4).map { try root.file("Downloads/file\($0).bin", size: 10) }
        let report = try await run(try plan(files.map { try planned($0) })) { url in
            if url.lastPathComponent == "file2.bin" { withUnsafeCurrentTask { $0?.cancel() } }
        }

        #expect(report.outcomes[2...].map(\.result) == [.skipped(.cancelled), .skipped(.cancelled)])
        #expect(!exists(files[0]) && !exists(files[1]))
        #expect(exists(files[2]) && exists(files[3]))
        let records = try HistoryLog.read(folder: logFolder).records
        #expect(Set(records.map(\.path)) == Set(files[..<2].map(\.path)))
        #expect(records.filter { $0.phase == .result }.map(\.status) == [.ok, .ok])
    }
}
