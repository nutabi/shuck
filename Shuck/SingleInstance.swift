import AppKit

/// Only one instance of a build runs (SAF-018, D-135). A second launch activates the first and quits.
///
/// "The same build" means the same bundle ID, and the debug build has its own (D-70), so a debug build never yields to
/// a release build. A test launch skips the check: a UI test starts the app with a fixture root on purpose, and the app
/// unit tests run inside the app, so a stray instance of the debug build must not make either quit. The history log's
/// lock still stops two runs at once there.
nonisolated enum SingleInstance {
    /// The process ID of the instance to hand over to, or `nil` if this launch should go on.
    static func instanceToActivate(running: [pid_t], current: pid_t, testLaunch: Bool) -> pid_t? {
        guard !testLaunch else { return nil }
        return running.first { $0 != current }
    }

    /// Whether this launch is a UI test's, with a fixture root, or hosts the app's unit tests, which XCTest says by
    /// setting `XCTestConfigurationFilePath`.
    static func isTestLaunch(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains(AppEnvironment.fixtureRootArgument) || environment["XCTestConfigurationFilePath"] != nil
    }

    /// Activates the other instance of this build and quits, if there is one. Call it before building any model.
    @MainActor
    static func yieldToRunningInstance(arguments: [String], bundleID: String?) {
        guard let bundleID else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
            !$0.isTerminated
        }
        let current = ProcessInfo.processInfo.processIdentifier
        let target = instanceToActivate(
            running: others.map(\.processIdentifier), current: current,
            testLaunch: isTestLaunch(arguments: arguments, environment: ProcessInfo.processInfo.environment))
        guard let target, let other = others.first(where: { $0.processIdentifier == target }) else { return }
        other.activate()
        exit(0)
    }
}
