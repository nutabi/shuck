import Foundation
import ShuckExecution
import ShuckKit
import Testing

@testable import Shuck

/// The summary confirmation for "Rebuildable" items: the plan, the totals per category, the run and the removal of
/// deleted items (SAF-003, SAF-006, SAF-011).
///
/// The scan and the run are stubs, so these tests never touch the file system. The engine's fixture tests delete real
/// folders (`DeveloperJunkPipelineTests`).
@MainActor
struct SummaryConfirmationTests {
    let context = ScanContext(home: URL(filePath: "/StubHome", directoryHint: .isDirectory))
    let xcode = ItemCategory(id: "xcode", name: "Xcode")
    let simulators = ItemCategory(id: "simulators", name: "Simulators")

    func url(_ path: String) -> URL { context.home.appending(path: "Library/Caches").appending(path: path) }

    func item(
        _ name: String, size: Int64, category: ItemCategory, tier: Tier = .rebuildable,
        method: ActionMethod = .delete, selection: ItemSelection = .selected, folder: String = "Library/Caches"
    ) -> ScanItem {
        ScanItem(
            url: context.home.appending(path: folder).appending(path: name),
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), tier: tier, method: method, reason: "Stub",
            source: StubRebuildable.id, category: category, selection: selection)
    }

    func scannedModel(items: [ScanItem], runPlan: RunPlan? = nil) async -> (FileCleanupModel, StubRebuildable) {
        let subTool = StubRebuildable(items: items)
        let model = FileCleanupModel(subTools: [subTool], context: context, runPlan: runPlan)
        await model.scan(subTool)?.value
        return (model, subTool)
    }

    /// A run that deletes the items named in `deleted` and skips the others as missing.
    func run(deleting deleted: Set<String>) -> RunPlan {
        { (plan: Plan) async throws(HistoryError) -> RunReport in
            RunReport(
                run: plan.run,
                outcomes: plan.items.map { item in
                    let name = item.url?.lastPathComponent ?? ""
                    return ItemOutcome(item: item, result: deleted.contains(name) ? .done(nil) : .skipped(.missing))
                })
        }
    }

    @Test func theConfirmationTotalsEachCategoryInTheOrderThePlanNamesThemSAF003() async throws {
        let (model, subTool) = await scannedModel(
            items: [
                item("a", size: 1_000, category: xcode), item("b", size: 5_000, category: simulators),
                item("c", size: 2_000, category: xcode),
            ],
            runPlan: run(deleting: []))

        let confirmation = try #require(try model.confirmRebuildable(subTool))

        #expect(confirmation.categoryTotals.map(\.id) == ["xcode", "simulators"])
        #expect(confirmation.categoryTotals.map(\.count) == [2, 1])
        #expect(confirmation.categoryTotals.map(\.bytes) == [3_000, 5_000])
        #expect(confirmation.totalBytes == 8_000)
        #expect(confirmation.plan.items.map(\.url) == [url("a"), url("b"), url("c")])
        #expect(confirmation.plan.items.allSatisfy { $0.tier == .rebuildable && $0.method == .delete })
        #expect(confirmation.phase == .waiting)
    }

    @Test func onlyTheSelectedRebuildableItemsEnterThePlanSAF003SAF004() async throws {
        let (model, subTool) = await scannedModel(
            items: [
                item("selected", size: 1_000, category: xcode),
                item("unselected", size: 2_000, category: xcode, selection: .unselected),
                item("running", size: 4_000, category: xcode, selection: .disabled("App is running")),
                // "Your data" needs the itemized Trash review, not this confirmation.
                item("mine", size: 8_000, category: xcode, tier: .yourData, method: .trash),
            ],
            runPlan: run(deleting: []))

        let confirmation = try #require(try model.confirmRebuildable(subTool))

        #expect(confirmation.plan.items.map(\.url) == [url("selected")])
    }

    @Test func deletedItemsLeaveTheListAndTheEstimateButSkippedOnesStaySAF011() async throws {
        let (model, subTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode), item("b", size: 3_000, category: xcode)],
            runPlan: run(deleting: ["a"]))
        let confirmation = try #require(try model.confirmRebuildable(subTool))

        await confirmation.start()?.value

        guard case .finished(let report) = confirmation.phase else {
            Issue.record("Not finished: \(confirmation.phase)")
            return
        }
        #expect(report.deletedURLs == [url("a")])
        #expect(model.scanResults[subTool.id]?.items.map(\.url) == [url("b")])
        guard case .scanned(let summary) = model.state(of: subTool.id) else {
            Issue.record("The sub-tool lost its scan")
            return
        }
        #expect(summary.reclaimableBytes == 3_000)
    }

    @Test func aConfirmationRunsOnce() async throws {
        let (model, subTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode)], runPlan: run(deleting: ["a"]))
        let confirmation = try #require(try model.confirmRebuildable(subTool))

        let first = confirmation.start()
        #expect(confirmation.phase == .running)
        #expect(confirmation.start() == nil)
        await first?.value
        #expect(confirmation.start() == nil)
    }

    @Test func withoutAHistoryLogNothingIsDeletedSAF005() async throws {
        let failure = HistoryError.cannotOpen("/StubHome/Library/Application Support/me.nutabi.shuck", errno: EACCES)
        let (model, subTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode)],
            runPlan: { (_: Plan) async throws(HistoryError) -> RunReport in throw failure })
        let confirmation = try #require(try model.confirmRebuildable(subTool))

        await confirmation.start()?.value

        #expect(confirmation.phase == .failed(failure))
        #expect(model.scanResults[subTool.id]?.items.count == 1)
    }

    @Test func stoppingCancelsTheRunBeforeTheNextItemSAF014() async throws {
        let (model, subTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode), item("b", size: 3_000, category: xcode)],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                while !Task.isCancelled { await Task.yield() }
                return RunReport(
                    run: plan.run, outcomes: plan.items.map { ItemOutcome(item: $0, result: .skipped(.cancelled)) })
            })
        let confirmation = try #require(try model.confirmRebuildable(subTool))

        let task = confirmation.start()
        confirmation.stop()
        await task?.value

        guard case .finished(let report) = confirmation.phase else {
            Issue.record("Not finished: \(confirmation.phase)")
            return
        }
        #expect(report.outcomes.map(\.result) == [.skipped(.cancelled), .skipped(.cancelled)])
        #expect(report.deletedURLs.isEmpty)
        #expect(model.scanResults[subTool.id]?.items.count == 2)
    }

    @Test func theGuardRefusesAnItemOutsideTheSubToolsRootsAndNothingIsPlannedSAF007() async throws {
        let (model, subTool) = await scannedModel(
            items: [
                item("a", size: 1_000, category: xcode),
                item("Documents", size: 1_000, category: xcode, folder: "Documents"),
            ],
            runPlan: run(deleting: []))

        #expect(throws: PlanError.self) { try model.confirmRebuildable(subTool) }
    }

    /// Tests and previews give the model no run, so nothing in them can delete a file.
    @Test func aModelWithoutARunOffersNoConfirmation() async throws {
        let (model, subTool) = await scannedModel(items: [item("a", size: 1_000, category: xcode)])

        #expect(!model.canRun)
        #expect(try model.confirmRebuildable(subTool) == nil)
    }

    @Test func aSkippedOrFailedDeleteReadsLikeHistorySAF011() {
        func text(_ result: ItemOutcome.Result) -> String {
            let item = PlannedItem(
                url: url("a"), tier: .rebuildable, method: .delete,
                snapshot: ItemSnapshot(kind: .folder, allocatedSize: 10))
            return String(localized: OutcomeWording.result(of: ItemOutcome(item: item, result: result)))
        }

        #expect(text(.done(nil)) == "Deleted permanently")
        #expect(text(.skipped(.modifiedSinceScan)) == "Skipped: modified since the scan")
        #expect(text(.skipped(.appRunning)) == "Skipped: its app was running")
        #expect(text(.failed(ActionError(errno: EACCES))) == "Failed: Permission denied")
    }
}

/// A "Rebuildable" sub-tool whose scan reports fixed items under the caches folder.
struct StubRebuildable: SubTool {
    static let id = ToolID(rawValue: "TSR")
    let info = ToolInfo(
        id: Self.id, name: "Stub", summary: "Reports fixed items.", symbolName: "testtube.2", availability: .available)
    let tiers: Set<Tier> = [.rebuildable, .yourData]
    let items: [ScanItem]

    func allowedRoots(home: URL) -> [URL] { [home.appending(path: "Library/Caches")] }

    func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            for item in items {
                continuation.yield(.item(item))
            }
            continuation.finish()
        }
    }
}
