import Foundation
import ShuckExecution
import ShuckKit
import Testing

@testable import Shuck

/// A list with both tiers, as Developer Junk has with Xcode Archives: "Select All" leaves "Your data" out, each action
/// counts and acts on its own tier, and a run never mixes them (DEV-R05, SAF-002, SAF-003, SAF-004, D-147).
///
/// The scan and the run are stubs, so these tests never touch the file system. The engine's fixture tests move real
/// archives (`XcodeArchivesPipelineTests`).
@MainActor
struct YourDataItemsTests {
    let context = ScanContext(home: URL(filePath: "/StubHome", directoryHint: .isDirectory))
    let xcode = ItemCategory(id: "xcode", name: "Xcode")
    let archives = ItemCategory(id: "xcode-archives", name: "Xcode Archives")

    func url(_ name: String) -> URL { context.home.appending(path: "Library/Caches").appending(path: name) }

    func cache(_ name: String, size: Int64 = 1_000, selection: ItemSelection = .selected) -> ScanItem {
        let folder = context.home.appending(path: "Library/Caches")
        let rule = SummaryConfirmationTests.rule(for: folder, tier: .rebuildable)
        return ScanItem(
            url: url(name), snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), tier: .rebuildable,
            method: .delete, reason: "Stub", source: StubRebuildable.id, category: xcode, selection: selection,
            ruleMatch: rule.map { RuleMatch(rule: $0, modified: .distantPast) })
    }

    func archive(_ name: String, size: Int64 = 50_000, selection: ItemSelection = .unselected) -> ScanItem {
        ScanItem(
            url: url(name), snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), tier: .yourData,
            method: .trash, reason: "Stub", source: StubRebuildable.id, category: archives, selection: selection)
    }

    /// A run that reports every item as done: deleted, or moved to the Trash.
    var runAll: RunPlan {
        { (plan: Plan) async throws(HistoryError) -> RunReport in
            RunReport(
                run: plan.run,
                outcomes: plan.items.map { item in
                    ItemOutcome(
                        item: item, result: .done(item.method == .trash ? URL(filePath: "/StubHome/.Trash/x") : nil))
                })
        }
    }

    func scannedModel(_ items: [ScanItem]) async -> (FileCleanupModel, StubRebuildable) {
        let subTool = StubRebuildable(items: items)
        let model = FileCleanupModel(subTools: [subTool], context: context, runPlan: runAll)
        await model.scan(subTool)?.value
        return (model, subTool)
    }

    @Test func selectAllLeavesYourDataUnselectedButKeepsAChoiceTheUserMadeSAF002() {
        let list = ScanResults()
        let mine = archive("Mine")
        let other = archive("Other")
        for item in [cache("a", selection: .unselected), cache("b", selection: .unselected), mine, other] {
            list.apply(.item(item))
        }

        list.selectAll()

        #expect(list.selectedItems(in: .rebuildable).count == 2 && list.selectedItems(in: .yourData).isEmpty)
        list.selection.insert(mine.target)
        list.selectAll()
        #expect(list.selectedItems(in: .yourData) == [mine])
        list.selection = []
        #expect(list.selectedItems.isEmpty)
    }

    @Test func eachTierCountsItsOwnSelectedItemsAndSizeSAF003SAF013() {
        let list = ScanResults()
        let mine = archive("Mine", size: 50_000)
        for item in [cache("a", size: 1_000), cache("b", size: 2_000), mine, archive("Other")] {
            list.apply(.item(item))
        }
        list.selection.insert(mine.target)

        #expect(list.selectedItems(in: .rebuildable).count == 2)
        #expect(list.selectedBytes(in: .rebuildable) == 3_000)
        #expect(list.selectedItems(in: .yourData) == [mine])
        #expect(list.selectedBytes(in: .yourData) == 50_000)
        #expect(list.hasYourData)
        #expect(!ScanResults().hasYourData)
    }

    @Test func aMixedSelectionGivesTwoSingleTierPlansSAF004() async throws {
        let mine = archive("Mine")
        let (model, subTool) = await scannedModel([cache("a"), cache("b"), mine, archive("Other")])
        let results = try #require(model.results(of: subTool.id) as? ScanResults)
        results.selection.insert(mine.target)

        let confirmation = try #require(try model.confirmRebuildable(subTool))
        // Every URL is offered to the review, as a caller that did not filter would; only "Your data" enters its plan.
        let review = try #require(try model.reviewMoveToTrash(subTool, urls: results.items.compactMap(\.url)))

        #expect(confirmation.plan.items.allSatisfy { $0.tier == .rebuildable && $0.method == .delete })
        #expect(confirmation.plan.items.count == 2)
        #expect(review.plan.items.allSatisfy { $0.tier == .yourData && $0.method == .trash })
        #expect(review.plan.items.map(\.url) == [url("Mine"), url("Other")])
    }

    @Test func movedArchivesLeaveTheListAndDeletedCachesStayUntilTheirOwnRunSAF011() async throws {
        let mine = archive("Mine")
        let (model, subTool) = await scannedModel([cache("a"), mine, archive("Other")])
        let results = try #require(model.results(of: subTool.id) as? ScanResults)
        results.selection.insert(mine.target)
        let review = try #require(
            try model.reviewMoveToTrash(subTool, urls: results.selectedItems(in: .yourData).compactMap(\.url)))

        await review.start()?.value

        #expect(results.items.map(\.url) == [url("a"), url("Other")])
        #expect(results.selectedItems(in: .yourData).isEmpty)
        #expect(results.selectedItems(in: .rebuildable).count == 1)
    }
}
