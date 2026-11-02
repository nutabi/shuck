import Foundation
import ShuckExecution

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
