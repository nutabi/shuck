import AppKit
import ShuckKit
import Synchronization
import os

/// Asks a running app to quit, the way the user would with Cmd-Q (APP-006). It has no way to force an app to quit, so
/// Shuck never does.
nonisolated protocol AppQuitter: Sendable {
    /// Sends a normal quit request to every running instance of the app with `bundleID`, compared without case.
    /// - Returns: How many instances were asked. The app may still refuse, for example to show a Save dialog.
    func requestQuit(bundleID: String) -> Int
}

/// Quits the apps running on this Mac with `NSRunningApplication.terminate()`, which is a normal quit request. It never
/// uses `forceTerminate()`.
nonisolated struct SystemAppQuitter: AppQuitter {
    func requestQuit(bundleID: String) -> Int {
        let id = bundleID.lowercased()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier?.lowercased() == id }
        return apps.filter { $0.terminate() }.count
    }
}

/// The apps a UI test's fixture root pretends are running. Quitting one removes it, so it "exits" and a later run does
/// not skip its items, and Xcode, which runs the test, is never asked to quit (SAF-016, D-110, D-113).
nonisolated final class FixtureRunningApps: RunningApps, AppQuitter {
    private let running: Mutex<Set<String>>

    init(_ bundleIDs: Set<String>) {
        running = Mutex(Set(bundleIDs.map { $0.lowercased() }))
    }

    func bundleIDs() -> Set<String> { running.withLock { $0 } }

    func name(of bundleID: String) -> String? { nil }

    func requestQuit(bundleID: String) -> Int {
        running.withLock { $0.remove(bundleID.lowercased()) != nil ? 1 : 0 }
    }
}

/// How a request to quit an app ended (APP-006).
nonisolated enum QuitOutcome: Equatable, Sendable {
    /// The app was running, was asked to quit and is gone.
    case exited
    /// The app was not running, so nothing was sent.
    case notRunning
    /// No running instance accepted the request, so nothing is waiting to exit.
    case requestNotSent
    /// The caller stopped waiting. The app may still be running; it was not forced.
    case cancelled
}

/// Quits an app and waits until it has gone (APP-006).
nonisolated struct QuitApp: Sendable {
    let runningApps: any RunningApps
    let quitter: any AppQuitter
    /// The pause between two looks at the running apps. A test passes one that counts them instead of sleeping.
    let pause: @Sendable () async throws -> Void

    private static let logger = Logger(tool: .applications)

    /// A pause of a tenth of a second, which asks the system little.
    static let realPause: @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }

    /// Sends one normal quit request, then looks until `bundleID` is gone from the running apps, the same list the
    /// executor checks again before it acts (SAF-009). There is no time limit, because the app may show a Save
    /// dialog; the caller cancels the task to stop waiting. Nothing is ever forced.
    @concurrent
    func quit(bundleID: String) async -> QuitOutcome {
        let id = bundleID.lowercased()
        guard runningApps.bundleIDs().contains(id) else { return .notRunning }
        Self.logger.info("Asking an app to quit: \(id, privacy: .private)")
        guard quitter.requestQuit(bundleID: id) > 0 else {
            Self.logger.error("An app did not take the quit request: \(id, privacy: .private)")
            return .requestNotSent
        }
        while runningApps.bundleIDs().contains(id) {
            do {
                try await pause()
            } catch {
                Self.logger.info("Stopped waiting for an app to quit: \(id, privacy: .private)")
                return .cancelled
            }
        }
        Self.logger.info("An app quit: \(id, privacy: .private)")
        return .exited
    }
}
