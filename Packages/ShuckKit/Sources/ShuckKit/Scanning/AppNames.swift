import AppKit

/// The names of installed apps, by bundle ID. Caches & Logs groups its items by app and shows a folder named
/// `com.example.Notes` as "Notes" (CAC-002).
public protocol AppNames: Sendable {
    /// The display name of the app with `bundleID`, or `nil` if no installed app has that bundle ID.
    func name(ofBundleID bundleID: String) -> String?
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
}

/// A fixed list, for tests. Bundle IDs compare without case, as a folder's name may differ in case from the app's.
public struct StubAppNames: AppNames {
    let names: [String: String]

    public init(_ names: [String: String] = [:]) {
        self.names = Dictionary(uniqueKeysWithValues: names.map { ($0.key.lowercased(), $0.value) })
    }

    public func name(ofBundleID bundleID: String) -> String? { names[bundleID.lowercased()] }
}
