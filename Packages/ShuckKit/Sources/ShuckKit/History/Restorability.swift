import Foundation

/// An item Shuck moved to the Trash, as the history log recorded it (SAF-005).
public struct TrashedItem: Equatable, Sendable {
    /// The run that trashed the item.
    public let run: UUID
    /// The tool or sub-tool that trashed it.
    public let tool: ToolID
    public let tier: Tier
    /// Where the item was before it was trashed, and where Restore puts it back.
    public let originalURL: URL
    /// Where the system put it in the Trash (`resultingItemURL`).
    public let trashedURL: URL
    /// The allocated size logged when it was trashed; Restore checks it is still about the same (SAF-008).
    public let bytes: Int64?
    /// The file identity logged when it was trashed; Restore moves only an item that still has it (HIS-004, SAF-008).
    /// `nil` for items Shuck 0.1.0 trashed, which did not log it.
    public let identity: FileIdentity?

    public init(
        run: UUID, tool: ToolID, tier: Tier, originalURL: URL, trashedURL: URL, bytes: Int64?,
        identity: FileIdentity? = nil
    ) {
        self.run = run
        self.tool = tool
        self.tier = tier
        self.originalURL = originalURL
        self.trashedURL = trashedURL
        self.bytes = bytes
        self.identity = identity
    }

    /// Whether something now occupies the original path, so the user must choose what to do (HIS-003).
    public var originalIsTaken: Bool {
        ResolvedPath.itemExists(at: originalURL)
    }
}

/// One item to restore, with the user's choice for when its original path is taken (HIS-003).
public struct RestoreRequest: Equatable, Sendable {
    /// What to do when something occupies the original path. Restore never overwrites.
    public enum IfTaken: Equatable, Sendable {
        /// Leave the item in the Trash.
        case skip
        /// Restore it next to the other item, with " (restored)" added to its name.
        case keepBoth
    }

    public let item: TrashedItem
    public let ifTaken: IfTaken

    public init(item: TrashedItem, ifTaken: IfTaken = .skip) {
        self.item = item
        self.ifTaken = ifTaken
    }
}

/// Whether Restore can undo a logged operation (HIS-003, HIS-004).
public enum Restorability: Equatable, Sendable {
    /// The item is still where the Trash put it.
    case restorable(TrashedItem)
    /// The item is no longer at its trashed path, usually because the Trash was emptied (HIS-004).
    case trashEmptied
    /// Shuck may not look inside the Trash, so it cannot tell; usually Full Disk Access is missing (SAF-012).
    case notAccessible
    /// The log does not say where the item went in the Trash.
    case unknownLocation
    /// A later restore already put the item back.
    case restored
    /// Deleted permanently or cleaned by a tool's command (HIS-004, SAF-006).
    case permanent
    /// A launchctl change, reversed by the opposite action rather than by Restore (SAF-006).
    case reversedByOppositeAction
}

/// One operation from the history log that changed something, with whether Restore can undo it.
public struct HistoryEntry: Equatable, Sendable {
    /// The operation's result record.
    public let record: HistoryRecord
    public let restorability: Restorability

    public init(record: HistoryRecord, restorability: Restorability) {
        self.record = record
        self.restorability = restorability
    }
}

extension HistoryLog.Contents {
    /// Every operation that succeeded, in log order, with whether Restore can undo it (HIS-003, HIS-004).
    ///
    /// Skipped and failed operations changed nothing and are left out, and so are the restores themselves: a restore
    /// marks the entry it put back as ``Restorability/restored``. Restore records name the trashed path they took the
    /// item from, which is how they are matched (D-52).
    public func entries() -> [HistoryEntry] {
        var entries: [HistoryEntry] = []
        // The entry for the item at each trashed path, with case folded as the startup volume compares names. The
        // Trash can reuse a name once an item has left it, so a later record for the same path replaces the earlier
        // one, whose item must have left the Trash (HIS-004).
        var inTrash: [String: Int] = [:]
        for record in records where record.phase == .result && record.status == .ok {
            let restorability: Restorability
            switch record.operation {
            case .trash:
                guard let trashedPath = record.trashedPath else {
                    restorability = .unknownLocation
                    break
                }
                if let earlier = inTrash[PathGuard.fold(trashedPath)] {
                    entries[earlier] = HistoryEntry(record: entries[earlier].record, restorability: .trashEmptied)
                }
                inTrash[PathGuard.fold(trashedPath)] = entries.count
                restorability = .restorable(
                    TrashedItem(
                        run: record.run, tool: record.tool, tier: record.tier, originalURL: URL(filePath: record.path),
                        trashedURL: URL(filePath: trashedPath), bytes: record.bytes, identity: record.identity))
            case .restore:
                if let trashedPath = record.trashedPath,
                    let index = inTrash.removeValue(forKey: PathGuard.fold(trashedPath))
                {
                    entries[index] = HistoryEntry(record: entries[index].record, restorability: .restored)
                }
                continue
            case .delete, .tool:
                restorability = .permanent
            case .launchctl:
                restorability = .reversedByOppositeAction
            }
            entries.append(HistoryEntry(record: record, restorability: restorability))
        }
        return entries.map { entry in
            guard case .restorable(let item) = entry.restorability else { return entry }
            return HistoryEntry(record: entry.record, restorability: Self.checkTrash(for: item))
        }
    }

    /// Whether `item` is still in the Trash. Does not follow a symlink. An item with another file identity at the
    /// trashed path took the name after `item` left the Trash (HIS-004).
    private static func checkTrash(for item: TrashedItem) -> Restorability {
        var info = stat()
        guard lstat(item.trashedURL.path, &info) == 0 else {
            // Only a missing path means the Trash was emptied; any other error means Shuck cannot tell (SAF-012).
            return LstatFailure(errno: errno) == .missing ? .trashEmptied : .notAccessible
        }
        if let identity = item.identity,
            !identity.isSameTrashedFile(as: FileIdentity(volume: info.st_dev, file: info.st_ino))
        {
            return .trashEmptied
        }
        return .restorable(item)
    }
}

/// The entries directly inside the Trash folder, by file number, read once when History loads (HIS-001).
struct TrashListing {
    let folder: URL
    private var entries: [UInt64: [URL]]?
    private var unreadable = false

    init(folder: URL) {
        self.folder = folder
    }

    /// The only entry directly inside the folder with the file number of `identity`. `nil` if there is none or more
    /// than one, such as hard links. Throws `true` if the folder cannot be listed because Shuck may not look.
    mutating func entry(with identity: FileIdentity) -> (url: URL?, notAccessible: Bool) {
        if entries == nil {
            var found: [UInt64: [URL]] = [:]
            do {
                for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                    if let entry = FileIdentity.read(url) { found[entry.file, default: []].append(url) }
                }
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                unreadable = true
            } catch {
                // A Trash that does not exist holds nothing.
            }
            entries = found
        }
        if unreadable { return (nil, true) }
        let matches = entries?[identity.file] ?? []
        return (matches.count == 1 ? matches[0] : nil, false)
    }
}

extension Restorability {
    /// What Restore can do for a Trash item that has an intent record and no result, because Shuck was quit or crashed
    /// between the move and the result record (HIS-001, SAF-005, R-04). The result record is the only one that names
    /// the trashed path, so the item is found by the identity its intent record logged: it is restorable when its
    /// original path is gone and an entry directly inside the Trash has that identity. `nil` if it is not found, and
    /// the item stays interrupted. ``notAccessible`` if Shuck may not list the Trash (SAF-012).
    static func interruptedTrash(_ intent: HistoryRecord, in trash: inout TrashListing) -> Restorability? {
        guard let identity = intent.identity, !ResolvedPath.itemExists(at: URL(filePath: intent.path)) else {
            return nil
        }
        let found = trash.entry(with: identity)
        if found.notAccessible { return .notAccessible }
        guard let trashed = found.url else { return nil }
        return .restorable(
            TrashedItem(
                run: intent.run, tool: intent.tool, tier: intent.tier, originalURL: URL(filePath: intent.path),
                trashedURL: trashed, bytes: intent.bytes, identity: identity))
    }
}
