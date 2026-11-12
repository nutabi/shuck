import Foundation
import Observation
import ShuckExecution
import ShuckKit

/// Where one run stands, whatever it does: the same four steps for Move to Trash, Restore and every run to come
/// (SAF-011, TD-06).
nonisolated enum RunPhase<Report: Equatable & Sendable>: Equatable {
    /// Nothing has happened yet: the review or the question is on screen, and the user may still cancel.
    case waiting
    case running
    /// Every item has an outcome: done, skipped or failed, with a reason (SAF-011).
    case finished(Report)
    /// The history log could not be opened, so nothing ran (SAF-005).
    case failed(HistoryError)
}

/// Runs a plan's items, whatever their method (PRD section 8.1). The app passes ``AppEnvironment/run(_:)``; tests pass
/// a stub.
typealias RunPlan = @Sendable (Plan) async throws(HistoryError) -> RunReport

/// The scaffolding every run shares: its phase, a start that works once, Stop and the report (SAF-011, SAF-014).
///
/// A run model belongs to one run. ``TrashReview``, ``HistoryRestore`` and the summary confirmation each hold one
/// and add what is theirs: the plan, the question or the review. ``RunSheet`` shows it.
@Observable
final class RunModel<Report: Equatable & Sendable> {
    private(set) var phase = RunPhase<Report>.waiting
    /// The run, once it has started.
    private(set) var task: Task<Void, Never>?
    private let runs: ActiveRuns

    /// - Parameter runs: Where the run is listed while it is under way, so quitting can ask first (SAF-005).
    init(runs: ActiveRuns = .shared) {
        self.runs = runs
    }

    /// Starts `work`, or returns `nil` if the run has started before.
    /// - Parameters:
    ///   - onFinish: Called when the run ends, after the phase has changed, with its report, or `nil` if the history
    ///     log could not be opened. The task waits for it.
    ///   - work: The run, off the main actor. It throws only if the log cannot be opened, and then nothing ran.
    @discardableResult
    func start(
        onFinish: @escaping (Report?) async -> Void = { _ in },
        work: @escaping @Sendable () async throws(HistoryError) -> Report
    ) -> Task<Void, Never>? {
        guard phase == .waiting else { return nil }
        phase = .running
        let id = UUID()
        let runs = runs
        let task = Task {
            defer { runs.remove(id) }
            do throws(HistoryError) {
                let report = try await work()
                phase = .finished(report)
                await onFinish(report)
            } catch {
                phase = .failed(error)
                await onFinish(nil)
            }
        }
        self.task = task
        runs.add(id, task)
        return task
    }

    /// Stops the run before its next item (SAF-014). Items already acted on stay as they are, and the report says
    /// which.
    func stop() {
        task?.cancel()
    }
}
