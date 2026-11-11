import Foundation

/// The free space on the volume that holds a folder, as macOS reports it (SAF-013).
public enum FreeSpace {
    /// The bytes free now on the volume that holds `url`, or `nil` if macOS doesn't say.
    ///
    /// This is `volumeAvailableCapacityKey`: the space free now, without the purgeable space macOS could free when it
    /// needs it. Purgeable space grows and shrinks on its own, so counting it would blur what a run freed. Reading it
    /// asks the file system for the volume's numbers and walks nothing. A `URL` keeps the resource values it has read,
    /// so the cache is cleared first: two readings of the same URL around a run must both be fresh.
    public static func available(at url: URL) -> Int64? {
        var url = url
        url.removeAllCachedResourceValues()
        guard let bytes = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        else { return nil }
        return Int64(bytes)
    }

    /// The bytes in use on the volume that holds `url`: its capacity less what is free now, or `nil` if macOS doesn't
    /// say. Like ``available(at:)``, it walks nothing.
    public static func used(at url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacity
        else { return nil }
        return Int64(max(0, total - available))
    }
}

/// The size above which one Rebuildable item needs a second confirmation before it is deleted or cleaned up (SAF-015).
///
/// The PRD's default is a quarter of the home folder's size, but measuring the home folder means walking all of it. A
/// quarter of the space in use on the startup volume is read at once and is close to it on a Mac with one user, a little
/// larger (D-144).
public struct OversizeThreshold: Equatable, Sendable {
    /// The size in bytes; an item larger than this is oversized.
    public let bytes: Int64

    /// The threshold for a volume with `usedSpace` bytes in use, or `nil` if that is not known, and then no item is
    /// oversized.
    public init?(usedSpace: Int64?) {
        guard let usedSpace, usedSpace > 0 else { return nil }
        bytes = usedSpace / 4
    }

    /// The Rebuildable items of `items` larger than the threshold, in plan order. "Your data" items get an itemized
    /// review of their own (SAF-002).
    public func oversized(_ items: [PlannedItem]) -> [PlannedItem] {
        items.filter { $0.tier == .rebuildable && $0.allocatedSize > bytes }
    }
}

/// How free space changed over a run, next to what the run expected to free, and why the two can differ (SAF-013,
/// R-06).
///
/// Items moved to the Trash are not in the estimate: they free nothing until the Trash is emptied, and the Trash's own
/// summary says so.
public struct FreeSpaceChange: Equatable, Sendable {
    /// A reason the measured change can differ from the estimate.
    public enum Gap: Hashable, Sendable {
        /// Local Time Machine snapshots and APFS clones keep a deleted file's blocks in use, so the space freed can be
        /// far below the estimate.
        case snapshotsAndClones
        /// A tool's size is the most it may remove, and the tool decides what it removes (D-125).
        case toolEstimate
        /// A tool ran whose size Shuck could not measure, such as `simctl delete unavailable`, so the estimate leaves
        /// out whatever it freed (D-125).
        case toolSizeUnknown
        /// macOS and other apps use and free space while the run goes, and macOS frees purgeable space when it needs it.
        case otherActivity
    }

    /// How much more space is free after the run than before it, in bytes; below zero if less is free.
    public let measured: Int64
    /// How much the run expected to free: the allocated sizes of the deleted items and the tools' estimates. A tool
    /// whose size is not known adds nothing.
    public let estimate: Int64
    /// The reasons that apply, in the order the summary states them. Empty when the two agree.
    public let gaps: [Gap]

    /// The smallest difference between the measured change and the estimate that the summary explains: 10 MB, or a
    /// tenth of the estimate if that is more. Smaller differences are the history log and other apps' everyday writes.
    public static let minimumUnexplained: Int64 = 10_000_000

    /// - Parameters:
    ///   - before: The free bytes just before the run.
    ///   - after: The free bytes just after it.
    ///   - deleted: The allocated size of the items the run deleted.
    ///   - toolEstimate: The estimates of the tool commands that ran to the end and have one, or `nil` if none did.
    ///   - toolSizeUnknown: Whether a tool command without an estimate ran to the end.
    public init(before: Int64, after: Int64, deleted: Int64, toolEstimate: Int64?, toolSizeUnknown: Bool = false) {
        measured = after - before
        estimate = deleted + (toolEstimate ?? 0)
        let unexplained = max(Self.minimumUnexplained, estimate / 10)
        var gaps: [Gap] = []
        if deleted > 0, measured < estimate - unexplained {
            gaps.append(.snapshotsAndClones)
        }
        if toolEstimate != nil {
            gaps.append(.toolEstimate)
        }
        if toolSizeUnknown {
            gaps.append(.toolSizeUnknown)
        }
        // A tool of unknown size explains any space freed beyond the estimate, but not less space than it.
        let freedLess = measured < estimate - unexplained
        let freedMore = measured > estimate + unexplained
        if freedLess || (freedMore && !toolSizeUnknown) {
            gaps.append(.otherActivity)
        }
        self.gaps = gaps
    }
}
