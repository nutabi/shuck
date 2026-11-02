import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport

/// A ``FolderTrash`` inside the fixture root, so tests never touch the real Trash (D-47).
///
/// `beforeMove` runs just before each move, so a test can look at the log and the disk mid-run, cancel the run, or make
/// the move fail by throwing.
struct FakeTrash: Trash {
    let folder: URL
    var beforeMove: @Sendable (URL) throws -> Void = { _ in }

    func trashItem(at url: URL) throws -> URL {
        try beforeMove(url)
        return try FolderTrash(folder: folder).trashItem(at: url)
    }
}

extension TrashExecutor {
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
