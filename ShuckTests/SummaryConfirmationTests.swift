import Foundation
import ShuckExecution
import ShuckKit
import Synchronization
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
        items: [ScanItem], runPlan: RunPlan? = nil, readFreeSpace: @escaping ReadFreeSpace = { nil },
        readUsedSpace: @escaping ReadUsedSpace = { nil }
    ) async -> (FileCleanupModel, StubRebuildable) {
        let subTool = StubRebuildable(items: items)
        let model = FileCleanupModel(
            subTools: [subTool], context: context, runPlan: runPlan, readFreeSpace: readFreeSpace,
            readUsedSpace: readUsedSpace)
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

    /// A Tool item for `command`, with a size estimate.
    func toolItem(_ arguments: [String], estimate: Int64) throws -> ScanItem {
        let command = try ToolCommand(
            executable: "/StubTools/cleaner", arguments: arguments, environment: ["PATH": "/usr/bin"])
        return ScanItem(
            command: command, allocatedSize: estimate, tier: .rebuildable, reason: "Stub", source: StubRebuildable.id,
            category: xcode, selection: .selected)
    }

    /// The plan holds only the selected Rebuildable items, in the order the scan found them, and the confirmation
    /// totals each category in the order the plan names them (SAF-003, SAF-004). A plan with a tool's command is worded
    /// as cleaning up (SAF-010, D-125). The guard refuses an item outside the sub-tool's roots, and nothing is planned
    /// (SAF-007). A model without a run offers no confirmation, so nothing in tests and previews can delete a file.
    @Test func theConfirmationTotalsAndPlansOnlyTheSelectedItemsSAF003SAF004SAF007SAF010() async throws {
        let (model, subTool) = await scannedModel(
            items: [
                item("a", size: 1_000, category: xcode), item("b", size: 5_000, category: simulators),
                item("c", size: 2_000, category: xcode),
                item("unselected", size: 2_000, category: xcode, selection: .unselected),
                item("running", size: 4_000, category: xcode, selection: .disabled("App is running")),
                // "Your data" needs the itemized Trash review, not this confirmation.
                item("mine", size: 8_000, category: xcode, tier: .yourData, method: .trash),
            ],
            runPlan: run(deleting: []))

        let confirmation = try #require(try await model.confirmRebuildable(subTool))

        #expect(confirmation.categoryTotals.map(\.id) == ["xcode", "simulators"])
        #expect(confirmation.categoryTotals.map(\.count) == [2, 1])
        #expect(confirmation.categoryTotals.map(\.bytes) == [3_000, 5_000])
        #expect(confirmation.totalBytes == 8_000)
        #expect(confirmation.plan.items.map(\.url) == [url("a"), url("b"), url("c")])
        #expect(confirmation.plan.items.allSatisfy { $0.tier == .rebuildable && $0.method == .delete })
        #expect(confirmation.phase == .waiting)
        #expect(!confirmation.runsTools)

        let (mixedModel, mixedTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode), try toolItem(["clean"], estimate: 5_000)],
            runPlan: run(deleting: []))
        let mixed = try #require(try await mixedModel.confirmRebuildable(mixedTool))
        #expect(mixed.runsTools)
        #expect(mixed.totalBytes == 6_000)
        #expect(mixed.categoryTotals.map(\.count) == [2])

        let (guarded, guardedTool) = await scannedModel(
            items: [
                item("a", size: 1_000, category: xcode),
                item("Documents", size: 1_000, category: xcode, folder: "Documents"),
            ],
            runPlan: run(deleting: []))
        await #expect(throws: PlanError.self) { try await guarded.confirmRebuildable(guardedTool) }

        let (noRun, noRunTool) = await scannedModel(items: [item("a", size: 1_000, category: xcode)])
        #expect(!noRun.canRun)
        #expect(try await noRun.confirmRebuildable(noRunTool) == nil)
    }

    /// Deleted items and commands that ran leave the list and the estimate, and skipped ones stay (SAF-011). Free space
    /// is read before the run and after it, and the estimate is what was deleted and what the tools that ran said they
    /// may remove; a skipped item counts for nothing (SAF-013).
    @Test func aRunUpdatesTheListAndMeasuresTheChangeInFreeSpaceSAF011SAF013() async throws {
        let readings = FreeSpaceReadings([10_000_000_000, 10_000_004_000])
        let (model, subTool) = await scannedModel(
            items: [
                item("a", size: 3_000, category: xcode), item("b", size: 9_000, category: xcode),
                try toolItem(["clean"], estimate: 1_000), try toolItem(["two"], estimate: 2_000),
            ],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                RunReport(
                    run: plan.run,
                    outcomes: plan.items.map { item in
                        // The second command (estimate 2,000) is not an executable; "b" is gone.
                        let result: ItemOutcome.Result =
                            switch (item.url?.lastPathComponent, item.allocatedSize) {
                            case ("b", _): .skipped(.missing)
                            case (nil, 2_000): .skipped(.toolUnavailable(.notAnExecutable))
                            default: .done(nil)
                            }
                        return ItemOutcome(item: item, result: result)
                    })
            },
            readFreeSpace: readings.read)
        let confirmation = try #require(try await model.confirmRebuildable(subTool))
        #expect(confirmation.freeSpace == nil)

        await confirmation.start()?.value

        guard case .finished(let report) = confirmation.phase else {
            Issue.record("Not finished: \(confirmation.phase)")
            return
        }
        #expect(report.deletedURLs == [url("a")])
        let remaining = try #require(model.scanResults[subTool.id])
        #expect(remaining.items.map(\.allocatedSize) == [9_000, 2_000])
        #expect(remaining.selection.count == 2)
        guard case .scanned(let summary) = model.state(of: subTool.id) else {
            Issue.record("The sub-tool lost its scan")
            return
        }
        #expect(summary.reclaimableBytes == 11_000)
        let change = try #require(confirmation.freeSpace)
        #expect(change.measured == 4_000)
        #expect(change.estimate == 4_000)
        #expect(change.gaps == [.toolEstimate])
        #expect(readings.count == 2)
    }

    /// D-125: a tool with no estimate adds nothing to it, and the summary says its size is not known (SAF-013). Without
    /// both readings there is nothing to compare, and the summary states only the estimate.
    @Test func aToolWithoutAnEstimateAndAMissingReadingLeaveGapsSAF013D125() async throws {
        let readings = FreeSpaceReadings([10_000_000_000, 10_500_000_000])
        let (model, subTool) = await scannedModel(
            items: [try toolItem(["unavailable"], estimate: 0)],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                RunReport(run: plan.run, outcomes: plan.items.map { ItemOutcome(item: $0, result: .done(nil)) })
            },
            readFreeSpace: readings.read)
        let confirmation = try #require(try await model.confirmRebuildable(subTool))

        await confirmation.start()?.value

        let change = try #require(confirmation.freeSpace)
        #expect(change.estimate == 0)
        #expect(change.gaps == [.toolSizeUnknown])

        let missing = FreeSpaceReadings([10_000_000_000, nil])
        let (otherModel, otherTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode)], runPlan: run(deleting: ["a"]),
            readFreeSpace: missing.read)
        let other = try #require(try await otherModel.confirmRebuildable(otherTool))

        await other.start()?.value

        #expect(other.freeSpace == nil)
        #expect(missing.count == 2)
    }

    /// SAF-015, D-144: an item larger than a quarter of the used space waits for a second confirmation, and nothing runs
    /// before it. One within the threshold, or without a reading of the used space, needs only the one confirmation.
    @Test func anOversizedItemNeedsASecondConfirmationSAF015() async throws {
        let calls = Mutex(0)
        let (model, subTool) = await scannedModel(
            items: [item("huge", size: 30_000, category: xcode), item("small", size: 1_000, category: xcode)],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                calls.withLock { $0 += 1 }
                return RunReport(run: plan.run, outcomes: plan.items.map { ItemOutcome(item: $0, result: .done(nil)) })
            },
            readUsedSpace: { 100_000 })
        let confirmation = try #require(try await model.confirmRebuildable(subTool))

        #expect(confirmation.threshold?.bytes == 25_000)
        #expect(confirmation.oversized.map(\.url) == [url("huge")])
        #expect(confirmation.needsSecondConfirmation)
        #expect(confirmation.start() == nil)
        #expect(confirmation.phase == .waiting)

        confirmation.confirmedOversized = true
        await confirmation.start()?.value

        #expect(calls.withLock { $0 } == 1)
        #expect(model.scanResults[subTool.id]?.items.isEmpty == true)

        let (withinModel, withinTool) = await scannedModel(
            items: [item("a", size: 25_000, category: xcode)], runPlan: run(deleting: ["a"]),
            readUsedSpace: { 100_000 })
        let within = try #require(try await withinModel.confirmRebuildable(withinTool))
        #expect(within.oversized.isEmpty)
        #expect(!within.needsSecondConfirmation)
        await within.start()?.value
        #expect(within.phase != .waiting)

        let (unknownModel, unknownTool) = await scannedModel(
            items: [item("a", size: 1_000_000, category: xcode)], runPlan: run(deleting: ["a"]))
        let unknown = try #require(try await unknownModel.confirmRebuildable(unknownTool))
        #expect(unknown.threshold == nil)
        #expect(!unknown.needsSecondConfirmation)
    }

    /// A run that cannot open the history log deletes nothing (SAF-005), and a stopped run skips every item that has not
    /// started (SAF-014); either way the list stays as it was.
    @Test func aFailedOrStoppedRunLeavesTheListAloneSAF005SAF014() async throws {
        let failure = HistoryError.cannotOpen("/StubHome/Library/Application Support/me.nutabi.shuck", errno: EACCES)
        let (failed, failedTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode)],
            runPlan: { (_: Plan) async throws(HistoryError) -> RunReport in throw failure })
        let failedConfirmation = try #require(try await failed.confirmRebuildable(failedTool))

        await failedConfirmation.start()?.value

        #expect(failedConfirmation.phase == .failed(failure))
        #expect(failed.scanResults[failedTool.id]?.items.count == 1)

        let (model, subTool) = await scannedModel(
            items: [item("a", size: 1_000, category: xcode), item("b", size: 3_000, category: xcode)],
            runPlan: { (plan: Plan) async throws(HistoryError) -> RunReport in
                // Only a cancelled run reports its items as cancelled, so a run that is never stopped fails the test.
                let result: ItemOutcome.Result = await waitUntilCancelled() ? .skipped(.cancelled) : .done(nil)
                return RunReport(run: plan.run, outcomes: plan.items.map { ItemOutcome(item: $0, result: result) })
            })
        let confirmation = try #require(try await model.confirmRebuildable(subTool))

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
