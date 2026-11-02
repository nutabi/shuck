import Foundation
import ShuckKit

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
    private let load: Load

    init(home: URL, load: @escaping Load) {
        self.home = home
        self.load = load
    }

    func reload() async {
        do throws(HistoryError) {
            state = .loaded(try await load())
        } catch {
            state = .failed(error)
        }
    }
}
