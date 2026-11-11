import Foundation
import ShuckKit

/// One sub-tool's results: what its page lists and its selection (FCL-002). Each available sub-tool has its own, so
/// a scan, a selection or a run in one list never changes another's.
///
/// The page needs only to know whether there is anything to list (D-61); the model removes rows a run acted on.
protocol SubToolResults: AnyObject {
    /// Whether the page shows its message instead of a list (D-61).
    var isEmpty: Bool { get }
    /// Removes rows, for example after a run trashed them, and drops them from the selection.
    func remove(_ urls: some Sequence<URL>)
    /// Empties the list before a new scan, or after a stopped one.
    func removeAll()
}

/// The results of a sub-tool whose scan streams its items, such as Developer Junk, in the order the scan found them
/// (FCL-012). Large Files and Old Files list their shared scan in ``PersonalFilesResults`` instead (FCL-006).
@Observable
final class ScanResults: SubToolResults {
    private(set) var items: [ScanItem] = []
    /// Rules select safe rebuildable items by default; personal files stay unselected (SAF-004).
    private var selected: Set<ItemTarget> = []
    var selection: Set<ItemTarget> {
        get { selected }
        set { selected = newValue.intersection(items.filter { $0.selection.isSelectable }.map(\.target)) }
    }

    var selectedItems: [ScanItem] {
        items.filter { selected.contains($0.target) && $0.selection.isSelectable }
    }
    /// The allocated size of the selected items, in bytes (SAF-013).
    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.allocatedSize }
    }
    /// Selects every row that can be chosen; the setter leaves out locked rows (SAF-009).
    func selectAll() {
        selection = Set(items.map(\.target))
    }

    /// Folders macOS did not let the scan read (SAF-012).
    private(set) var notAccessibleCount = 0
    /// Folders the scan could not read for another reason, such as a disk error (SAF-011).
    private(set) var unreadableCount = 0

    var isEmpty: Bool { items.isEmpty }

    func apply(_ event: ScanEvent) {
        switch event {
        case .item(let item):
            if let index = items.firstIndex(where: { $0.target == item.target }) {
                // A repeated event refreshes metadata, not the user's choice; a newly disabled item is deselected.
                items[index] = item
                if !item.selection.isSelectable { selected.remove(item.target) }
            } else {
                items.append(item)
                if item.selection == .selected { selected.insert(item.target) }
            }
        case .notAccessible: notAccessibleCount += 1
        case .unreadable: unreadableCount += 1
        }
    }

    /// The items at `urls`, in that order. URLs the list no longer has are left out.
    func items(at urls: [URL]) -> [ScanItem] {
        let byTarget = Dictionary(
            uniqueKeysWithValues: items.filter { $0.selection.isSelectable }.map { ($0.target, $0) })
        return urls.compactMap { byTarget[.path($0)] }
    }

    func remove(_ urls: some Sequence<URL>) {
        let removed = Set(urls)
        items.removeAll { $0.url.map(removed.contains) == true }
        selected.subtract(removed.map(ItemTarget.path))
    }

    /// Removes the items for tool commands a run has run, and drops them from the selection.
    func remove(commands: some Sequence<ToolCommand>) {
        let removed = Set(commands.map(ItemTarget.command))
        items.removeAll { removed.contains($0.target) }
        selected.subtract(removed)
    }

    func removeAll() {
        items = []
        selected = []
        notAccessibleCount = 0
        unreadableCount = 0
    }

    /// What the landing page shows about the list (FCL-004).
    func summary(finished: Date) -> FileCleanupModel.ScanSummary {
        FileCleanupModel.ScanSummary(
            finished: finished, itemCount: items.count,
            reclaimableBytes: items.filter { $0.selection.isSelectable }.reduce(0) { $0 + $1.allocatedSize },
            notAccessibleCount: notAccessibleCount, unreadableCount: unreadableCount)
    }
}

extension PersonalFilesResults: SubToolResults {
    var isEmpty: Bool { rows.isEmpty }
}
