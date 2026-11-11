import Foundation
import ShuckExecution
import ShuckKit

/// One "Move to Trash" in a sub-tool: the plan the review lists, the run, and its report (SAF-002, SAF-011).
///
/// The plan is fixed when the review opens, and the run acts on exactly that list (PRD section 8.1). A review runs at
/// most once. `TrashReviewSheet` shows it.
@Observable
final class TrashReview: Identifiable {
    let plan: Plan
    /// The plan's items that iCloud keeps on the user's other devices. The review marks them and says that moving them
    /// to the Trash removes them there too (SAF-002, D-129).
    let synced: Set<URL>
    /// The run's phase, start and Stop (``RunModel``). Until it starts, the review is on screen.
    let run = RunModel<RunReport>()
    /// The measured change in free space over the run, once it has ended, if macOS gave both readings (SAF-013).
    private(set) var freeSpace: FreeSpaceChange?
    private let runPlan: RunPlan
    private let readFreeSpace: ReadFreeSpace
    private let onFinish: (RunReport) -> Void

    var id: UUID { plan.run }

    /// The allocated size of the plan's items, as the review states it (SAF-002, SAF-013).
    var totalBytes: Int64 {
        plan.items.reduce(0) { $0 + $1.allocatedSize }
    }

    /// - Parameters:
    ///   - readFreeSpace: Read just before the run and just after it.
    ///   - onFinish: Called with the report when the run ends, so the caller can drop the moved items.
    init(
        plan: Plan, synced: Set<URL> = [], runPlan: @escaping RunPlan, readFreeSpace: @escaping ReadFreeSpace,
        onFinish: @escaping (RunReport) -> Void
    ) {
        self.plan = plan
        self.synced = synced
        self.runPlan = runPlan
        self.readFreeSpace = readFreeSpace
        self.onFinish = onFinish
    }

    var phase: RunPhase<RunReport> { run.phase }

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

    /// Stops the run before its next item (SAF-014). Items already moved stay in the Trash, and the report says which.
    func stop() {
        run.stop()
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
