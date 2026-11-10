import Foundation
import ShuckKit

/// One app's items on the Caches & Logs page, with their total (CAC-002).
nonisolated struct AppGroup: Identifiable, Equatable {
    let name: String
    /// The biggest first.
    let items: [ScanItem]

    var id: String { name }

    /// The allocated size of the items, in bytes (SAF-013).
    var totalSize: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }

    /// Groups items by the app the scan named, the biggest group first and the biggest item first inside it. An item
    /// with no app name is grouped under its own file name, so it is never left out. Equal sizes go by name, so the
    /// order does not change between redraws.
    static func groups(of items: [ScanItem]) -> [AppGroup] {
        let byName = Dictionary(grouping: items) { $0.appName ?? $0.url?.lastPathComponent ?? "" }
        return byName.map { name, items in
            AppGroup(name: name, items: items.sorted(by: bigger))
        }
        .sorted { first, second in
            first.totalSize != second.totalSize
                ? first.totalSize > second.totalSize
                : first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    private static func bigger(_ first: ScanItem, _ second: ScanItem) -> Bool {
        first.allocatedSize != second.allocatedSize
            ? first.allocatedSize > second.allocatedSize
            : (first.url?.path ?? "") < (second.url?.path ?? "")
    }
}
