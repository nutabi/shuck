import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Restore, run against a fake Trash inside the fixture root (D-47): items are trashed with the Trash executor first,
/// then put back from what the history log says (HIS-003, HIS-004).
struct RestoreExecutorTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let logFolder: URL
    let trash: FakeTrash

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        logFolder = HistoryLog.folder(home: root.url, bundleID: ShuckKit.bundleID)
        trash = FakeTrash(folder: root.url.appending(path: ".Trash"))
    }

    /// Trashes `urls` with the Trash executor and returns them as the history log now lists them.
    private func trashed(_ urls: [URL]) async throws -> [TrashedItem] {
        let items = try urls.map { url in
            PlannedItem(url: url, tier: .yourData, method: .trash, snapshot: try #require(ItemSnapshot.read(url)))
        }
        let plan = try Plan(tool: .largeFiles, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
        _ = await TrashExecutor(pathGuard: pathGuard, log: try HistoryLog(folder: logFolder), trash: trash).run(plan)
        return try restorable()
    }

    /// The items the history log lists as restorable.
    private func restorable() throws -> [TrashedItem] {
        try HistoryLog.read(folder: logFolder).entries().compactMap { entry in
            guard case .restorable(let item) = entry.restorability else { return nil }
            return item
        }
    }

    private func restore(_ requests: [RestoreRequest]) async throws -> [RestoreOutcome.Result] {
        let executor = RestoreExecutor(pathGuard: pathGuard, log: try HistoryLog(folder: logFolder), trash: trash)
        return await executor.run(requests).outcomes.map(\.result)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func restoreRecords() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: logFolder).records.filter { $0.operation == .restore }
    }

    // MARK: - Restoring

    @Test func putsItemsBackWhereTheyWereAndLogsItHIS003() async throws {
        let movie = try root.file("Movies/clip.mov", size: 50_000)
        let package = try root.folder("Documents/Old.pages")
        try root.file("Documents/Old.pages/Index.zip", size: 8_000)
        let items = try await trashed([movie, package])
        #expect(items.count == 2 && !exists(movie) && !exists(package))

        let results = try await restore(items.map { RestoreRequest(item: $0) })

        #expect(results == [.restored(movie), .restored(package)])
        let inside = try root.url("Documents/Old.pages/Index.zip")
        #expect(exists(movie) && exists(inside))
        #expect(items.allSatisfy { !exists($0.trashedURL) })
        let records = try restoreRecords()
        #expect(records.map(\.phase) == [.intent, .result, .intent, .result])
        #expect(records.map(\.path) == [movie, movie, package, package].map(\.path))
        #expect(records.map(\.trashedPath) == items.flatMap { [$0.trashedURL.path, $0.trashedURL.path] })
        #expect(records.allSatisfy { $0.tool == .history && $0.tier == .yourData })
        #expect(records.compactMap(\.status) == [.ok, .ok])
        #expect(try HistoryLog.read(folder: logFolder).entries().map(\.restorability) == [.restored, .restored])
    }

    @Test func recreatesMissingParentFoldersHIS003() async throws {
        let file = try root.file("Projects/2024/Client/brief.key", size: 1_000)
        let items = try await trashed([file])
        try FileManager.default.removeItem(at: try root.url("Projects"))

        #expect(try await restore(items.map { RestoreRequest(item: $0) }) == [.restored(file)])
        #expect(exists(file))
    }

    @Test func neverOverwritesAnItemAtTheOriginalPathHIS003() async throws {
        let file = try root.file("Downloads/report.pdf", size: 1_000)
        let items = try await trashed([file])
        try root.file("Downloads/report.pdf", size: 3_000)
        let newer = try #require(ItemSnapshot.read(file))
        #expect(try #require(items.first).originalIsTaken)

        #expect(try await restore(items.map { RestoreRequest(item: $0) }) == [.skipped(.originalTaken)])

        #expect(ItemSnapshot.read(file) == newer)
        #expect(exists(try #require(items.first).trashedURL))
        #expect(try restoreRecords().compactMap(\.status) == [.skipped])
        #expect(try restorable() == items)
    }

    @Test func keepBothAddsRestoredToTheNameHIS003() async throws {
        let file = try root.file("Downloads/report.pdf", size: 1_000)
        let folder = try root.folder("Downloads/Photos")
        var items = try await trashed([file, folder])
        try root.file("Downloads/report.pdf")
        try root.folder("Downloads/Photos")
        try root.file("Downloads/report (restored).pdf")
        // A second copy of report.pdf, trashed and then also found taken.
        let copy = try root.file("Documents/report.pdf", size: 1_000)
        items += try await trashed([copy]).filter { $0.originalURL == copy }
        try root.file("Documents/report.pdf")

        let results = try await restore(items.map { RestoreRequest(item: $0, ifTaken: .keepBoth) })

        let expected = [
            "Downloads/report (restored 2).pdf", "Downloads/Photos (restored)", "Documents/report (restored).pdf",
        ]
        #expect(results == (try expected.map { .restored(try root.url($0)) }))
        #expect(try expected.allSatisfy { exists(try root.url($0)) })
        #expect(
            try restoreRecords().filter { $0.phase == .result }.map(\.path)
                == (try expected.map { try root.url($0).path }))
    }

    // MARK: - Not restorable

    @Test func anItemNoLongerInTheTrashIsSkippedHIS004() async throws {
        let file = try root.file("Downloads/report.pdf", size: 1_000)
        let items = try await trashed([file])
        try FileManager.default.removeItem(at: try #require(items.first).trashedURL)

        #expect(try await restore(items.map { RestoreRequest(item: $0) }) == [.skipped(.missing)])
        #expect(!exists(file))
        #expect(try HistoryLog.read(folder: logFolder).entries().map(\.restorability) == [.trashEmptied])
    }

    @Test func anItemThatChangedInTheTrashIsSkippedSAF008() async throws {
        let file = try root.file("Downloads/report.pdf", size: 1_000)
        let item = try #require(try await trashed([file]).first)
        try Data(count: 1_000_000).write(to: item.trashedURL)

        let results = try await restore([RestoreRequest(item: item)])

        guard case .skipped(.changed(let now)) = results.first else {
            Issue.record("Expected the changed item to be skipped: \(results)")
            return
        }
        #expect(now.allocatedSize >= 1_000_000)
        #expect(!exists(file))
    }

    @Test func takesItemsOnlyFromDirectlyInsideTheTrash() async throws {
        // A log entry whose trashed path points at another of the user's files is never acted on.
        let other = try root.file("Documents/keep.txt", size: 100)
        let forged = TrashedItem(
            run: UUID(), tool: .largeFiles, tier: .yourData, originalURL: try root.url("Downloads/keep.txt"),
            trashedURL: other, bytes: nil)
        let nested = try root.file(".Trash/Folder/inner.txt", size: 100)
        let fromFolder = TrashedItem(
            run: UUID(), tool: .largeFiles, tier: .yourData, originalURL: try root.url("Downloads/inner.txt"),
            trashedURL: nested, bytes: nil)

        let results = try await restore([RestoreRequest(item: forged), RestoreRequest(item: fromFolder)])

        #expect(results == [.skipped(.notInTrash), .skipped(.notInTrash)])
        #expect(exists(other) && exists(nested))
    }

    @Test func neverRestoresIntoAProtectedLocationSAF007() async throws {
        let inTrash = try root.file(".Trash/id_rsa", size: 100)
        let item = TrashedItem(
            run: UUID(), tool: .largeFiles, tier: .yourData, originalURL: try root.url(".ssh/id_rsa"),
            trashedURL: inTrash, bytes: nil)
        let protected = try root.url(".ssh")

        let results = try await restore([RestoreRequest(item: item)])

        #expect(
            results == [
                .skipped(
                    .rejected(.protectedLocation(protected.appending(path: "id_rsa").path, protected: protected.path)))
            ])
        #expect(exists(inTrash) && !exists(protected))
    }

    // MARK: - Cancellation

    @Test func cancellingStopsBeforeTheNextItemSAF014() async throws {
        let files = try (1...3).map { try root.file("Downloads/file\($0).bin", size: 10) }
        let items = try await trashed(files)
        let executor = RestoreExecutor(pathGuard: pathGuard, log: try HistoryLog(folder: logFolder), trash: trash)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await executor.run(items.map { RestoreRequest(item: $0) })
        }
        let report = await task.value

        #expect(report.outcomes.map(\.result) == Array(repeating: .skipped(.cancelled), count: 3))
        #expect(files.allSatisfy { !exists($0) })
        #expect(try restoreRecords().isEmpty)
    }
}
