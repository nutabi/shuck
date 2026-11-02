import Foundation

/// The main window's sidebar selection, shared through the environment so one page can open another, as the run
/// summary opens History.
@Observable
final class AppNavigation {
    var selection: SidebarDestination? = .overview
    /// A run the History page shows expanded when it next appears.
    var revealedRun: UUID?

    /// Opens the History page with `run` expanded.
    func showHistory(revealing run: UUID) {
        revealedRun = run
        selection = .history
    }
}
