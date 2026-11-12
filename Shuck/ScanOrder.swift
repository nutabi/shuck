import ShuckKit

/// The order a list shows scan results in. While a scan runs, new items would move and insert rows above others in a
/// live `List`, which leaves `NSTableView`'s cached row heights stale and makes rows jump under the pointer. So a
/// running scan shows items in the order they arrived, and the list is sorted by size once, when the scan is over
/// (FCL-012, NFR-A11Y-001).
nonisolated enum ScanOrder {
    /// `items` as they arrived while `scanning`, the biggest first otherwise. Equal sizes keep their arrival order.
    static func ordered(_ items: [ScanItem], scanning: Bool) -> [ScanItem] {
        scanning ? items : items.sorted { $0.allocatedSize > $1.allocatedSize }
    }
}
