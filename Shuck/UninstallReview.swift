import Foundation
import ShuckExecution
import ShuckKit

/// One uninstall: the review of the app bundle and the chosen leftovers, Quit if the app is running, and the run
/// (APP-006, APP-007, SAF-002, SAF-011).
///
/// It wraps a ``TrashReview``, which fixes the plan, runs it and reports. What it adds is the quit: while the app runs,
/// Move to Trash stays off, and Quit asks the app to quit the way Cmd-Q does, never by force, then waits until the app
/// has gone. `UninstallReviewSheet` shows it.
@Observable
final class UninstallReview: Identifiable {
    /// Whether the app is running, and so what the review offers before it can move anything.
    nonisolated enum Quit: Equatable {
        /// The app is not running, so Move to Trash is on offer.
        case notRunning
        /// The app is running. Quit asks it to quit.
        case running
        /// The request is sent and the review waits for the app to exit, with no time limit: it may show a Save dialog.
        case waiting
        /// No running instance took the request, so the user has to quit the app themselves.
        case notSent
    }

    let app: InstalledApp
    let trash: TrashReview
    private(set) var quit: Quit
    private let quitApp: QuitApp
    private var quitTask: Task<Void, Never>?

    var id: UUID { trash.id }

    init(app: InstalledApp, trash: TrashReview, quitApp: QuitApp) {
        self.app = app
        self.trash = trash
        self.quitApp = quitApp
        quit = .notRunning
        quit = isRunning ? .running : .notRunning
    }

    /// The plan's items that move to the Trash, the bundle first. The review lists these; an agent's `launchctl` step is
    /// not a thing the user chooses, so it is told in a note (APP-011).
    var trashItems: [PlannedItem] {
        trash.plan.items.filter { $0.method == .trash }
    }

    /// The size of the items the review lists. The unload steps are not counted: their plist is, once, as its Trash item.
    var totalBytes: Int64 {
        trashItems.reduce(0) { $0 + $1.allocatedSize }
    }

    /// The LaunchAgent property lists Shuck stops before it moves them (APP-011). The review marks their rows.
    var agents: Set<URL> {
        Set(trash.plan.items.compactMap { $0.method == .launchctl ? $0.url : nil })
    }

    /// Whether the app is running now, by the same list the run checks again before it acts (SAF-009).
    var isRunning: Bool {
        guard let id = app.bundleID?.lowercased() else { return false }
        return quitApp.runningApps.bundleIDs().contains(id)
    }

    /// Whether Move to Trash is on offer: the app has gone, and the plan has an item.
    var canMove: Bool { quit == .notRunning && !trash.plan.items.isEmpty }

    /// Asks the app to quit and waits until it has exited, or returns `nil` if the app is not running or a request is
    /// already waiting (APP-006). Nothing is forced. ``cancelQuit()`` stops the wait.
    @discardableResult
    func quitTheApp() -> Task<Void, Never>? {
        guard quit == .running || quit == .notSent, let bundleID = app.bundleID else { return nil }
        quit = .waiting
        let quitApp = quitApp
        let task = Task {
            let outcome = await quitApp.quit(bundleID: bundleID)
            switch outcome {
            case .exited, .notRunning: quit = .notRunning
            case .requestNotSent: quit = .notSent
            case .cancelled: quit = .running
            }
            quitTask = nil
        }
        quitTask = task
        return task
    }

    /// Stops waiting for the app. It may still quit on its own, and it is never forced (APP-006).
    func cancelQuit() {
        quitTask?.cancel()
    }

    /// Looks at the running apps again, for an app the user quit or started meanwhile. Nothing changes while a request
    /// waits.
    func refresh() {
        guard quit != .waiting else { return }
        quit = isRunning ? (quit == .notSent ? .notSent : .running) : .notRunning
    }

    /// Starts the run, or returns `nil` if the app is running, or the run has started before. The running apps are
    /// read again first, so an app started since the review opened is never moved (APP-006, SAF-009).
    @discardableResult
    func start() -> Task<Void, Never>? {
        refresh()
        guard canMove else { return nil }
        return trash.start()
    }
}
