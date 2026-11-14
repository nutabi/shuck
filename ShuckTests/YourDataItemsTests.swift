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
        await model.scan(subTool.id)?.value
        return (model, subTool)
    }

    /// Scan, select, plan and run: "Select All" leaves "Your data" out but keeps a choice the user made, each tier
    /// counts its own selection, a mixed selection gives two single-tier plans, and moved archives leave the list while
    /// deleted caches stay until their own run.
    @Test func eachTierIsSelectedCountedPlannedAndRunOnItsOwnSAF002SAF003SAF004SAF011SAF013() async throws {
        let mine = archive("Mine")
        let (model, subTool) = await scannedModel([
            cache("a", size: 1_000, selection: .unselected), cache("b", size: 2_000, selection: .unselected), mine,
            archive("Other"),
        ])
        let results = try #require(model.results(of: subTool.id) as? ScanResults)

        results.selectAll()

        #expect(results.selectedItems(in: .rebuildable).count == 2 && results.selectedItems(in: .yourData).isEmpty)
        results.selection.insert(mine.target)
        results.selectAll()
        #expect(results.selectedItems(in: .rebuildable).count == 2)
        #expect(results.selectedBytes(in: .rebuildable) == 3_000)
        #expect(results.selectedItems(in: .yourData) == [mine])
        #expect(results.selectedBytes(in: .yourData) == 50_000)
        #expect(results.hasYourData)
        #expect(!ScanResults().hasYourData)

        let confirmation = try #require(try await model.confirmRebuildable(subTool.id))
        // Every URL is offered to the review, as a caller that did not filter would; only "Your data" enters its plan.
        let everything = try #require(
            try await model.reviewMoveToTrash(subTool.id, urls: results.items.compactMap(\.url)))
        #expect(confirmation.plan.items.allSatisfy { $0.tier == .rebuildable && $0.method == .delete })
        #expect(confirmation.plan.items.count == 2)
        #expect(everything.plan.items.allSatisfy { $0.tier == .yourData && $0.method == .trash })
        #expect(everything.plan.items.map(\.url) == [url("Mine"), url("Other")])

        let review = try #require(
            try await model.reviewMoveToTrash(subTool.id, urls: results.selectedItems(in: .yourData).compactMap(\.url)))
        await review.start()?.value

        #expect(results.items.map(\.url) == [url("a"), url("b"), url("Other")])
        #expect(results.selectedItems(in: .yourData).isEmpty)
        #expect(results.selectedItems(in: .rebuildable).count == 2)
        results.selection = []
        #expect(results.selectedItems.isEmpty)
    }
}
