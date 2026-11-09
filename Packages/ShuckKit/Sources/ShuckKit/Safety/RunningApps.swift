import AppKit

/// Which apps are running now, by bundle ID (SAF-009). A scan asks it to disable the items of a running app, and the
/// executor asks it again just before acting, in case the app started after the scan (CAC-003, D-110).
public protocol RunningApps: Sendable {
    /// The bundle IDs of the apps running now, lowercased. A bundle ID is compared without case, as a folder named
    /// after one may differ in case from the app's own.
    func bundleIDs() -> Set<String>
}

extension RunningApps {
    /// One of `apps` that is running now, if any. Asks nothing when `apps` is empty, as for personal files.
    public func firstRunning(of apps: Set<String>) -> String? {
        guard !apps.isEmpty else { return nil }
        let running = bundleIDs()
        return apps.sorted().first { running.contains($0.lowercased()) }
    }
}

/// The apps running on this Mac, from `NSWorkspace`, whose list is safe to read from any thread.
public struct SystemRunningApps: RunningApps {
    public init() {}

    public func bundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }
}

/// A fixed list, for tests and for the app's fixture-root mode, where Xcode itself runs the UI tests (D-110).
public struct StubRunningApps: RunningApps {
    let running: Set<String>

    public init(_ bundleIDs: Set<String> = []) {
        running = Set(bundleIDs.map { $0.lowercased() })
    }

    public func bundleIDs() -> Set<String> { running }
}

extension ItemSelection {
    /// The note a running app's item shows instead of a checkbox (CAC-003).
    public static var appIsRunning: ItemSelection {
        .disabled(LocalizedStringResource("App is running", bundle: #bundle))
    }

    /// This selection, or ``appIsRunning`` if one of `apps` is running now (SAF-009, CAC-003).
    public func unlessRunning(_ apps: Set<String>, in runningApps: any RunningApps) -> ItemSelection {
        runningApps.firstRunning(of: apps) == nil ? self : .appIsRunning
    }
}
