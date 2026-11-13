import AppKit

/// The names of installed apps, by bundle ID. Caches & Logs groups its items by app and shows a folder named
/// `com.example.Notes` as "Notes" (CAC-002).
public protocol AppNames: Sendable {
    /// The display name of the app with `bundleID`, or `nil` if no installed app has that bundle ID.
    func name(ofBundleID bundleID: String) -> String?

    /// The bundle IDs of the installed apps by name, read once per scan. Caches & Logs ties a folder named after an app,
    /// such as `Firefox`, to the app, so the folder is disabled while the app runs (SAF-009, CAC-003, D-189).
    func bundleIDsByName(home: URL) -> AppsByName
}

/// The bundle IDs of installed apps, by any name an app goes by: its display name, its bundle name and its file name
/// without `.app`. Names compare without case, and two apps with one name give both bundle IDs.
public struct AppsByName: Sendable, Equatable {
    private let bundleIDs: [String: Set<String>]

    public init(_ bundleIDsByName: [String: Set<String>] = [:]) {
        bundleIDs = Dictionary(
            bundleIDsByName.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $0.union($1) })
    }

    /// The bundle IDs of the apps called `name`, empty if none is.
    public func bundleIDs(named name: String) -> Set<String> { bundleIDs[name.lowercased()] ?? [] }
}

/// The apps installed on this Mac, from Launch Services. Only reads.
public struct SystemAppNames: AppNames {
    public init() {}

    public func name(ofBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let bundle = Bundle(url: url)
        else { return nil }
        let name =
            (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// The apps in `/Applications` and `~/Applications`, read from their `Info.plist`s.
    public func bundleIDsByName(home: URL) -> AppsByName {
        Applications().bundleIDsByName(home: home)
    }
}

/// A fixed list, for tests. Bundle IDs compare without case, as a folder's name may differ in case from the app's.
public struct StubAppNames: AppNames {
    let names: [String: String]
    let byName: AppsByName

    /// `byName` gives the bundle IDs of apps by name, for folders not named like a bundle ID.
    public init(_ names: [String: String] = [:], byName: [String: Set<String>] = [:]) {
        self.names = Dictionary(uniqueKeysWithValues: names.map { ($0.key.lowercased(), $0.value) })
        self.byName = AppsByName(byName)
    }

    public func name(ofBundleID bundleID: String) -> String? { names[bundleID.lowercased()] }

    public func bundleIDsByName(home: URL) -> AppsByName { byName }
}
