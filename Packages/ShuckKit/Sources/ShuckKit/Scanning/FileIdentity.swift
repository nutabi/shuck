import Foundation

/// Which file an item is, whichever path leads to it: its volume and its file number on that volume.
///
/// Two paths with the same identity are one file, such as two hard links, so totals count it once (FCL-007). A move
/// within a volume, such as into its Trash, keeps it, so the history log records it to tell a trashed item from another
/// that later took its name in the Trash (HIS-004).
public struct FileIdentity: Codable, Hashable, Sendable {
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

    /// Whether `current`, read now at a trashed item's path, is the file this identity was logged for, in this session
    /// or an earlier one. Compares only the file number: a volume's device number can change when the Mac restarts,
    /// and both identities are of an item directly inside the Trash, whose volume the path fixes and whose file
    /// numbers APFS never reuses (D-84).
    public func isSameTrashedFile(as current: FileIdentity) -> Bool {
        file == current.file
    }
}
