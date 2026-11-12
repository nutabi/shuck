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
        logFolder = root.historyFolder
        trash = FakeTrash(folder: root.trashFolder)
    }

    /// Trashes `urls` with the Trash executor and returns them as the history log now lists them.
    private func trashed(_ urls: [URL]) async throws -> [TrashedItem] {
        let items = try urls.map { url in
            try root.planned(url, tier: .yourData, method: .trash)
        }
        let plan = try Plan(tool: .largeFiles, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
        _ = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)
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

        #expect(results == [.done(movie), .done(package)])
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

        #expect(try await restore(items.map { RestoreRequest(item: $0) }) == [.done(file)])
        #expect(exists(file))
    }

    @Test func aFailedMoveRemovesTheFoldersItCreatedAndKeepsOldOnesHIS003() async throws {
        let file = try root.file("Projects/old.txt", size: 1_000)
        let items = try await trashed([file])
        let item = try #require(items.first)
        // A name over the 255-byte limit: the folders are created, then the move fails.
        let tooLong = try root.url("Projects/2024/Client/" + String(repeating: "n", count: 300))

        let result = RestoreExecutor(pathGuard: pathGuard, log: try HistoryLog(folder: logFolder), trash: trash)
            .act(on: item, to: tooLong)

        guard case .failed = result else {
            Issue.record("expected a failure, got \(result)")
            return
        }
        #expect(!exists(try root.url("Projects/2024")))
        #expect(exists(try root.url("Projects")))
        #expect(exists(item.trashedURL))
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
        #expect(results == (try expected.map { .done(try root.url($0)) }))
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

    @Test func anItemShuckMayNotReadInTheTrashIsSkippedAsNotAccessibleSAF012() async throws {
        let drafts = try root.folder("Documents/Drafts")
        try root.file("Documents/Drafts/notes.txt", size: 1_000)
        let items = try await trashed([drafts])
        let trashedURL = try #require(items.first).trashedURL
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trashedURL.path)

        #expect(try await restore(items.map { RestoreRequest(item: $0) }) == [.skipped(.notAccessible)])
        #expect(exists(trashedURL) && !exists(drafts))
        #expect(try restoreRecords().compactMap(\.detail) == ["notAccessible"])
    }

    @Test func aTrashNameALaterRunReusedRestoresOnlyTheLaterItemHIS004SAF008() async throws {
        let first = try root.file("Downloads/report.pdf", size: 1_000)
        let earlier = try #require(try await trashed([first]).first)
        // The user empties the Trash, and a later run trashes another report.pdf, which gets the same name.
        let second = try root.file("Documents/report.pdf", size: 1_000)
        try FileManager.default.removeItem(at: earlier.trashedURL)
        let later = try #require(try await trashed([second]).first)
        #expect(later.trashedURL == earlier.trashedURL)
        #expect(try restorable() == [later])
        #expect(
            try HistoryLog.read(folder: logFolder).entries().map(\.restorability) == [
                .trashEmptied, .restorable(later),
            ])

        // A History page read before the later run still offers the earlier item.
        #expect(try await restore([RestoreRequest(item: earlier)]) == [.skipped(.otherItem)])
        #expect(!exists(first) && exists(later.trashedURL))
        #expect(try restoreRecords().compactMap(\.detail) == ["otherItem"])

        #expect(try await restore([RestoreRequest(item: later)]) == [.done(second)])
        #expect(try HistoryLog.read(folder: logFolder).entries().map(\.restorability) == [.trashEmptied, .restored])
    }

    @Test func aSameNamedItemSomeoneElsePutInTheTrashIsNeverRestoredHIS004SAF008() async throws {
        let file = try root.file("Downloads/report.pdf", size: 1_000)
        let item = try #require(try await trashed([file]).first)
        // The Trash is emptied, and another app moves its own report.pdf, of the same size, there.
        let other = try root.file("Desktop/report.pdf", size: 1_000)
        try FileManager.default.removeItem(at: item.trashedURL)
        try FileManager.default.moveItem(at: other, to: item.trashedURL)
        #expect(try restorable().isEmpty)

        #expect(try await restore([RestoreRequest(item: item)]) == [.skipped(.otherItem)])
        #expect(!exists(file) && exists(item.trashedURL))
    }

    @Test func anItemLoggedBeforeARestartThatRenumberedItsVolumeStillRestoresHIS003() async throws {
        let inTrash = try root.file(".Trash/clip.mov", size: 1_000)
        let original = try root.url("Movies/clip.mov")
        let now = try #require(FileIdentity.read(inTrash))
        try await HistoryLog(folder: logFolder).append(
            .result(
                run: UUID(), tool: .largeFiles, operation: .trash, path: original.path, tier: .yourData, status: .ok,
                trashedPath: inTrash.path, identity: FileIdentity(volume: now.volume &+ 1, file: now.file),
                bytes: try #require(ItemSnapshot.read(inTrash)).allocatedSize))
        let item = try #require(try restorable().first)

        #expect(try await restore([RestoreRequest(item: item)]) == [.done(original)])
        #expect(exists(original) && !exists(inTrash))
    }

    @Test func anItemLoggedWithoutAnIdentityAsShuck010LoggedItStillRestoresHIS003() async throws {
        let inTrash = try root.file(".Trash/clip.mov", size: 1_000)
        let original = try root.url("Movies/clip.mov")
        let bytes = try #require(ItemSnapshot.read(inTrash)).allocatedSize
        try await HistoryLog(folder: logFolder).append(
            .result(
                run: UUID(), tool: .largeFiles, operation: .trash, path: original.path, tier: .yourData, status: .ok,
                trashedPath: inTrash.path, bytes: bytes))
        let item = try #require(try restorable().first)
        #expect(item.identity == nil)

        #expect(try await restore([RestoreRequest(item: item)]) == [.done(original)])
        #expect(exists(original) && !exists(inTrash))
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

    /// SET-001: the guard answers a restore into an excluded folder as it answers one into any protected location,
    /// so the item stays in the Trash. Restore keeps that answer (D-149) and logs it as the user's exclusion.
    @Test func neverRestoresIntoAFolderTheUserExcludedSET001SAF007() async throws {
        let original = try root.file("Documents/Keep/report.pdf", size: 100)
        let items = try await trashed([original])
        let keep = try root.url("Documents/Keep")
        let excluding = PathGuard(configuration: root.pathGuardConfiguration(userExclusions: [keep]))
        let executor = RestoreExecutor(pathGuard: excluding, log: try HistoryLog(folder: logFolder), trash: trash)

        let results = await executor.run(items.map { RestoreRequest(item: $0) }).outcomes.map(\.result)

        #expect(results == [.skipped(.userExclusion(keep.path))])
        #expect(!exists(original) && exists(items[0].trashedURL))
        #expect(try restoreRecords().compactMap(\.detail) == ["userExclusion: \(keep.path)"])
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

    // MARK: - Stopping

    @Test func stoppingWhileATrashedFolderIsMeasuredLeavesItInTheTrashSAF014() async throws {
        let package = try root.folder("Documents/Old.pages")
        try root.file("Documents/Old.pages/Index.zip", size: 8_000)
        let item = try #require(try await trashed([package]).first)
        let executor = RestoreExecutor(pathGuard: pathGuard, log: try HistoryLog(folder: logFolder), trash: trash)

        // The task is cancelled when re-validation starts, as when the user clicks Stop while it measures the folder.
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return executor.act(on: item, to: item.originalURL)
        }.value

        #expect(result == .skipped(.cancelled))
        #expect(!exists(package) && exists(item.trashedURL))
    }
}
