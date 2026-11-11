import AppKit

/// Which apps are running now, by bundle ID (SAF-009). A scan asks it to disable the items of a running app, and the
/// executor asks it again just before acting, in case the app started after the scan (CAC-003, D-110).
public protocol RunningApps: Sendable {
    /// The bundle IDs of the apps running now, lowercased. A bundle ID is compared without case, as a folder named
    /// after one may differ in case from the app's own.
    func bundleIDs() -> Set<String>

    /// The name a running app shows, such as "Xcode", for the note on its items (D-138). `nil` when it is not known.
    func name(of bundleID: String) -> String?
}

extension RunningApps {
    /// One of `apps` that is running now, if any. Asks nothing when `apps` is empty, as for personal files.
    public func firstRunning(of apps: Set<String>) -> String? {
        guard !apps.isEmpty else { return nil }
        let running = bundleIDs()
        return apps.sorted().first { running.contains($0.lowercased()) }
    }

    /// No name, so the note says "App is running", unless a list says otherwise.
    public func name(of bundleID: String) -> String? { nil }
}

/// The apps running on this Mac, from `NSWorkspace`, whose list is safe to read from any thread.
public struct SystemRunningApps: RunningApps {
    public init() {}

    public func bundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }

    public func name(of bundleID: String) -> String? {
        let id = bundleID.lowercased()
        return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier?.lowercased() == id }?.localizedName
    }
}

/// A fixed list, for tests and for the app's fixture-root mode, where Xcode itself runs the UI tests (D-110).
public struct StubRunningApps: RunningApps {
    let running: Set<String>
    let names: [String: String]

    /// `names` gives some of the apps a name, by bundle ID; the others have none.
    public init(_ bundleIDs: Set<String> = [], names: [String: String] = [:]) {
        running = Set(bundleIDs.map { $0.lowercased() })
        self.names = Dictionary(names.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    public func bundleIDs() -> Set<String> { running }

    public func name(of bundleID: String) -> String? { names[bundleID.lowercased()] }
}

extension ItemSelection {
    /// The note a running app's item shows instead of a checkbox (CAC-003). It names the app when its name is known,
    /// such as "Xcode is running", since the item's own name may be another app's, as a DerivedData project's is
    /// (D-138).
    public static func appIsRunning(_ name: String?) -> ItemSelection {
        guard let name, !name.isEmpty else {
            return .disabled(LocalizedStringResource("App is running", bundle: #bundle))
        }
        return .disabled(LocalizedStringResource("\(name) is running", bundle: #bundle))
    }

    /// This selection, or ``appIsRunning(_:)`` if one of `apps` is running now (SAF-009, CAC-003).
    public func unlessRunning(_ apps: Set<String>, in runningApps: any RunningApps) -> ItemSelection {
        guard let running = runningApps.firstRunning(of: apps) else { return self }
        return .appIsRunning(runningApps.name(of: running))
    }
}
