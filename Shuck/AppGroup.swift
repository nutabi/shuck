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
    /// order does not change between redraws. While `scanning`, groups and items stay in the order they arrived, so
    /// no row moves under the list until the scan is over (``ScanOrder``).
    static func groups(of items: [ScanItem], scanning: Bool = false) -> [AppGroup] {
        func name(of item: ScanItem) -> String { item.appName ?? item.url?.lastPathComponent ?? "" }
        if scanning {
            var names: [String] = []
            var byName: [String: [ScanItem]] = [:]
            for item in items {
                let key = name(of: item)
                if byName[key] == nil { names.append(key) }
                byName[key, default: []].append(item)
            }
            return names.map { AppGroup(name: $0, items: byName[$0] ?? []) }
        }
        let byName = Dictionary(grouping: items, by: name(of:))
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
