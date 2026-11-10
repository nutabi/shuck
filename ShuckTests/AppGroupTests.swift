import Foundation
import ShuckKit
import Testing

@testable import Shuck

/// Caches & Logs groups its items by the app the scan named (CAC-002).
struct AppGroupTests {
    func item(_ path: String, size: Int64, app: String?) -> ScanItem {
        ScanItem(
            url: URL(filePath: "/StubHome/Library/\(path)"),
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), tier: .rebuildable, method: .delete,
            reason: "Fixture", source: .cachesAndLogs, scope: .contents, appName: app)
    }

    @Test func itemsOfOneAppShareAGroupAndTheBiggestGroupComesFirstCAC002() {
        let groups = AppGroup.groups(
            of: [
                item("Caches/a", size: 100, app: "Notes"), item("Caches/b", size: 5_000, app: "Mail"),
                item("Logs/a", size: 900, app: "Notes"), item("Caches/c", size: 10, app: "Other"),
            ])

        #expect(groups.map(\.name) == ["Mail", "Notes", "Other"])
        #expect(groups.map(\.totalSize) == [5_000, 1_000, 10])
        // Inside a group the biggest item comes first.
        #expect(groups[1].items.map(\.allocatedSize) == [900, 100])
    }

    @Test func anItemWithoutAnAppNameIsGroupedUnderItsFileNameNotLeftOut() {
        let groups = AppGroup.groups(of: [item("Caches/loose.dat", size: 1, app: nil)])
        #expect(groups.map(\.name) == ["loose.dat"])
    }

    @Test func equalSizesAreOrderedByNameSoTheOrderIsStable() {
        let groups = AppGroup.groups(of: [
            item("Caches/b", size: 5, app: "Beta"), item("Caches/a", size: 5, app: "Alpha"),
        ])
        #expect(groups.map(\.name) == ["Alpha", "Beta"])
    }

    @Test func noItemsMakeNoGroups() {
        #expect(AppGroup.groups(of: []).isEmpty)
    }
}
