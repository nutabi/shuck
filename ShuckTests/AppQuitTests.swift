import Foundation
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// Quitting a running app (APP-006). The stubs never reach this Mac's apps, and the pause never sleeps (SAF-016).
struct AppQuitTests {
    /// What the app does when asked to quit.
    enum Behavior: Sendable { case exits, refuses, ignores }

    /// A fixture app that counts each request and then acts as `behavior` says.
    final class Quitter: AppQuitter {
        let behavior: Behavior
        let apps: FixtureRunningApps
        let requests = Mutex(0)

        init(_ behavior: Behavior, apps: FixtureRunningApps) {
            self.behavior = behavior
            self.apps = apps
        }

        func requestQuit(bundleID: String) -> Int {
            requests.withLock { $0 += 1 }
            switch behavior {
            case .exits: return apps.requestQuit(bundleID: bundleID)
            case .refuses: return 0
            case .ignores: return 1
            }
        }
    }

    @Test(
        arguments: [
            (true, Behavior.exits, QuitOutcome.exited, 1, false, 0),
            (false, .exits, .notRunning, 0, false, 0),
            (true, .refuses, .requestNotSent, 1, true, 0),
            (true, .ignores, .cancelled, 1, true, 3),
        ])
    func quittingWaitsForTheAppAndNeverForcesItAPP006(
        running: Bool, behavior: Behavior, outcome: QuitOutcome, requests: Int, stillRunning: Bool, pauseCount: Int
    ) async {
        let apps = FixtureRunningApps(running ? ["com.Example.App"] : [])
        let quitter = Quitter(behavior, apps: apps)
        let pauses = Mutex(0)
        // An app that ignores the request is waited for until the task is cancelled, from the third pause.
        let task = Task {
            await QuitApp(
                runningApps: apps, quitter: quitter,
                pause: {
                    let count = pauses.withLock { count -> Int in
                        count += 1
                        return count
                    }
                    if count == 3 { withUnsafeCurrentTask { $0?.cancel() } }
                    try Task.checkCancellation()
                }
            ).quit(bundleID: "com.example.app")
        }
        #expect(await task.value == outcome)
        #expect(quitter.requests.withLock { $0 } == requests)
        #expect(apps.bundleIDs().contains("com.example.app") == stillRunning)
        #expect(pauses.withLock { $0 } == pauseCount)
    }
}
