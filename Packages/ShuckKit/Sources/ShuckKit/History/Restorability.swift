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

    public init(run: UUID, tool: ToolID, tier: Tier, originalURL: URL, trashedURL: URL, bytes: Int64?) {
        self.run = run
        self.tool = tool
        self.tier = tier
        self.originalURL = originalURL
        self.trashedURL = trashedURL
        self.bytes = bytes
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
        // The entry for the item at each trashed path. The Trash can reuse a name once an item has left it, so a
        // later record for the same path replaces the earlier one.
        var inTrash: [String: Int] = [:]
        for record in records where record.phase == .result && record.status == .ok {
            let restorability: Restorability
            switch record.operation {
            case .trash:
                guard let trashedPath = record.trashedPath else {
                    restorability = .unknownLocation
                    break
                }
                inTrash[trashedPath] = entries.count
                restorability = .restorable(
                    TrashedItem(
                        run: record.run, tool: record.tool, tier: record.tier, originalURL: URL(filePath: record.path),
                        trashedURL: URL(filePath: trashedPath), bytes: record.bytes))
            case .restore:
                if let trashedPath = record.trashedPath, let index = inTrash.removeValue(forKey: trashedPath) {
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

    /// Whether `item` is still in the Trash. Does not follow a symlink.
    private static func checkTrash(for item: TrashedItem) -> Restorability {
        var info = stat()
        if lstat(item.trashedURL.path, &info) == 0 { return .restorable(item) }
        return errno == ENOENT || errno == ENOTDIR ? .trashEmptied : .notAccessible
    }
}
