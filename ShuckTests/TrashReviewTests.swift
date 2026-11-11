import Foundation
import ShuckExecution
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// "Move to Trash" from a personal-files list: the plan, the run and the removal of moved items (SAF-002, SAF-011,
/// FCL-006).
///
/// The scan and the run are stubs, so these tests never touch the file system. The engine's fixture tests move real
/// files (`LargeFilesPipelineTests`, `OldFilesPipelineTests`).
@MainActor
struct TrashReviewTests {
    let context = ScanContext(home: URL(filePath: "/StubHome", directoryHint: .isDirectory))
    let largeFiles = LargeFiles(minimumSize: 1_000)
    let oldFiles = OldFiles(minimumSize: 0) { _ in nil }
    let yearsAgo = Date.now.addingTimeInterval(-3 * 365 * 86_400)

    func url(_ path: String) -> URL { context.home.appending(path: path) }

    /// A model whose scan found two large old movies, the clip synced by iCloud, a small old note and a read-only folder,
    /// and whose runs go to `runPlan`.
    func scannedModel(runPlan: @escaping RunPlan) async -> FileCleanupModel {
        let files = [
            ("Movies/big.mov", 5_000, nil), ("Movies/clip.mov", 3_000, nil), ("Documents/note.txt", 10, nil),
            ("go/pkg/mod", 9_000, ReadOnlyReason.managedBy(.developerJunk)),
        ].map { path, size, readOnly in
            PersonalFile(
                url: url(path), snapshot: ItemSnapshot(kind: .file, allocatedSize: Int64(size)), modified: yearsAgo,
                readOnly: readOnly, isSynced: path == "Movies/clip.mov")
        }
        let scan: FileCleanupModel.PersonalFilesScan = { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                continuation.finish()
            }
        }
        let model = FileCleanupModel(
            subTools: [largeFiles, oldFiles], context: context, personalFilesScan: scan, runPlan: runPlan)
        await model.scan(largeFiles)?.value
        return model
    }

    /// A run that moves the items named in `trashed` and skips the others as changed.
    func run(trashing trashed: Set<String>, onCall: @escaping @Sendable () -> Void = {}) -> RunPlan {
        { (plan: Plan) async throws(HistoryError) -> RunReport in
            onCall()
            let outcomes = plan.items.map { item in
                guard let url = item.url, let snapshot = item.snapshot else {
                    Issue.record("A Trash review must have file targets")
                    return ItemOutcome(item: item, result: .skipped(.unsupportedMethod(item.method)))
                }
                return trashed.contains(url.lastPathComponent)
                    ? ItemOutcome(
                        item: item, result: .done(URL(filePath: "/StubHome/.Trash/\(url.lastPathComponent)")))
                    : ItemOutcome(item: item, result: .skipped(.changed(snapshot)))
            }
            return RunReport(run: plan.run, outcomes: outcomes)
        }
    }

    @Test func thePlanHoldsTheSelectedItemsInOrderWithoutReadOnlyOnesSAF002() async throws {
        let model = await scannedModel(runPlan: run(trashing: []))
        let selection = [url("Movies/clip.mov"), url("go/pkg/mod"), url("Movies/big.mov"), url("Documents/note.txt")]

        let review = try #require(try model.reviewMoveToTrash(largeFiles, urls: selection))

        // The note is too small for Large Files, and the Go module cache is read-only (FCL-011).
        #expect(review.plan.tool == .largeFiles)
        #expect(review.plan.items.map(\.url) == [url("Movies/clip.mov"), url("Movies/big.mov")])
        #expect(review.plan.items.allSatisfy { $0.tier == .yourData && $0.method == .trash })
        #expect(review.totalBytes == 8_000)
        #expect(review.phase == .waiting)
    }

    /// The review knows which of its items iCloud syncs, so it can mark them and warn (SAF-002, FCL-012, D-129).
    @Test func theReviewNamesItsSyncedItemsSAF002() async throws {
        let model = await scannedModel(runPlan: run(trashing: []))
        let rows = try #require(model.personalFilesResults[.largeFiles]?.rows)
        #expect(rows.filter(\.isSynced).map(\.name) == ["clip.mov"])

        let both = try #require(
            try model.reviewMoveToTrash(largeFiles, urls: [url("Movies/big.mov"), url("Movies/clip.mov")]))
        #expect(both.synced == [url("Movies/clip.mov")])
        let one = try #require(try model.reviewMoveToTrash(largeFiles, urls: [url("Movies/big.mov")]))
        #expect(one.synced.isEmpty)
    }

    @Test func movedItemsLeaveBothListsAndTheEstimatesFCL006SAF011() async throws {
        let model = await scannedModel(runPlan: run(trashing: ["big.mov"]))
        let review = try #require(
            try model.reviewMoveToTrash(oldFiles, urls: [url("Movies/big.mov"), url("Movies/clip.mov")]))

        await review.start()?.value

        guard case .finished(let report) = review.phase else {
            Issue.record("Not finished: \(review.phase)")
            return
        }
        #expect(report.trashedURLs == [url("Movies/big.mov")])
        // The skipped clip stays listed in both sub-tools.
        #expect(model.personalFilesResults[.largeFiles]?.rows.map(\.name) == ["mod", "clip.mov"])
        #expect(model.personalFilesResults[.oldFiles]?.rows.map(\.name).contains("big.mov") == false)
        #expect(model.personalFilesResults[.oldFiles]?.rows.map(\.name).contains("clip.mov") == true)
        #expect(model.personalFiles.items[url("Movies/big.mov")] == nil)
        guard case .scanned(let summary) = model.state(of: .largeFiles) else {
            Issue.record("Large Files lost its scan")
            return
        }
        #expect(summary.reclaimableBytes == 3_000)
    }

    @Test func aReviewRunsOnce() async throws {
        let calls = Mutex(0)
        let model = await scannedModel(runPlan: run(trashing: []) { calls.withLock { $0 += 1 } })
        let review = try #require(try model.reviewMoveToTrash(largeFiles, urls: [url("Movies/big.mov")]))

        let first = review.start()
        #expect(review.phase == .running)
        #expect(review.start() == nil)
        await first?.value
        #expect(review.start() == nil)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func withoutAHistoryLogNothingMovesSAF005() async throws {
        let failure = HistoryError.cannotOpen("/StubHome/Library/Application Support/me.nutabi.shuck", errno: EACCES)
        let model = await scannedModel { (_: Plan) async throws(HistoryError) -> RunReport in throw failure }
        let review = try #require(try model.reviewMoveToTrash(largeFiles, urls: [url("Movies/big.mov")]))

        await review.start()?.value

        #expect(review.phase == .failed(failure))
        #expect(model.personalFilesResults[.largeFiles]?.rows.count == 3)
    }

    @Test func stoppingCancelsTheRunBeforeTheNextItemSAF014() async throws {
        let model = await scannedModel { (plan: Plan) async throws(HistoryError) -> RunReport in
            // Like the executor: wait, then skip every item that has not started.
            while !Task.isCancelled { await Task.yield() }
            return RunReport(
                run: plan.run, outcomes: plan.items.map { ItemOutcome(item: $0, result: .skipped(.cancelled)) })
        }
        let review = try #require(
            try model.reviewMoveToTrash(largeFiles, urls: [url("Movies/big.mov"), url("Movies/clip.mov")]))

        let task = review.start()
        review.stop()
        await task?.value

        guard case .finished(let report) = review.phase else {
            Issue.record("Not finished: \(review.phase)")
            return
        }
        #expect(report.outcomes.map(\.result) == [.skipped(.cancelled), .skipped(.cancelled)])
        #expect(model.personalFilesResults[.largeFiles]?.rows.count == 3)
    }

    /// Tests and previews give the model no run, so nothing in them can move a file.
    @Test func aModelWithoutARunOffersNoReview() async throws {
        let model = FileCleanupModel(subTools: [largeFiles], context: context)
        #expect(!model.canRun)
        #expect(try model.reviewMoveToTrash(largeFiles, urls: [url("Movies/big.mov")]) == nil)
    }

    /// SAF-011: the summary says why an item was not moved, in the words History uses for the same code (D-90).
    @Test func theSummarySaysWhyAnItemWasNotMovedSAF011() {
        func text(_ result: ItemOutcome.Result, method: ActionMethod = .trash) -> String {
            let item = PlannedItem(
                url: url("Movies/clip.mov"), tier: .yourData, method: method,
                snapshot: ItemSnapshot(kind: .file, allocatedSize: 10))
            return String(localized: OutcomeWording.result(of: ItemOutcome(item: item, result: result)))
        }

        #expect(text(.skipped(.missing)) == "Skipped: no longer there")
        #expect(text(.skipped(.notAccessible)) == "Skipped: not accessible")
        #expect(
            text(.skipped(.changed(ItemSnapshot(kind: .file, allocatedSize: 20)))) == "Skipped: changed since the scan")
        #expect(text(.skipped(.cancelled)) == "Skipped: stopped before it was acted on")
        #expect(
            text(.skipped(.unsupportedMethod(.tool)), method: .tool) == "Skipped: this version of Shuck can't do this")
        #expect(text(.skipped(.notAllowed(.delete)), method: .delete) == "Skipped: not allowed for this kind of item")
        #expect(text(.failed(ActionError(errno: EACCES))) == "Failed: Permission denied")
        #expect(
            text(.skipped(.missing))
                == String(
                    localized: HistoryView.status(
                        of: HistoryRun.Item(
                            operation: .trash, path: "/StubHome/Movies/clip.mov", trashedPath: nil, bytes: 10,
                            tier: .yourData,
                            outcome: .skipped("missing"), restorability: nil))))
    }
}
