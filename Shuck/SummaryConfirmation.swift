import Foundation
import ShuckExecution
import ShuckKit

/// One summary confirmation: the plan for "Rebuildable" items, their totals per category, the run and its report
/// (SAF-003, SAF-006, SAF-011).
///
/// Rebuildable items are deleted permanently, so unlike Move to Trash the review is not one row per item: it states the
/// totals per category, and the full list is one click away. The plan is fixed when the confirmation opens, and the run
/// acts on exactly that list (PRD section 8.1). A confirmation runs at most once. `SummaryConfirmationSheet` shows it.
@Observable
final class SummaryConfirmation: Identifiable {
    /// What one category of the plan holds.
    nonisolated struct CategoryTotal: Identifiable, Equatable {
        let category: ItemCategory
        let count: Int
        /// The allocated size of the category's items, in bytes (SAF-013).
        let bytes: Int64

        var id: String { category.id }
    }

    let plan: Plan
    /// The run's phase, start and Stop (``RunModel``). Until it starts, the confirmation is on screen.
    let run = RunModel<RunReport>()
    /// The categories in the order the plan first names them.
    let categoryTotals: [CategoryTotal]
    /// The measured change in free space over the run, once it has ended, if macOS gave both readings (SAF-013).
    private(set) var freeSpace: FreeSpaceChange?
    private let runPlan: RunPlan
    private let readFreeSpace: ReadFreeSpace
    private let onFinish: (RunReport) -> Void

    var id: UUID { plan.run }

    /// The allocated size of the plan's items, as the confirmation states it (SAF-002, SAF-013).
    var totalBytes: Int64 {
        plan.items.reduce(0) { $0 + $1.allocatedSize }
    }

    var phase: RunPhase<RunReport> { run.phase }

    /// Whether the plan runs a tool's own cleanup command for some item. Its wording then says "Clean Up" where a plan of
    /// only deleted items says "Delete", since a tool decides what it removes (SAF-010, D-125).
    var runsTools: Bool {
        plan.items.contains { $0.method == .tool }
    }

    /// - Parameters:
    ///   - readFreeSpace: Read just before the run and just after it.
    ///   - onFinish: Called with the report when the run ends, so the caller can drop the deleted items.
    init(
        plan: Plan, runPlan: @escaping RunPlan, readFreeSpace: @escaping ReadFreeSpace,
        onFinish: @escaping (RunReport) -> Void
    ) {
        self.plan = plan
        self.runPlan = runPlan
        self.readFreeSpace = readFreeSpace
        self.onFinish = onFinish
        var totals: [CategoryTotal] = []
        for item in plan.items {
            if let index = totals.firstIndex(where: { $0.category.id == item.category.id }) {
                let total = totals[index]
                totals[index] = CategoryTotal(
                    category: total.category, count: total.count + 1, bytes: total.bytes + item.allocatedSize)
            } else {
                totals.append(CategoryTotal(category: item.category, count: 1, bytes: item.allocatedSize))
            }
        }
        categoryTotals = totals
    }

    /// Starts the run, or returns `nil` if it has started before.
    @discardableResult
    func start() -> Task<Void, Never>? {
        let plan = plan
        let runPlan = runPlan
        let onFinish = onFinish
        let readFreeSpace = readFreeSpace
        // Reading the volume's numbers takes well under a millisecond, so the main actor reads them (NFR-PERF-001).
        let before = run.phase == .waiting ? readFreeSpace() : nil
        return run.start(
            onFinish: { [weak self] report in
                guard let report else { return }
                self?.freeSpace = FreeSpaceChange(before: before, after: readFreeSpace(), report: report)
                onFinish(report)
            },
            work: { () async throws(HistoryError) -> RunReport in try await runPlan(plan) })
    }

    /// Stops the run before its next item (SAF-014). Items already deleted stay deleted, and the report says which.
    func stop() {
        run.stop()
    }
}

extension RunReport {
    /// The tool commands the run ran to the end, which leave the list as the deleted items do: what the tool removed is
    /// gone, and its old estimate no longer holds.
    var cleanedCommands: [ToolCommand] {
        outcomes.compactMap { outcome in
            if case .done = outcome.result, case .command(let command) = outcome.item.target { command } else { nil }
        }
    }

    /// The items the run deleted, by the URL the scan found them at. An item that keeps its folder and loses only what
    /// is inside it (CAC-004) is listed too: its old size no longer holds.
    var deletedURLs: [URL] {
        outcomes.compactMap { outcome in
            if case .done = outcome.result, outcome.item.method == .delete { outcome.item.url } else { nil }
        }
    }
}
