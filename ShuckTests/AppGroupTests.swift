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

    /// A UI test names the apps its fixture root is taken to have, so their caches can start selected (CAC-009,
    /// D-156). The name is the bundle ID itself, whatever its case.
    @Test func aFixtureRootsInstalledAppsAreNamedByTheirBundleIDCAC009() {
        let names = AppEnvironment.FixtureAppNames(installed: ["com.example.Notes"])

        #expect(names.name(ofBundleID: "COM.example.notes") == "COM.example.notes")
        #expect(names.installed == ["com.example.notes"])
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

    @Test func whileScanningGroupsAndItemsKeepTheirArrivalOrderFCL012() {
        let items = [
            item("Caches/a", size: 100, app: "Notes"), item("Caches/b", size: 5_000, app: "Mail"),
            item("Logs/a", size: 900, app: "Notes"),
        ]

        let scanning = AppGroup.groups(of: items, scanning: true)
        #expect(scanning.map(\.name) == ["Notes", "Mail"])
        #expect(scanning[0].items.map(\.allocatedSize) == [100, 900])
        #expect(AppGroup.groups(of: items, scanning: false).map(\.name) == ["Mail", "Notes"])
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
}
