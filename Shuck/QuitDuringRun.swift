import AppKit

/// The runs under way, so quitting can ask first and then stop them (SAF-005, SAF-014).
///
/// Every ``RunModel`` adds its task here when it starts and the task removes itself when it ends, after its report is
/// written. A quit while a run is under way must not leave a Trash move without its result record.
@MainActor
final class ActiveRuns {
    static let shared = ActiveRuns()

    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Whether a Move to Trash, Delete, tool run or Restore is under way.
    var isRunning: Bool { !tasks.isEmpty }

    func add(_ id: UUID, _ task: Task<Void, Never>) {
        tasks[id] = task
    }

    func remove(_ id: UUID) {
        tasks[id] = nil
    }

    /// Stops every run before its next item (SAF-014) and returns once each has ended: the item in hand finished and
    /// its result was written.
    func stopAndWait() async {
        let running = Array(tasks.values)
        for task in running { task.cancel() }
        for task in running { await task.value }
    }
}

/// What quitting does, whatever the user answered.
nonisolated enum QuitDecision: Equatable {
    case quitNow
    case keepRunning
    case stopThenQuit

    /// `stopAnswered` is `nil` when no question was asked.
    static func decide(isRunning: Bool, stopAnswered: Bool?) -> QuitDecision {
        guard isRunning else { return .quitNow }
        return stopAnswered == true ? .stopThenQuit : .keepRunning
    }
}

/// Asks before the app quits during a run. Closing the main window quits the app (D-99), so it comes here too.
final class ShuckAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let runs = ActiveRuns.shared
        let isRunning = runs.isRunning
        switch QuitDecision.decide(isRunning: isRunning, stopAnswered: isRunning ? askToStop() : nil) {
        case .quitNow: return .terminateNow
        case .keepRunning: return .terminateCancel
        case .stopThenQuit:
            Task {
                await runs.stopAndWait()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    /// The default button, Return, is "Keep Running". Returns whether the user chose to stop and quit.
    private func askToStop() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Stop the run and quit?")
        alert.informativeText = String(
            localized: "Shuck finishes the item it is working on, stops before the next one and then quits.")
        alert.addButton(withTitle: String(localized: "Keep Running"))
        let stop = alert.addButton(withTitle: String(localized: "Stop and Quit"))
        stop.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }
}
