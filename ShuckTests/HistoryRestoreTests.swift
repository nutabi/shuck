import Foundation
import ShuckExecution
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// Restore from the History page: the one question for taken paths, the run and the reload (HIS-003, SAF-011).
///
/// The run is a stub, so these tests never move a file. Only the check for a taken path reads the disk: an item whose
/// original path is the test bundle's app counts as taken, and one under `/StubHome` does not. The engine's fixture
/// tests restore real files (`RestoreExecutorTests`).
@MainActor
struct HistoryRestoreTests {
    let home = URL(filePath: "/StubHome", directoryHint: .isDirectory)
    let empty = HistoryModel.History(runs: [], unreadableLineCount: 0)

    func trashed(_ original: URL) -> TrashedItem {
        TrashedItem(
            run: UUID(), tool: .largeFiles, tier: .yourData, originalURL: original,
            trashedURL: home.appending(path: ".Trash/\(original.lastPathComponent)"), bytes: 100)
    }

    /// What the stubs were asked to do.
    final class Calls: Sendable {
        let requests = Mutex<[RestoreRequest]>([])
        let loads = Mutex(0)
    }

    /// A model whose restores record their requests in `calls`, restore everything, and count the reloads.
    func model(_ calls: Calls) -> HistoryModel {
        let empty = empty
        return HistoryModel(home: home) { () async throws(HistoryError) -> HistoryModel.History in
            calls.loads.withLock { $0 += 1 }
            return empty
        } runRestore: { (batch: [RestoreRequest]) async throws(HistoryError) -> RestoreReport in
            calls.requests.withLock { $0 += batch }
            return RestoreReport(
                run: UUID(),
                outcomes: batch.map { RestoreOutcome(request: $0, result: .done($0.item.originalURL)) })
        }
    }

    @Test func withoutATakenPathTheRestoreStartsAtOnceAndReloadsHIS003() async throws {
        let calls = Calls()
        let model = model(calls)
        let items = [trashed(home.appending(path: "Movies/big.mov")), trashed(home.appending(path: "Movies/clip.mov"))]

        let restore = try #require(model.restore(items))
        #expect(restore.takenItems.isEmpty)
        #expect(restore.totalBytes == 200)
        #expect(model.isRestoring)
        await restore.task?.value

        #expect(calls.requests.withLock { $0 } == items.map { RestoreRequest(item: $0, ifTaken: .skip) })
        guard case .finished(let report) = restore.phase else {
            Issue.record("The restore did not finish: \(restore.phase)")
            return
        }
        #expect(report.outcomes.count == 2)
        #expect(calls.loads.withLock { $0 } == 1, "History did not reload after the restore")
        #expect(!model.isRestoring)
        model.dismissRestore()
        #expect(model.restore == nil)
    }

    /// HIS-003: when some original paths are taken, nothing moves until one answer, which applies to every item.
    @Test func takenPathsWaitForOneAnswerForAllOfThemHIS003() async throws {
        let calls = Calls()
        let model = model(calls)
        let taken = trashed(Bundle.main.bundleURL)
        let free = trashed(home.appending(path: "Movies/clip.mov"))

        let restore = try #require(model.restore([taken, free]))
        #expect(restore.phase == .askingAboutTakenPaths)
        #expect(restore.takenItems == [taken])
        #expect(restore.task == nil)
        #expect(model.restore([free]) == nil, "A second restore started while the first was waiting")

        await restore.start(ifTaken: .keepBoth)?.value
        #expect(calls.requests.withLock { $0 } == [taken, free].map { RestoreRequest(item: $0, ifTaken: .keepBoth) })
        #expect(restore.start(ifTaken: .skip) == nil, "A restore ran twice")
    }

    /// HIS-003: two runs can trash different versions of the same path. Ask before restoring them together, even
    /// when nothing currently occupies that path, and pass either answer to the executor without reordering items.
    @Test(arguments: [RestoreRequest.IfTaken.keepBoth, .skip])
    func repeatedOriginalPathsWaitForAnAnswerHIS003(ifTaken: RestoreRequest.IfTaken) async throws {
        let calls = Calls()
        let model = model(calls)
        let first = trashed(home.appending(path: "Movies/clip.mov"))
        let second = TrashedItem(
            run: UUID(), tool: .largeFiles, tier: .yourData, originalURL: first.originalURL,
            trashedURL: home.appending(path: ".Trash/clip 2.mov"), bytes: 100)

        let restore = try #require(model.restore([first, second]))
        #expect(restore.phase == .askingAboutTakenPaths)
        #expect(restore.takenItems == [second])
        #expect(restore.task == nil)
        #expect(calls.requests.withLock { $0 }.isEmpty)

        await restore.start(ifTaken: ifTaken)?.value
        #expect(calls.requests.withLock { $0 } == [first, second].map { RestoreRequest(item: $0, ifTaken: ifTaken) })
        #expect(calls.loads.withLock { $0 } == 1)
    }

    @Test func cancellingTheQuestionMovesNothingHIS003() {
        let calls = Calls()
        let model = model(calls)

        model.restore([trashed(Bundle.main.bundleURL)])
        model.dismissRestore()
        #expect(model.restore == nil)
        #expect(calls.requests.withLock { $0 }.isEmpty)
    }

    /// SAF-005: if the history log cannot be opened, nothing moves and the restore says why.
    @Test func aRestoreWhoseLogCannotOpenFailsSAF005() async throws {
        let failure = HistoryError.cannotOpen("/StubHome/Library/Application Support/me.nutabi.shuck.debug", errno: 13)
        let empty = empty
        let model = HistoryModel(home: home) { () async throws(HistoryError) -> HistoryModel.History in
            empty
        } runRestore: { (_: [RestoreRequest]) async throws(HistoryError) -> RestoreReport in
            throw failure
        }

        let restore = try #require(model.restore([trashed(home.appending(path: "Movies/clip.mov"))]))
        await restore.task?.value
        #expect(restore.phase == .failed(failure))
    }

    @Test func aModelWithoutARunOffersNoRestore() {
        let empty = empty
        let model = HistoryModel(home: home) { () async throws(HistoryError) -> HistoryModel.History in empty }

        #expect(!model.canRestore)
        #expect(model.restore([trashed(home.appending(path: "Movies/clip.mov"))]) == nil)
        #expect(model.restore == nil)
    }

    /// HIS-004: only items still in the Trash can be restored.
    @Test func restorableItemsAreTheOnesStillInTheTrashHIS004() {
        let inTrash = trashed(home.appending(path: "Movies/big.mov"))
        let items = [
            Restorability.restorable(inTrash), .trashEmptied, .restored, .notAccessible,
        ].map { restorability in
            HistoryRun.Item(
                operation: .trash, path: "/StubHome/Movies/x.mov", trashedPath: nil, bytes: 100, tier: .yourData,
                outcome: .succeeded,
                restorability: restorability)
        }
        let run = HistoryRun(id: UUID(), tool: .largeFiles, started: .now, items: items)

        #expect(run.restorableItems == [inTrash])
    }

    /// HIS-003: Restore acts on the selected items still in the Trash, in the page's order.
    @Test func theSelectionRestoresItsItemsStillInTheTrashHIS003() {
        let first = trashed(home.appending(path: "Movies/big.mov"))
        let second = trashed(home.appending(path: "Movies/clip.mov"))
        let runs = [[second, first], [trashed(home.appending(path: "Movies/other.mov"))]].map { items in
            HistoryRun(
                id: UUID(), tool: .largeFiles, started: .now,
                items: items.map { item in
                    HistoryRun.Item(
                        operation: .trash, path: item.originalURL.path, trashedPath: item.trashedURL.path, bytes: 100,
                        tier: .yourData,
                        outcome: .succeeded, restorability: .restorable(item))
                })
        }
        let history = HistoryModel.History(runs: runs, unreadableLineCount: 0)
        let elsewhere = URL(filePath: "/StubHome/.Trash/gone.mov")

        let selected = HistoryView.items([first.trashedURL, second.trashedURL, elsewhere], in: history)
        #expect(selected == [second, first])
        #expect(HistoryView.items([], in: history).isEmpty)
    }

    /// SAF-011: the summary says what happened to every item, in words.
    @Test func theSummarySaysWhatHappenedToEachItemSAF011() {
        let item = trashed(home.appending(path: "Movies/clip.mov"))
        func text(_ result: RestoreOutcome.Result) -> String {
            String(
                localized: HistoryRestoreSheet.outcome(
                    RestoreOutcome(request: RestoreRequest(item: item, ifTaken: .keepBoth), result: result)))
        }

        #expect(text(.done(item.originalURL)) == "Restored")
        #expect(
            text(.done(home.appending(path: "Movies/clip (restored).mov")))
                == "Restored as “clip (restored).mov”")
        #expect(text(.skipped(.originalTaken)) == "Skipped: its original place is taken")
        #expect(text(.skipped(.missing)) == "Skipped: no longer in the Trash")
        #expect(text(.skipped(.notAccessible)) == "Skipped: not accessible")
        #expect(text(.skipped(.otherItem)) == "Skipped: no longer in the Trash, and another item has its name")
        #expect(text(.skipped(.cancelled)) == "Skipped: stopped before it was restored")
        #expect(text(.failed(ActionError(errno: EACCES))) == "Failed: Permission denied")
    }
}
