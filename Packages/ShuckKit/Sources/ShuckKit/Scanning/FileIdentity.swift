import Foundation

/// Which file an item is, whichever path leads to it: its volume and its file number on that volume.
///
/// Two paths with the same identity are one file, such as two hard links, so totals count it once (FCL-007).
public struct FileIdentity: Hashable, Sendable {
    /// The volume's device number (`st_dev`).
    public let volume: Int32
    /// The file's number on its volume (`st_ino`).
    public let file: UInt64

    public init(volume: Int32, file: UInt64) {
        self.volume = volume
        self.file = file
    }

    /// Reads the identity of the item at `url` without following a symlink. Returns `nil` if nothing is there.
    public static func read(_ url: URL) -> FileIdentity? {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &info) } ?? -1 }
        guard result == 0 else { return nil }
        return FileIdentity(volume: info.st_dev, file: info.st_ino)
    }
}
