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
    /// `beforeMove` just before each move.
    init(
        root: FixtureRoot, pathGuard: PathGuard, beforeMove: @escaping @Sendable (URL) throws -> Void = { _ in }
    ) throws {
        self.init(
            pathGuard: pathGuard, log: try HistoryLog(folder: root.historyFolder),
            trash: FakeTrash(folder: root.trashFolder, beforeMove: beforeMove))
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

    func act(on item: PlannedItem, at target: URL) -> Acted<ItemOutcome.SkipReason> {
        handed.withLock { $0.append(item.url) }
        onAct()
        return Acted(.done(nil))
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
