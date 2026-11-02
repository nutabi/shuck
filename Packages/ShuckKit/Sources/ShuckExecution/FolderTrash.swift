import Foundation

/// A Trash that is a plain folder: tests use one inside the fixture root, and so does the app in its debug-only
/// fixture-root mode, so neither touches the real Trash in the home folder (D-47, D-63).
///
/// Like the Finder, it adds a number to a name that is already taken: `clip.mov`, then `clip 2.mov`.
public struct FolderTrash: Trash {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func trashItem(at url: URL) throws -> URL {
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
