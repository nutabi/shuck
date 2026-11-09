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
    private let runPlan: RunPlan
    private let onFinish: (RunReport) -> Void

    var id: UUID { plan.run }

    /// The allocated size of the plan's items, as the confirmation states it (SAF-002, SAF-013).
    var totalBytes: Int64 {
        plan.items.reduce(0) { $0 + $1.allocatedSize }
    }

    var phase: RunPhase<RunReport> { run.phase }

    /// - Parameter onFinish: Called with the report when the run ends, so the caller can drop the deleted items.
    init(plan: Plan, runPlan: @escaping RunPlan, onFinish: @escaping (RunReport) -> Void) {
        self.plan = plan
        self.runPlan = runPlan
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
        return run.start(
            onFinish: { report in
                if let report { onFinish(report) }
            },
            work: { () async throws(HistoryError) -> RunReport in try await runPlan(plan) })
    }

    /// Stops the run before its next item (SAF-014). Items already deleted stay deleted, and the report says which.
    func stop() {
        run.stop()
    }
}

extension RunReport {
    /// The items the run deleted, by the URL the scan found them at. An item that keeps its folder and loses only what
    /// is inside it (CAC-004) is listed too: its old size no longer holds.
    var deletedURLs: [URL] {
        outcomes.compactMap { outcome in
            if case .done = outcome.result, outcome.item.method == .delete { outcome.item.url } else { nil }
        }
    }
}
