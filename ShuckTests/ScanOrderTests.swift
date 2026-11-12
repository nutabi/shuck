import Foundation
import ShuckKit
import Testing

@testable import Shuck

/// A list keeps the order items arrive in while a scan runs, and sorts by size when it is over (FCL-012,
/// NFR-A11Y-001).
struct ScanOrderTests {
    func item(_ name: String, size: Int64) -> ScanItem {
        ScanItem(
            url: URL(filePath: "/StubHome/Library/\(name)"),
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), tier: .rebuildable, method: .delete,
            reason: "Fixture", source: .cachesAndLogs, scope: .contents, appName: nil)
    }

    @Test func aRunningScanKeepsArrivalOrderFCL012() {
        let items = [item("a", size: 10), item("b", size: 300), item("c", size: 20)]
        #expect(ScanOrder.ordered(items, scanning: true).map(\.allocatedSize) == [10, 300, 20])
    }

    @Test func aFinishedScanIsSortedBiggestFirstFCL012() {
        let items = [item("a", size: 10), item("b", size: 300), item("c", size: 20)]
        #expect(ScanOrder.ordered(items, scanning: false).map(\.allocatedSize) == [300, 20, 10])
    }
}
