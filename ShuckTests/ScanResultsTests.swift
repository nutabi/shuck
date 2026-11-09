import Foundation
import ShuckKit
import Testing

@testable import Shuck

@MainActor
struct ScanResultsTests {
    let category = ItemCategory(id: "fixture", name: "Fixture caches")

    func item(_ name: String, selection: ItemSelection = .unselected) -> ScanItem {
        ScanItem(
            url: URL(filePath: "/StubHome/Library/Caches/\(name)"),
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: 4096),
            tier: .rebuildable, method: .delete, reason: "Fixture cache", source: .cachesAndLogs,
            category: category, selection: selection)
    }

    @Test func defaultsAndUserSelectionRespectDisabledItemsSAF004DEV005() {
        let list = ScanResults()
        let stale = item("stale", selection: .selected)
        let recent = item("recent")
        let running = item("running", selection: .disabled("Fixture app is running"))
        for item in [stale, recent, running] { list.apply(.item(item)) }
        #expect(list.selectedItems == [stale])
        // A user can choose recent data, but cannot force a disabled row into the selection or a plan.
        list.selection = [recent.target, running.target, .path(URL(filePath: "/StubHome/missing"))]
        #expect(list.selectedItems == [recent] && list.selection == [recent.target])
        #expect(list.items(at: [URL(filePath: "/StubHome/Library/Caches/running")]).isEmpty)
        #expect(list.summary(finished: .now).reclaimableBytes == 8192)
        #expect(list.selectedBytes == 4096)
    }

    @Test func refreshedEventsKeepTheUsersChoiceUntilAnItemIsDisabled() {
        let list = ScanResults()
        let stale = item("stale", selection: .selected)
        list.apply(.item(stale))
        list.selection = []
        list.apply(.item(stale))
        #expect(list.items.count == 1 && list.selection.isEmpty)
        list.selection = [stale.target]
        list.apply(.item(item("stale", selection: .disabled("Fixture app is running"))))
        #expect(list.selectedItems.isEmpty && list.selection.isEmpty)
    }

    @Test func commandsHaveTheirOwnSelectionAndEstimateWithoutAPathDEV003() throws {
        let list = ScanResults()
        let command = try ToolCommand(
            executable: "/StubHome/tools/cleaner", arguments: ["clean"], environment: ["PATH": "/bin"])
        let tool = ScanItem(
            command: command, allocatedSize: 12_345, tier: .rebuildable, reason: "Fixture cleanup",
            source: .developerJunk,
            category: category, selection: .selected)
        let path = item("stale", selection: .selected)
        list.apply(.item(tool))
        list.apply(.item(path))
        #expect(list.selectedItems == [tool, path])
        #expect(list.summary(finished: .now).reclaimableBytes == 12_345 + 4096)
        list.remove([try #require(path.url)])
        #expect(list.items == [tool] && list.selection == [tool.target])
        list.removeAll()
        #expect(list.items.isEmpty && list.selection.isEmpty)
    }
}
