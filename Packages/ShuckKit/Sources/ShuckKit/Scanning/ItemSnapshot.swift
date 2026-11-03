import Foundation

/// What an item looked like when it was measured: its type and allocated size (SAF-013).
///
/// A plan records the snapshot taken at scan time; the executor takes a new one just before acting and skips the
/// item if they don't match (SAF-008).
public struct ItemSnapshot: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case file
        /// A folder or a package (FCL-009).
        case folder
        case symlink
    }

    public let kind: Kind
    /// Allocated size in bytes. For a folder, the total of everything inside it.
    public let allocatedSize: Int64

    public init(kind: Kind, allocatedSize: Int64) {
        self.kind = kind
        self.allocatedSize = allocatedSize
    }

    /// Measures the item at `url` without following symlinks. Returns `nil` if nothing is there, or if
    /// `shouldContinue` returns `false` while a folder is being measured.
    public static func read(_ url: URL, while shouldContinue: () -> Bool = { true }) -> ItemSnapshot? {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .totalFileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        if values.isSymbolicLink == true {
            return ItemSnapshot(kind: .symlink, allocatedSize: Int64(values.totalFileAllocatedSize ?? 0))
        }
        guard values.isDirectory == true else {
            return ItemSnapshot(kind: .file, allocatedSize: Int64(values.totalFileAllocatedSize ?? 0))
        }
        // The enumerator does not follow symlinks, so a link inside the folder counts as the link itself. Each item's
        // autoreleased objects are freed before the next, so measuring a large folder keeps memory flat (D-80).
        var total: Int64 = 0
        let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let size = autoreleasepool(invoking: { nextSize(contents, keys) }) {
            guard shouldContinue() else { return nil }
            total += size
        }
        return ItemSnapshot(kind: .folder, allocatedSize: total)
    }

    /// What re-validation finds at an item's path (SAF-008, SAF-012).
    public enum Check: Equatable, Sendable {
        case found(ItemSnapshot)
        case missing
        /// Permission was denied (EPERM or EACCES), for example by macOS privacy protection (SAF-012).
        case notAccessible
        /// `shouldContinue` returned `false` while a folder was being measured, as when the user stops a run (SAF-014).
        case stopped
    }

    /// Measures the item at `url` as ``read(_:while:)`` does, telling a missing item from one Shuck may not read. A
    /// folder whose contents can't be listed is not accessible, rather than empty. Any other error counts as missing.
    /// Measuring a large folder, such as a device backup, can take a while, so it stops as soon as `shouldContinue`
    /// returns `false`.
    public static func check(_ url: URL, while shouldContinue: () -> Bool = { true }) -> Check {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return failure(errno) }
        if info.st_mode & S_IFMT == S_IFDIR {
            guard let folder = opendir(url.path) else { return failure(errno) }
            closedir(folder)
        }
        if let snapshot = read(url, while: shouldContinue) { return .found(snapshot) }
        return shouldContinue() ? .missing : .stopped
    }

    private static func failure(_ code: Int32) -> Check {
        code == EPERM || code == EACCES ? .notAccessible : .missing
    }

    /// The allocated size of the enumerator's next item, or `nil` when it has none left.
    private static func nextSize(_ contents: FileManager.DirectoryEnumerator?, _ keys: Set<URLResourceKey>) -> Int64? {
        guard let child = contents?.nextObject() as? URL else { return nil }
        return Int64((try? child.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
    }

    /// Whether `current` still matches this planned snapshot: the same kind, and a size within
    /// 64 KiB or 1%, whichever is larger (D-48).
    public func matches(_ current: ItemSnapshot) -> Bool {
        kind == current.kind && Self.sizeMatches(planned: allocatedSize, current: current.allocatedSize)
    }

    /// Whether a size measured now is within 64 KiB or 1% of the planned size, whichever is larger (D-48).
    public static func sizeMatches(planned: Int64, current: Int64) -> Bool {
        abs(current - planned) <= max(64 * 1024, planned / 100)
    }
}
