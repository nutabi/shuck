import Foundation
import Security

/// How a leftover was matched to its app (APP-002, APP-003). Every match here is High confidence; Medium and Low
/// matches by name come later.
enum LeftoverMatch: Equatable, Sendable {
    /// An entry named by the app's bundle ID, such as `Caches/<id>` or `Preferences/<id>.plist`.
    case bundleID
    /// `Group Containers/<group>` for a group in the app's `com.apple.security.application-groups` entitlement.
    case appGroup(String)
    /// A LaunchAgents plist whose label is the bundle ID (`exact`) or starts with `<id>.`.
    case agentLabel(exact: Bool)
    /// A LaunchAgents plist whose program lies inside the app bundle.
    case agentProgram

    /// The folders whose leftovers are never preselected, as they can hold the only copy of the user's data: a
    /// sandboxed app's documents live in `Containers/<id>/Data` (OQ-07, D-192).
    static let neverPreselectedFolders: Set<String> = ["Application Support", "Containers", "Group Containers"]

    /// Whether the item at `url` starts selected: an exact bundle-ID match outside `neverPreselectedFolders`. Every
    /// other High match is listed, and the user may select it (APP-003, OQ-07, D-192). This is the only place
    /// default selection is decided.
    func startsSelected(at url: URL) -> Bool {
        guard !Self.neverPreselectedFolders.contains(url.deletingLastPathComponent().lastPathComponent) else {
            return false
        }
        switch self {
        case .bundleID, .agentLabel(exact: true): return true
        case .appGroup, .agentLabel(exact: false), .agentProgram: return false
        }
    }

    var reason: LocalizedStringResource {
        switch self {
        case .bundleID: LocalizedStringResource("Named by the app's bundle ID", bundle: #bundle)
        case .appGroup(let group):
            LocalizedStringResource("In an app group the app declares: \(group)", bundle: #bundle)
        case .agentLabel: LocalizedStringResource("Launch agent named by the app's bundle ID", bundle: #bundle)
        case .agentProgram: LocalizedStringResource("Launch agent that runs a program inside the app", bundle: #bundle)
        }
    }
}

extension Applications {
    /// The `~/Library` entries named by an app's bundle ID (APP-002), as data: the folder, and each name the entry may
    /// have, which is the bundle ID followed by one of the suffixes. A name must match whole (R-05), so `Notes` never
    /// matches `NotesPro`. Preferences' `ByHost`, LaunchAgents and Group Containers are matched by their own rules.
    static let namedByBundleID: [(folder: String, suffixes: [String])] = [
        ("Library/Application Support", [""]), ("Library/Caches", [""]), ("Library/Containers", [""]),
        ("Library/Preferences", [".plist"]), ("Library/Saved Application State", [".savedState"]),
        ("Library/HTTPStorages", ["", ".binarycookies"]), ("Library/WebKit", [""]),
        ("Library/Cookies", [".binarycookies"]), ("Library/Logs", [""]), ("Library/Application Scripts", [""]),
    ]

    /// The app groups an app declares in its code signature's entitlements, read from the bundle with the Security
    /// framework and without starting a process (D-82). An unsigned app, or one with no groups, has none.
    public static func declaredAppGroups(of app: URL) -> [String] {
        var code: SecStaticCode?
        var information: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let entitlements = (information as? [String: Any])?[kSecCodeInfoEntitlementsDict as String]
                as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    /// Finds the leftovers of `app` in the folders APP-002 names, by its exact bundle ID and the app groups it declares,
    /// and streams them as items: Trash, "Your data", High confidence (APP-002, APP-003). An app without a bundle ID has
    /// none. A folder macOS does not let the scan read is reported once and the scan goes on (SAF-012). Every item is
    /// admitted by the path guard and left out if an exclusion hides it (SAF-007, SET-001). Cancelling the consuming
    /// task stops it (SAF-014).
    public func leftovers(of app: InstalledApp, _ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                if let bundleID = app.bundleID, Self.isSingleComponent(bundleID) {
                    var finder = LeftoverFinder(
                        app: app, bundleID: bundleID, context: context, roots: allowedRoots(home: context.home),
                        emit: { continuation.yield($0) })
                    finder.run(groups: appGroups(app.url))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Whether `name` can be one path component, so a bundle ID or group such as `../x` never leaves its folder.
    fileprivate static func isSingleComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}

/// One search for an app's leftovers.
private struct LeftoverFinder {
    let app: InstalledApp
    let bundleID: String
    let context: ScanContext
    let roots: [URL]
    let emit: (ScanEvent) -> Void
    /// The folders already reported as not accessible, so each is reported once (SAF-012).
    private var reported: Set<URL> = []
    /// The items already emitted, so one found by two rules is listed once.
    private var emitted: Set<URL> = []

    static let category = ItemCategory(
        id: "appLeftovers", name: LocalizedStringResource("App leftovers", bundle: #bundle))

    init(
        app: InstalledApp, bundleID: String, context: ScanContext, roots: [URL], emit: @escaping (ScanEvent) -> Void
    ) {
        self.app = app
        self.bundleID = bundleID
        self.context = context
        self.roots = roots
        self.emit = emit
    }

    mutating func run(groups: [String]) {
        for (folder, suffixes) in Applications.namedByBundleID {
            for suffix in suffixes { probe(folder: folder, name: bundleID + suffix, match: .bundleID) }
        }
        for group in groups where Applications.isSingleComponent(group) {
            probe(folder: "Library/Group Containers", name: group, match: .appGroup(group))
        }
        scanByHostPreferences()
        scanLaunchAgents()
    }

    private func folder(_ relative: String) -> URL {
        context.home.appending(path: relative, directoryHint: .isDirectory)
    }

    /// Looks for `folder/name` directly, without listing the folder, so no other app's entry is read.
    private mutating func probe(folder relative: String, name: String, match: LeftoverMatch) {
        guard !Task.isCancelled else { return }
        let parent = folder(relative)
        let url = parent.appending(path: name)
        switch Self.existence(of: url) {
        case .missing: return
        case .denied: reportDenied(parent)
        case .present: add(url, match)
        }
    }

    /// `Preferences/ByHost/<id>.<host UUID>.plist`: the bundle ID, a UUID and `.plist`, nothing else.
    private mutating func scanByHostPreferences() {
        for url in list(folder("Library/Preferences/ByHost")) {
            let name = url.lastPathComponent
            guard name.hasPrefix(bundleID + "."), name.hasSuffix(".plist") else { continue }
            let middle = name.dropFirst(bundleID.count + 1).dropLast(".plist".count)
            if UUID(uuidString: String(middle)) != nil { add(url, .bundleID) }
        }
    }

    /// A LaunchAgents plist matches by its label or by the program it runs (APP-002). The plist is only read.
    private mutating func scanLaunchAgents() {
        for url in list(folder("Library/LaunchAgents")) where url.pathExtension == "plist" {
            guard !Task.isCancelled else { return }
            guard let data = try? Data(contentsOf: url),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                Applications.logger.error("Cannot read a launch agent plist")
                continue
            }
            let label = plist["Label"] as? String ?? ""
            let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first ?? ""
            if label == bundleID {
                add(url, .agentLabel(exact: true))
            } else if label.hasPrefix(bundleID + ".") {
                add(url, .agentLabel(exact: false))
            } else if program.hasPrefix(app.url.path + "/") {
                add(url, .agentProgram)
            }
        }
    }

    /// The entries of `parent`, sorted. A folder that does not exist has none; one macOS refuses is reported (SAF-012).
    private mutating func list(_ parent: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            let error = error as NSError
            guard error.code != NSFileReadNoSuchFileError else { return [] }
            Applications.logger.error(
                "Cannot list a folder: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            if error.code == NSFileReadNoPermissionError {
                reportDenied(parent)
            } else if !Task.isCancelled {
                emit(.unreadable(parent))
            }
            return []
        }
    }

    private mutating func reportDenied(_ parent: URL) {
        if !Task.isCancelled, reported.insert(parent).inserted { emit(.notAccessible(parent)) }
    }

    /// Emits the item at `url` if the guard admits it and no exclusion hides it (SAF-007, SET-001).
    private mutating func add(_ url: URL, _ match: LeftoverMatch) {
        guard !Task.isCancelled, !emitted.contains(url), !context.hides(url),
            ScanAccess(url, allowedRoots: roots, protection: context.protection).admits(url, emit),
            let (snapshot, modified) = ScanAccess.measure(url, emit)
        else { return }
        emitted.insert(url)
        emit(
            .item(
                ScanItem(
                    url: url, snapshot: snapshot, tier: .yourData, method: .trash, reason: match.reason,
                    source: .applications, modified: modified, confidence: .high, category: Self.category,
                    selection: match.startsSelected(at: url) ? .selected : .unselected, appName: app.name)))
    }

    private enum Existence { case missing, present, denied }

    /// Whether something is at `url`, read with `lstat` and so without following a link. A link is not a leftover:
    /// moving a link to the Trash removes nothing the app wrote.
    private static func existence(of url: URL) -> Existence {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &info) } ?? -1 }
        if result == 0 { return info.st_mode & S_IFMT == S_IFLNK ? .missing : .present }
        return errno == EACCES || errno == EPERM ? .denied : .missing
    }
}
