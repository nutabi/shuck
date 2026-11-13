import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Synchronization

/// A ``FolderTrash`` inside the fixture root, so tests never touch the real Trash (D-47).
///
/// `beforeMove` runs just before each move, so a test can look at the log and the disk mid-run, cancel the run, or make
/// the move fail by throwing.
struct FakeTrash: Trash {
    let folder: URL
    var beforeMove: @Sendable (URL) throws -> Void = { _ in }

    func trashItem(at url: URL) throws(ActionError) -> URL {
        do {
            try beforeMove(url)
        } catch {
            throw ActionError(error)
        }
        return try FolderTrash(folder: folder).trashItem(at: url)
    }
}

extension PlanExecutor {
    /// An executor for tests in `root`: it writes the root's history log and moves items into its fake Trash, running
    /// `beforeMove` just before each move. No app runs unless `runningApps` says so, and no test reads the real list.
    /// Tools are found only inside the root, as in the app's fixture-root mode (D-114); `toolRunner` can change how
    /// long a stopped tool gets to end.
    init(
        root: FixtureRoot, pathGuard: PathGuard, runningApps: any RunningApps = StubRunningApps(),
        toolRunner: ToolRunner? = nil, beforeMove: @escaping @Sendable (URL) throws -> Void = { _ in }
    ) throws {
        let runner = toolRunner ?? ToolRunner(executableRoots: [root.url])
        self.init(
            pathGuard: pathGuard, log: try HistoryLog(folder: root.historyFolder),
            actions: [
                .trash: TrashAction(trash: FakeTrash(folder: root.trashFolder, beforeMove: beforeMove)),
                .delete: DeleteAction(), .launchctl: LaunchctlAction(runner: runner),
            ], runningApps: runningApps, toolAction: ToolAction(runner: runner))
    }
}

/// An action for a method the executor has no real action for yet, such as Tool. It records which items it was handed
/// and acts on none of them; `onAct` runs as it is handed each one, so a test can cancel the run there.
final class FakeAction: PlanAction {
    private let handed = Mutex<[URL]>([])
    private let onAct: @Sendable () -> Void

    init(onAct: @escaping @Sendable () -> Void = {}) {
        self.onAct = onAct
    }

    /// The items the action was handed, in order.
    var items: [URL] {
        handed.withLock { $0 }
    }

    func act(on item: PlannedItem, at target: URL) async -> Acted<ItemOutcome.SkipReason> {
        handed.withLock { $0.append(target) }
        onAct()
        return Acted(.done(nil))
    }
}

/// An action that is still running when the run is stopped: it waits until its task is cancelled, then fails the item,
/// as a tool command does when Stop ends it (SAF-014). `started` says when it began, so a test can cancel then.
final class WaitingAction: PlanAction {
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init() {
        (started, startedContinuation) = AsyncStream.makeStream()
    }

    func act(on item: PlannedItem, at target: URL) async -> Acted<ItemOutcome.SkipReason> {
        startedContinuation.yield()
        // A sleep that long ends only by cancellation.
        let finished = (try? await Task.sleep(for: .seconds(600))) != nil
        return Acted(finished ? .done(nil) : .failed(ActionError(domain: "Test", code: 1, message: "stopped")))
    }
}

/// A history log that fails once it has written `recordsBeforeFailing` records, as a full disk would (SAF-005). It
/// counts the full flushes it is asked for, and fails them too once it is full.
actor FailingLog: RecordLog {
    let log: HistoryLog
    var recordsBeforeFailing: Int
    private(set) var fullFlushes = 0

    init(log: HistoryLog, recordsBeforeFailing: Int = .max) {
        self.log = log
        self.recordsBeforeFailing = recordsBeforeFailing
    }

    func append(_ record: HistoryRecord) async throws(HistoryError) {
        guard recordsBeforeFailing > 0 else { throw .cannotWrite(log.fileURL.path, "The test's log is full") }
        recordsBeforeFailing -= 1
        try await log.append(record)
    }

    func flushFully() async throws(HistoryError) {
        fullFlushes += 1
        guard recordsBeforeFailing > 0 else { throw .cannotWrite(log.fileURL.path, "The test's log is full") }
        try await log.flushFully()
    }
}
