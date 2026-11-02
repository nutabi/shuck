import Foundation

/// Adds up allocated sizes so that each file counts once, however many sub-tools list it and however many paths lead
/// to it (FCL-007).
///
/// Files are matched by ``FileIdentity``. A file without one, such as one a test made up, is matched by its path.
public struct ReclaimableTotal: Sendable {
    private enum Key: Hashable {
        case identity(FileIdentity)
        case path(String)
    }

    private var counted: Set<Key> = []
    /// The allocated size of the files added, each counted once, in bytes (SAF-013).
    public private(set) var bytes: Int64 = 0

    public init() {}

    public init(_ files: some Sequence<PersonalFile>) {
        add(contentsOf: files)
    }

    /// How many different files were added.
    public var count: Int { counted.count }

    /// Adds `file`'s size unless the same file was added already. Read-only files can never be cleaned up, so they are
    /// left out (FCL-011).
    public mutating func add(_ file: PersonalFile) {
        guard file.readOnly == nil else { return }
        let key = file.identity.map(Key.identity) ?? .path(file.url.standardizedFileURL.path)
        if counted.insert(key).inserted {
            bytes += file.snapshot.allocatedSize
        }
    }

    public mutating func add(contentsOf files: some Sequence<PersonalFile>) {
        for file in files {
            add(file)
        }
    }
}
