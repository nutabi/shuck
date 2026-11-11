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
        let folder = context.home.appending(path: folder)
        // A plan refuses a Delete without the rule that justifies it (D-132).
        let rule = method == .delete ? Self.rule(for: folder, tier: tier) : nil
        return ScanItem(
            url: folder.appending(path: name), snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), tier: tier,
            method: method, reason: "Stub", source: StubRebuildable.id, category: category, selection: selection,
            ruleMatch: rule.map { RuleMatch(rule: $0, modified: .distantPast) })
    }

    /// A Delete rule for every item in `folder`. `nil` for a tier that never deletes, whose plan is refused anyway.
    static func rule(for folder: URL, tier: Tier) -> CleanupRule? {
        guard let documentation = URL(string: "https://example.test/stub") else { return nil }
        return try? CleanupRule(
            id: "stub", name: "Stub", description: "Stub", category: ItemCategory(id: "stub", name: "Stub"),
            detection: .folder(folder), action: .paths([RulePath(root: folder, pattern: "*")], method: .delete),
            tier: tier, selection: .always, explanation: "Stub", documentation: documentation)
    }

    func scannedModel(
        items: [ScanItem], runPlan: RunPlan? = nil, readFreeSpace: @escaping ReadFreeSpace = { nil }
    ) async -> (FileCleanupModel, StubRebuildable) {
        let subTool = StubRebuildable(items: items)
        let model = FileCleanupModel(
            subTools: [subTool], context: context, runPlan: runPlan, readFreeSpace: readFreeSpace)
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

    /// A Tool item for `command`, with a size estimate.
    func toolItem(_ arguments: [String], estimate: Int64) throws -> ScanItem {
        let command = try ToolCommand(
            executable: "/StubTools/cleaner", arguments: arguments, environment: ["PATH": "/usr/bin"])
        return ScanItem(
            command: command, allocatedSize: estimate, tier: .rebuildable, reason: "Stub", source: StubRebuildable.id,
            category: xcode, selection: .selected)
    }

    /// SAF-003, SAF-004, SAF-010, D-125: a plan with a tool's command is worded as cleaning up, and a plan of deleted
    /// items as deleting.
    @Test func aPlanWithAToolCommandIsWordedAsCleaningUpSAF010() async throws {
        let (model, subTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode), try toolItem(["clean"], estimate: 5_000)],
            runPlan: run(deleting: []))
        let mixed = try #require(try model.confirmRebuildable(subTool))
        #expect(mixed.runsTools)
        #expect(mixed.totalBytes == 6_000)
        #expect(mixed.categoryTotals.map(\.count) == [2])

        let (other, otherTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode)], runPlan: run(deleting: []))
        #expect(try #require(try other.confirmRebuildable(otherTool)).runsTools == false)
    }

    /// SAF-011: a command that ran leaves the list like a deleted item; one that did not run stays.
    @Test func aCommandThatRanLeavesTheListAndTheEstimateSAF011() async throws {
        let (model, subTool) = await scannedModel(
            items: [try toolItem(["one"], estimate: 5_000), try toolItem(["two"], estimate: 2_000)],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                RunReport(
                    run: plan.run,
                    outcomes: plan.items.enumerated().map { index, item in
                        ItemOutcome(
                            item: item, result: index == 0 ? .done(nil) : .skipped(.toolUnavailable(.notAnExecutable)))
                    })
            })
        let confirmation = try #require(try model.confirmRebuildable(subTool))

        await confirmation.start()?.value

        let remaining = try #require(model.scanResults[subTool.id])
        #expect(remaining.items.map(\.allocatedSize) == [2_000])
        #expect(remaining.selection.count == 1)
        guard case .scanned(let summary) = model.state(of: subTool.id) else {
            Issue.record("The sub-tool lost its scan")
            return
        }
        #expect(summary.reclaimableBytes == 2_000)
    }

    /// SAF-013: free space is read before the run and after it, and the estimate is what was deleted and what the
    /// tools that ran said they may remove; a skipped item counts for nothing.
    @Test func theSummaryMeasuresTheChangeInFreeSpaceSAF013() async throws {
        let readings = FreeSpaceReadings([10_000_000_000, 10_000_004_000])
        let (model, subTool) = await scannedModel(
            items: [
                item("a", size: 3_000, category: xcode), item("b", size: 9_000, category: xcode),
                try toolItem(["clean"], estimate: 1_000),
            ],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                RunReport(
                    run: plan.run,
                    outcomes: plan.items.map { item in
                        ItemOutcome(
                            item: item, result: item.url?.lastPathComponent == "b" ? .skipped(.missing) : .done(nil))
                    })
            },
            readFreeSpace: readings.read)
        let confirmation = try #require(try model.confirmRebuildable(subTool))
        #expect(confirmation.freeSpace == nil)

        await confirmation.start()?.value

        let change = try #require(confirmation.freeSpace)
        #expect(change.measured == 4_000)
        #expect(change.estimate == 4_000)
        #expect(change.gaps == [.toolEstimate])
        #expect(readings.count == 2)
    }

    /// D-125: a tool with no estimate adds nothing to it, and the summary says its size is not known.
    @Test func aToolWithoutAnEstimateIsLeftOutOfTheEstimateD125() async throws {
        let readings = FreeSpaceReadings([10_000_000_000, 10_500_000_000])
        let (model, subTool) = await scannedModel(
            items: [try toolItem(["unavailable"], estimate: 0)],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                RunReport(run: plan.run, outcomes: plan.items.map { ItemOutcome(item: $0, result: .done(nil)) })
            },
            readFreeSpace: readings.read)
        let confirmation = try #require(try model.confirmRebuildable(subTool))

        await confirmation.start()?.value

        let change = try #require(confirmation.freeSpace)
        #expect(change.estimate == 0)
        #expect(change.gaps == [.toolSizeUnknown])
    }

    /// Without both readings there is nothing to compare, and the summary states only the estimate.
    @Test func withoutAReadingThereIsNoMeasuredChangeSAF013() async throws {
        let readings = FreeSpaceReadings([10_000_000_000, nil])
        let (model, subTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode)], runPlan: run(deleting: ["a"]),
            readFreeSpace: readings.read)
        let confirmation = try #require(try model.confirmRebuildable(subTool))

        await confirmation.start()?.value

        #expect(confirmation.freeSpace == nil)
        #expect(readings.count == 2)
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
