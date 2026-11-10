import Foundation
import ShuckKit
import os

/// The runs the History page lists, newest first, read from the history log (HIS-002).
///
/// The page reloads each time it appears, so it shows runs made since it was last open. While a reload is under way,
/// the page keeps showing what it read before.
@Observable
final class HistoryModel {
    /// Where reading the log stands.
    nonisolated enum State: Equatable {
        case loading
        case loaded(History)
        /// The log exists but could not be read.
        case failed(HistoryError)
    }

    /// What the log holds: its runs, newest first, and how many of its lines could not be read (HIS-001).
    nonisolated struct History: Equatable {
        let runs: [HistoryRun]
        let unreadableLineCount: Int
    }

    /// Reads the log off the main actor. The app passes ``AppEnvironment/loadHistory()``; tests pass a stub.
    typealias Load = @Sendable () async throws(HistoryError) -> History

    /// The home folder, shown as `~` in folder paths.
    let home: URL
    private(set) var state = State.loading
    /// The restore under way or just finished, which the page shows (HIS-003).
    private(set) var restore: HistoryRestore?
    private let load: Load
    private let runRestore: HistoryRestore.RunRestore?

    /// - Parameter runRestore: Moves items back from the Trash. Without one, as in previews, the page offers no
    ///   Restore, so nothing there can move a file.
    init(home: URL, load: @escaping Load, runRestore: HistoryRestore.RunRestore? = nil) {
        self.home = home
        self.load = load
        self.runRestore = runRestore
    }

    var canRestore: Bool { runRestore != nil }

    /// Restores `items`, at once unless some original paths are taken (D-68), and reloads the log when the run ends.
    /// Returns `nil` if there is nothing to restore, no way to restore, or a restore is still under way.
    @discardableResult
    func restore(_ items: [TrashedItem]) -> HistoryRestore? {
        guard let runRestore, !items.isEmpty, !isRestoring else { return nil }
        let restore = HistoryRestore(items: items, runRestore: runRestore) { [weak self] in
            await self?.reload()
        }
        self.restore = restore
        return restore
    }

    /// Whether a restore is waiting for an answer or running.
    var isRestoring: Bool {
        switch restore?.phase {
        case .waiting?, .running?: true
        default: false
        }
    }

    /// Closes the finished restore's summary, or cancels a restore still waiting for an answer.
    func dismissRestore() {
        guard restore?.phase != .running else { return }
        restore = nil
    }

    func reload() async {
        do throws(HistoryError) {
            state = .loaded(try await load())
        } catch {
            Logger.app.error("Cannot read the history log: \(String(describing: error), privacy: .private)")
            state = .failed(error)
        }
    }
}
