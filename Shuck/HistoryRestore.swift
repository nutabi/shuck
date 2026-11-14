import Foundation
import ShuckExecution
import ShuckKit

/// One Restore from the History page: the items to put back, the one question when some original paths are taken, the
/// run, and its report (HIS-003, SAF-011).
///
/// Without a taken path the restore starts at once, without a confirmation, because Restore never overwrites and only
/// puts back what Shuck moved (D-68). With taken paths it waits for one answer, Keep Both or Skip, which applies to all
/// of them. It also waits when an item is the property list of a LaunchAgent that the uninstall unloaded and whose
/// original place is free: one answer, off unless the user turns it on, says whether to load all such agents again
/// (APP-011, HIS-005). Both questions share one screen and one set of buttons. A restore runs at most once. The History page shows it in a ``HistoryRestoreSheet``.
@Observable
final class HistoryRestore: Identifiable {
    /// Moves items back from the Trash. The app passes ``AppEnvironment/restore(_:)``; tests pass a stub.
    typealias RunRestore = @Sendable ([RestoreRequest]) async throws(HistoryError) -> RestoreReport

    let id = UUID()
    /// The items to restore, in the order the page listed them.
    let items: [TrashedItem]
    /// The items whose original path is taken on disk or needed by an earlier item in this restore.
    let takenItems: [TrashedItem]
    /// The items that are the property list of an agent the uninstall unloaded, and whose original place is free, so
    /// Restore can load the agent again if the user says so. A Keep Both copy or a skipped item never is (D-199).
    let agentItems: [TrashedItem]
    /// Whether the user chose to load ``agentItems`` again. It is off by default and never set by the page itself, so
    /// nothing is loaded without the user's choice (APP-011).
    var loadAgents = false
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
        let taken = Set(takenItems.map(\.trashedURL))
        agentItems = items.filter { $0.unloadedAgentLabel != nil && !taken.contains($0.trashedURL) }
        self.runRestore = runRestore
        self.onFinish = onFinish
        if takenItems.isEmpty && agentItems.isEmpty { begin(ifTaken: .skip) }
    }

    /// Starts the restore with the user's answer for the taken paths, and for the agents ``loadAgents``, or returns
    /// `nil` if it has started before.
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
        let agents = loadAgents ? Set(agentItems.map(\.trashedURL)) : []
        let requests = items.map { item in
            RestoreRequest(
                item: item, ifTaken: ifTaken,
                reenableAgentLabel: agents.contains(item.trashedURL) ? item.unloadedAgentLabel : nil)
        }
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
