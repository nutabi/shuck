import Foundation
import os

/// An app Applications lists (APP-001): an app bundle the user may uninstall.
public struct InstalledApp: Equatable, Sendable, Identifiable {
    /// The app bundle, with the path the scan found it at.
    public let url: URL
    public var id: URL { url }
    /// The name the app shows, from its `Info.plist`, or the bundle's file name without `.app`.
    public let name: String
    /// `CFBundleIdentifier`, or `nil` for a bundle that declares none. Leftovers are matched by it (APP-002).
    public let bundleID: String?
    /// The bundle's kind and allocated size when it was scanned (SAF-013). An uninstall plan keeps it, so the run can
    /// compare it with the bundle just before acting (SAF-008).
    public let snapshot: ItemSnapshot
    /// The modification date the scan read with ``ModificationDate``, which the run compares too (SAF-008, D-132).
    public let modified: Date

    public var allocatedSize: Int64 { snapshot.allocatedSize }

    public init(url: URL, name: String, bundleID: String?, snapshot: ItemSnapshot, modified: Date) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.snapshot = snapshot
        self.modified = modified
    }
}

/// What the app inventory reports as it goes. Apps stream in, so the page can list them before the scan ends.
public enum AppInventoryEvent: Equatable, Sendable {
    case app(InstalledApp)
    /// A folder or app macOS does not let the scan read, shown as "Not accessible" (SAF-012). The scan goes on.
    case notAccessible(URL)
    /// A folder the scan could not read for another reason, such as a disk error (SAF-011). The scan goes on.
    case unreadable(URL)
}

/// The Applications tool's engine: its tier, its allowed roots and the inventory of installed apps (APP-001).
///
/// Applications is a tool of its own, not a File Cleanup ``SubTool`` (D-186): its scan lists apps, not items to clean,
/// and its uninstall plan is built with ``Plan/init(tool:allowedRoots:items:pathGuard:run:requiresRule:)`` from
/// ``allowedRoots(home:)``.
public struct Applications: Sendable {
    /// Whether an app is part of macOS, protected by System Integrity Protection, so it cannot be removed (APP-001).
    public typealias SystemProtected = @Sendable (URL) -> Bool

    /// The folders `~/Library` keeps an app's leftovers in, relative to the home folder (APP-002), and LaunchAgents,
    /// which holds the agents an uninstall unloads (APP-011). `Preferences` includes `ByHost`.
    public static let leftoverFolders = [
        "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
        "Library/Preferences", "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit",
        "Library/Cookies", "Library/Logs", "Library/Application Scripts", "Library/LaunchAgents",
    ]

    /// The bundle IDs of Shuck's own builds, which are never listed (APP-001, D-70).
    static let ownBundleIDs: Set<String> = [ShuckKit.bundleID, ShuckKit.debugBundleID]

    static let logger = Logger(tool: .applications)

    public var id: ToolID { .applications }
    /// Apps and their leftovers are the user's data, moved to the Trash (PRD section 8.2).
    public var tiers: Set<Tier> { [.yourData] }

    private let customAppFolders: [URL]?
    private let isSystemProtected: SystemProtected

    /// - Parameters:
    ///   - appFolders: The folders apps are listed from. `nil` uses ``appFolders(home:)``'s production folders; tests
    ///     pass folders inside the fixture root, so they never read the real `/Applications` (SAF-016).
    ///   - isSystemProtected: Whether an app is protected by System Integrity Protection. Tests stub it, since only
    ///     root can set the flag on a fixture.
    public init(appFolders: [URL]? = nil, isSystemProtected: @escaping SystemProtected = Self.hasRestrictedFlag) {
        customAppFolders = appFolders
        self.isSystemProtected = isSystemProtected
    }

    /// `/Applications` and `~/Applications`, or the folders the caller passed (APP-001).
    public func appFolders(home: URL) -> [URL] {
        customAppFolders ?? [
            URL(filePath: "/Applications", directoryHint: .isDirectory), home.appending(path: "Applications"),
        ]
    }

    /// The app folders and the leftover folders: everything an uninstall may move to the Trash, given to the path guard
    /// with each check (SAF-007 (c)). Approved by the owner (D-185).
    public func allowedRoots(home: URL) -> [URL] {
        appFolders(home: home) + Self.leftoverFolders.map { home.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// Lists the installed apps: each `.app` directly inside an app folder or inside one of its subfolders, one level
    /// down (APP-001). It leaves out links, apps protected by System Integrity Protection, Shuck itself and anything the
    /// path guard refuses. Cancelling the consuming task stops it (SAF-014).
    public func scan(_ context: ScanContext) -> AsyncStream<AppInventoryEvent> {
        AsyncStream { continuation in
            let task = Task {
                let roots = allowedRoots(home: context.home)
                for folder in appFolders(home: context.home) {
                    for entry in entries(of: folder, { continuation.yield($0) }) {
                        guard !Task.isCancelled else { break }
                        if entry.pathExtension.lowercased() == "app" {
                            app(at: entry, roots, context) { continuation.yield($0) }
                        } else if Self.isPlainFolder(entry) {
                            for child in entries(of: entry, { continuation.yield($0) })
                            where child.pathExtension.lowercased() == "app" {
                                guard !Task.isCancelled else { break }
                                app(at: child, roots, context) { continuation.yield($0) }
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The entries of `folder`, sorted by name. A folder that does not exist, as `~/Applications` often doesn't, has
    /// none; one the scan cannot read is reported (SAF-011, SAF-012).
    private func entries(of folder: URL, _ emit: (AppInventoryEvent) -> Void) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            let error = error as NSError
            guard error.code != NSFileReadNoSuchFileError else { return [] }
            Self.logger.error("Cannot list a folder: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            if !Task.isCancelled {
                emit(error.code == NSFileReadNoPermissionError ? .notAccessible(folder) : .unreadable(folder))
            }
            return []
        }
    }

    /// Reports the app at `url`, unless it is left out (APP-001) or the guard refuses it (SAF-007).
    private func app(at url: URL, _ roots: [URL], _ context: ScanContext, _ emit: @escaping (AppInventoryEvent) -> Void)
    {
        // A link to an app is not the app: moving the link to the Trash would uninstall nothing.
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true, values.isSymbolicLink != true
        else { return }
        let access = ScanAccess(url, allowedRoots: roots, protection: context.protection)
        guard access.admits(url, Self.forward(emit)) else { return }
        let info = Self.infoDictionary(of: url)
        let bundleID = info["CFBundleIdentifier"] as? String
        if let bundleID, Self.ownBundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            return
        }
        guard !isSystemProtected(url),
            let (snapshot, modified) = ScanAccess.measure(url, Self.forward(emit))
        else { return }
        emit(
            .app(
                InstalledApp(
                    url: url, name: Self.name(info, url), bundleID: bundleID, snapshot: snapshot, modified: modified)))
    }

    /// Reports what the shared scan helpers report, which is only ever a path they could not read.
    private static func forward(_ emit: @escaping (AppInventoryEvent) -> Void) -> (ScanEvent) -> Void {
        { event in
            switch event {
            case .notAccessible(let url): emit(.notAccessible(url))
            case .unreadable(let url): emit(.unreadable(url))
            case .item: break
            }
        }
    }

    /// Whether `url` is a folder an app may sit in, such as `Utilities`: not a link and not a package.
    private static func isPlainFolder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true && values.isPackage != true
    }

    /// The app's `Contents/Info.plist`, read from the bundle on disk, or an empty dictionary if it has none.
    static func infoDictionary(of app: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: app.appending(path: "Contents/Info.plist")),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return [:] }
        return plist as? [String: Any] ?? [:]
    }

    /// The display name, then the bundle name, then the file name without `.app`.
    static func name(_ info: [String: Any], _ url: URL) -> String {
        let names = ["CFBundleDisplayName", "CFBundleName"].compactMap { info[$0] as? String }
        return names.first { !$0.isEmpty } ?? url.deletingPathExtension().lastPathComponent
    }

    /// Whether the item at `url` has the `SF_RESTRICTED` flag, which System Integrity Protection sets on what it
    /// protects, such as Safari in `/Applications`. Only reads, without following a link.
    public static func hasRestrictedFlag(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0 && status.st_flags & UInt32(SF_RESTRICTED) != 0
    }
}
