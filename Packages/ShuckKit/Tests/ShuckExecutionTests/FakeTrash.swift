import Foundation
import ShuckExecution

/// A Trash folder inside the fixture root, so tests never touch the real Trash (D-47).
///
/// Like the Finder, it adds a number to a name that is already taken. `beforeMove` runs just before each move, so a
/// test can look at the log and the disk mid-run, cancel the run, or make the move fail by throwing.
struct FakeTrash: Trash {
    let folder: URL
    var beforeMove: @Sendable (URL) throws -> Void = { _ in }

    func trashItem(at url: URL) throws -> URL {
        try beforeMove(url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.deletingPathExtension().lastPathComponent
        let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        var destination = folder.appending(path: url.lastPathComponent)
        var number = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appending(path: "\(name) \(number)\(suffix)")
            number += 1
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}
