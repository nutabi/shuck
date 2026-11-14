import Foundation
import ShuckExecution
import ShuckKit
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
    func scannedModel(
        runPlan: @escaping RunPlan, readFreeSpace: @escaping ReadFreeSpace = { nil }
    ) async -> FileCleanupModel {
        let files = [
            ("Movies/big.mov", 5_000, nil), ("Movies/clip.mov", 3_000, nil), ("Documents/note.txt", 10, nil),
            ("go/pkg/mod", 9_000, ReadOnlyReason.managedBy(.developerJunk)),
        ].map { path, size, readOnly in
            PersonalFile(
                url: url(path), snapshot: ItemSnapshot(kind: .file, allocatedSize: Int64(size)), modified: yearsAgo,
                lastOpened: LastOpened(date: yearsAgo, source: .modified), readOnly: readOnly,
                isSynced: path == "Movies/clip.mov")
        }
        let scan: FileCleanupModel.PersonalFilesScan = { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                continuation.finish()
            }
        }
        let model = FileCleanupModel(
            subTools: [largeFiles, oldFiles], context: context, personalFilesScan: scan, runPlan: runPlan,
            readFreeSpace: readFreeSpace)
        await model.scan(largeFiles.id)?.value
        return model
    }

    /// A run that moves the items named in `trashed` and skips the others as changed.
    func run(trashing trashed: Set<String>) -> RunPlan {
        { (plan: Plan) async throws(HistoryError) -> RunReport in
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

    /// Scan, review, run: the plan holds the selected items in order without read-only ones, names the synced ones,
    /// moved items leave both lists and the estimates, and the change in free space is compared with nothing. Moving to
    /// the Trash expects to free nothing; the summary says the space comes back when the Trash is emptied.
    @Test func scanReviewAndRunUpdateTheListsAndMeasureFreeSpaceSAF002SAF011SAF013FCL006() async throws {
        let readings = FreeSpaceReadings([10_000_000_000, 10_000_000_000 - 2_000])
        let model = await scannedModel(runPlan: run(trashing: ["big.mov"]), readFreeSpace: readings.read)
        let rows = try #require(model.personalFilesResults[.largeFiles]?.rows)
        #expect(rows.filter(\.isSynced).map(\.name) == ["clip.mov"])
        let selection = [url("Movies/clip.mov"), url("go/pkg/mod"), url("Movies/big.mov"), url("Documents/note.txt")]

        let review = try #require(try await model.reviewMoveToTrash(largeFiles.id, urls: selection))

        // The note is too small for Large Files, and the Go module cache is read-only (FCL-011).
        #expect(review.plan.tool == .largeFiles)
        #expect(review.plan.items.map(\.url) == [url("Movies/clip.mov"), url("Movies/big.mov")])
        #expect(review.plan.items.allSatisfy { $0.tier == .yourData && $0.method == .trash })
        #expect(review.totalBytes == 8_000)
        #expect(review.phase == .waiting)
        // The review knows which of its items iCloud syncs, so it can mark them and warn (FCL-012, D-129).
        #expect(review.synced == [url("Movies/clip.mov")])
        let other = try #require(try await model.reviewMoveToTrash(oldFiles.id, urls: [url("Movies/big.mov")]))
        #expect(other.synced.isEmpty)

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
        let change = try #require(review.freeSpace)
        #expect(change.measured == -2_000)
        #expect(change.estimate == 0)
        #expect(change.gaps.isEmpty)
    }

    /// A run that cannot open the history log moves nothing (SAF-005), and a stopped run skips every item that has not
    /// started (SAF-014); either way both lists stay as they were.
    @Test func aFailedOrStoppedRunLeavesTheListsAloneSAF005SAF014() async throws {
        let failure = HistoryError.cannotOpen("/StubHome/Library/Application Support/me.nutabi.shuck", errno: EACCES)
        let failed = await scannedModel { (_: Plan) async throws(HistoryError) -> RunReport in throw failure }
        let failedReview = try #require(
            try await failed.reviewMoveToTrash(largeFiles.id, urls: [url("Movies/big.mov")]))

        await failedReview.start()?.value

        #expect(failedReview.phase == .failed(failure))
        #expect(failed.personalFilesResults[.largeFiles]?.rows.count == 3)

        let stopped = await scannedModel { (plan: Plan) async throws(HistoryError) -> RunReport in
            // Only a cancelled run reports its items as cancelled, so a run that is never stopped fails the test.
            let result: ItemOutcome.Result = await waitUntilCancelled() ? .skipped(.cancelled) : .done(nil)
            return RunReport(run: plan.run, outcomes: plan.items.map { ItemOutcome(item: $0, result: result) })
        }
        let review = try #require(
            try await stopped.reviewMoveToTrash(largeFiles.id, urls: [url("Movies/big.mov"), url("Movies/clip.mov")]))

        let task = review.start()
        review.stop()
        await task?.value

        guard case .finished(let report) = review.phase else {
            Issue.record("Not finished: \(review.phase)")
            return
        }
        #expect(report.outcomes.map(\.result) == [.skipped(.cancelled), .skipped(.cancelled)])
        #expect(stopped.personalFilesResults[.largeFiles]?.rows.count == 3)
    }

    /// Tests and previews give the model no run, so nothing in them can move a file.
    @Test func aModelWithoutARunOffersNoReview() async throws {
        let model = FileCleanupModel(subTools: [largeFiles], context: context)
        #expect(!model.canRun)
        #expect(try await model.reviewMoveToTrash(largeFiles.id, urls: [url("Movies/big.mov")]) == nil)
    }
}
