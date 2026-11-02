import Foundation
import ShuckExecution
import ShuckKit

/// One "Move to Trash" in a personal-files sub-tool: the plan the review lists, the run, and its report (SAF-002,
/// SAF-011).
///
/// The plan is fixed when the review opens, and the run acts on exactly that list (PRD section 8.1). A review runs at
/// most once. `TrashReviewSheet` shows it.
@Observable
final class TrashReview: Identifiable {
    /// Where the review stands.
    nonisolated enum Phase: Equatable {
        /// The plan is listed and nothing has moved.
        case reviewing
        case running
        /// Every item has an outcome: moved, skipped or failed, with a reason (SAF-011).
        case finished(RunReport)
        /// The history log could not be opened, so nothing moved (SAF-005).
        case failed(HistoryError)
    }

    /// Moves a plan's items to the Trash. The app passes ``AppEnvironment/run(_:)``; tests pass a stub.
    typealias RunPlan = @Sendable (Plan) async throws(HistoryError) -> RunReport

    let plan: Plan
    private(set) var phase = Phase.reviewing
    private let runPlan: RunPlan
    private let onFinish: (RunReport) -> Void
    private var task: Task<Void, Never>?

    var id: UUID { plan.run }

    /// The allocated size of the plan's items, as the review states it (SAF-002, SAF-013).
    var totalBytes: Int64 {
        plan.items.reduce(0) { $0 + $1.snapshot.allocatedSize }
    }

    /// - Parameter onFinish: Called with the report when the run ends, so the caller can drop the moved items.
    init(plan: Plan, runPlan: @escaping RunPlan, onFinish: @escaping (RunReport) -> Void) {
        self.plan = plan
        self.runPlan = runPlan
        self.onFinish = onFinish
    }

    /// Starts the run, or returns `nil` if it has started before.
    @discardableResult
    func start() -> Task<Void, Never>? {
        guard phase == .reviewing else { return nil }
        phase = .running
        let task = Task {
            do throws(HistoryError) {
                let report = try await runPlan(plan)
                phase = .finished(report)
                onFinish(report)
            } catch {
                phase = .failed(error)
            }
        }
        self.task = task
        return task
    }

    /// Stops the run before its next item (SAF-014). Items already moved stay in the Trash, and the report says which.
    func stop() {
        task?.cancel()
    }
}

extension RunReport {
    /// The items the run moved to the Trash, by the URL the scan found them at.
    var trashedURLs: [URL] {
        outcomes.compactMap { outcome in
            if case .done = outcome.result, outcome.item.method == .trash { outcome.item.url } else { nil }
        }
    }
}
