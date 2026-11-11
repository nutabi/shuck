import Foundation

/// The modification date an item's scan records and its run compares before acting (SAF-008, D-105, D-132).
///
/// Scan and run read it the same way, with a fresh `lstat` and no URL resource-value cache, so the two dates compare
/// at the same precision and an unchanged item always matches. Only reads.
public enum ModificationDate {
    /// The date re-validation compares: the item's own date, or, for an item whose scope is its contents, the newest
    /// date of the folder, what is directly inside it and what is inside those, the date its scan judged staleness by
    /// (D-112, D-132). `nil` if nothing is at `url`.
    public static func read(at url: URL, scope: ItemScope) -> Date? {
        guard let own = read(at: url) else { return nil }
        return compared(at: url, scope: scope, own: own)
    }

    /// ``read(at:scope:)`` for an item whose own date the scan has already read.
    public static func compared(at url: URL, scope: ItemScope, own: Date) -> Date {
        scope == .contents ? FolderActivity.newest(in: url, modified: own) : own
    }

    /// The item's own modification date, without following a final symlink. `nil` if nothing is at `url`.
    public static func read(at url: URL) -> Date? {
        status(of: url).map(date)
    }

    /// The `lstat` of the item at `url`, or `nil` if nothing is there.
    static func status(of url: URL) -> stat? {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &info) } ?? -1 }
        return result == 0 ? info : nil
    }

    /// The modification date in `info`, to the nanosecond the file system keeps.
    static func date(_ info: stat) -> Date {
        Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
    }
}
