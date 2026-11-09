import Foundation
import ShuckExecution
import ShuckKit

/// One Restore from the History page: the items to put back, the one question when some original paths are taken, the
/// run, and its report (HIS-003, SAF-011).
///
/// Without a taken path the restore starts at once, without a confirmation, because Restore never overwrites and only
/// puts back what Shuck moved (D-68). With taken paths it waits for one answer, Keep Both or Skip, which applies to all
/// of them. A restore runs at most once. The History page shows it in a ``HistoryRestoreSheet``.
@Observable
final class HistoryRestore: Identifiable {
    /// Moves items back from the Trash. The app passes ``AppEnvironment/restore(_:)``; tests pass a stub.
    typealias RunRestore = @Sendable ([RestoreRequest]) async throws(HistoryError) -> RestoreReport

    let id = UUID()
    /// The items to restore, in the order the page listed them.
    let items: [TrashedItem]
    /// The items whose original path is taken on disk or needed by an earlier item in this restore.
    let takenItems: [TrashedItem]
    /// The run's phase, start and Stop (``RunModel``). Until it starts, the question is on screen, if there is one.
    let run = RunModel<RestoreReport>()
    private let runRestore: RunRestore
    private let onFinish: () async -> Void

    /// The allocated size of the items, as logged when they were trashed.
    var totalBytes: Int64 {
        items.reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    /// Checks which original paths are taken and, if none is, starts the restore.
    /// - Parameter onFinish: Called when the run ends, so the History page can reload the log. The run's task
    ///   waits for it.
    init(items: [TrashedItem], runRestore: @escaping RunRestore, onFinish: @escaping () async -> Void) {
        self.items = items
        // One lstat per item, which is fast enough on the main actor for a run's items (NFR-PERF-001).
        var destinations: Set<URL> = []
        takenItems = items.filter { item in
            !destinations.insert(item.originalURL).inserted || item.originalIsTaken
        }
        self.runRestore = runRestore
        self.onFinish = onFinish
        if takenItems.isEmpty { begin(ifTaken: .skip) }
    }

    /// Starts the restore with the user's answer for the taken paths, or returns `nil` if it has started before.
    @discardableResult
    func start(ifTaken: RestoreRequest.IfTaken) -> Task<Void, Never>? {
        begin(ifTaken: ifTaken)
    }

    var phase: RunPhase<RestoreReport> { run.phase }

    /// Stops the run before its next item (SAF-014). Items already restored stay restored, and the report says which.
    func stop() {
        run.stop()
    }

    @discardableResult
    private func begin(ifTaken: RestoreRequest.IfTaken) -> Task<Void, Never>? {
        let requests = items.map { RestoreRequest(item: $0, ifTaken: ifTaken) }
        let runRestore = runRestore
        return run.start(
            onFinish: { [onFinish] _ in await onFinish() },
            work: { () async throws(HistoryError) -> RestoreReport in try await runRestore(requests) })
    }
}

extension HistoryRun {
    /// The items Restore can put back now: moved to the Trash by this run, and still there (HIS-003, HIS-004).
    var restorableItems: [TrashedItem] {
        items.compactMap(\.restorableItem)
    }
}

extension HistoryRun.Item {
    /// The item as Restore puts it back, if it is still in the Trash (HIS-004).
    var restorableItem: TrashedItem? {
        if case .restorable(let trashed)? = restorability { trashed } else { nil }
    }
}
