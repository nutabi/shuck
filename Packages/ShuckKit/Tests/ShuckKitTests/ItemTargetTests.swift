import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

struct ItemTargetTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let category = ItemCategory(id: "fixture", name: "Fixture caches")

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test func aCommandKeepsItsEstimateAndReviewMetadataThroughPlanningSAF001DEV003() throws {
        let command = try ToolCommand(
            executable: root.url.appending(path: "tools/cleaner").path, arguments: ["clean", "--cache"],
            environment: ["PATH": "/usr/bin:/bin"])
        let scanned = ScanItem(
            command: command, allocatedSize: 123_456, tier: .rebuildable, reason: "Fixture cleanup",
            source: FixtureSubTool.id, category: category, selection: .selected)
        let subTool = FixtureSubTool(tier: .rebuildable, method: .tool)
        let plan = try Plan(subTool: subTool, items: [scanned], pathGuard: pathGuard)
        let item = try #require(plan.items.first)
        #expect(item.target == .command(command) && scanned.id == item.id)
        #expect(item.method == .tool && item.allocatedSize == 123_456)
        #expect(item.url == nil && item.snapshot == nil && scanned.url == nil && scanned.snapshot == nil)
        #expect(item.category == category && item.selection == .selected)
        #expect(item.target.description == command.display)
    }

    @Test func aDisabledItemCannotBePlannedEvenWhenRequestedDirectlySAF004() throws {
        let file = try root.file("Library/Caches/Fixture/cache.db", size: 10)
        let snapshot = try #require(ItemSnapshot.read(file))
        let disabled = ItemSelection.disabled("Fixture app is running")
        let scanned = ScanItem(
            url: file, snapshot: snapshot, tier: .rebuildable, method: .delete, reason: "Fixture cache",
            source: FixtureSubTool.id, category: category, selection: disabled)
        #expect(!scanned.selection.isSelectable)
        #expect(scanned.selection.disabledReason.map { String(localized: $0) } == "Fixture app is running")
        #expect(throws: PlanError.notSelectable(file.path)) {
            try Plan(
                subTool: FixtureSubTool(tier: .rebuildable, method: .delete), items: [scanned], pathGuard: pathGuard)
        }
        let item = PlannedItem(url: file, tier: .rebuildable, method: .delete, snapshot: snapshot, selection: disabled)
        #expect(throws: PlanError.notSelectable(file.path)) {
            try Plan(tool: .developerJunk, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
        }
        #expect(PlanError.notSelectable(file.path).path == file.path)
    }

    @Test func aToolItemMustNameItsCommandRatherThanAFileSAF010() throws {
        let file = try root.file("Library/Caches/Fixture/cache.db", size: 10)
        let item = PlannedItem(
            url: file, tier: .rebuildable, method: .tool, snapshot: try #require(ItemSnapshot.read(file)))
        #expect(throws: PlanError.commandRequired(file.path)) {
            try Plan(tool: .developerJunk, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
        }
        #expect(PlanError.commandRequired(file.path).path == file.path)
    }
}
