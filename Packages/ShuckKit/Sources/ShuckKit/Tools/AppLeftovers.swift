import Foundation
import Security

/// How a leftover was matched to its app (APP-002, APP-003).
enum LeftoverMatch: Equatable, Sendable {
    /// An entry named by the app's bundle ID, such as `Caches/<id>` or `Preferences/<id>.plist`.
    case bundleID
    /// `Group Containers/<group>` for a group in the app's `com.apple.security.application-groups` entitlement.
    case appGroup(String)
    /// A LaunchAgents plist whose label is the bundle ID (`exact`) or starts with `<id>.`.
    case agentLabel(exact: Bool)
    /// A LaunchAgents plist whose program lies inside the app bundle.
    case agentProgram
    /// A helper in `PrivilegedHelperTools` named by the bundle ID, or by it and a `.` suffix (APP-004).
    case helperTool
    /// Medium: an entry in Application Support, Caches or Logs named like the app, the whole name (APP-003, D-196).
    case appName(String)
    /// Medium: such an entry named like the app's maker, the bundle ID's second component (APP-003, D-196).
    case vendorName(String)
    /// Low: such an entry named by the bundle ID and a `.` suffix, such as `com.example.Notes.ShipIt` (D-196).
    case idPrefix(String)

    var confidence: Confidence {
        switch self {
        case .bundleID, .appGroup, .agentLabel, .agentProgram, .helperTool: .high
        case .appName, .vendorName: .medium
        case .idPrefix: .low
        }
    }

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
        case .appGroup, .agentLabel(exact: false), .agentProgram, .helperTool, .appName, .vendorName, .idPrefix:
            return false
        }
    }

    var reason: LocalizedStringResource {
        switch self {
        case .bundleID: LocalizedStringResource("Named by the app's bundle ID", bundle: #bundle)
        case .appGroup(let group):
            LocalizedStringResource("In an app group the app declares: \(group)", bundle: #bundle)
        case .agentLabel: LocalizedStringResource("Launch agent named by the app's bundle ID", bundle: #bundle)
        case .agentProgram: LocalizedStringResource("Launch agent that runs a program inside the app", bundle: #bundle)
        case .helperTool: LocalizedStringResource("Helper tool named by the app's bundle ID", bundle: #bundle)
        case .appName(let name): LocalizedStringResource("Named like the app: \(name)", bundle: #bundle)
        case .vendorName(let name): LocalizedStringResource("Named like the app's maker: \(name)", bundle: #bundle)
        case .idPrefix(let name): LocalizedStringResource("Starts with the app's bundle ID: \(name)", bundle: #bundle)
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

    /// Finds the leftovers of `app` in the folders APP-002 names, by its exact bundle ID and the app groups it declares
    /// (High), by name in Application Support, Caches and Logs (Medium and Low, APP-003), and in the system-wide
    /// folders (APP-004), and streams them as items: Trash, "Your data". A system-wide item is disabled, as it needs
    /// admin rights. An app without a bundle ID has none. `installed` is every installed app by name: a name or vendor
    /// folder another installed app also goes by is not offered (R-05). A folder macOS does not let the scan read is reported once and the scan goes on (SAF-012). Every item is
    /// admitted by the path guard and left out if an exclusion hides it (SAF-007, SET-001). Cancelling the consuming
    /// task stops it (SAF-014).
    public func leftovers(
        of app: InstalledApp, among installed: AppsByName, _ context: ScanContext
    ) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                if let bundleID = app.bundleID, Self.isSingleComponent(bundleID) {
                    var finder = LeftoverFinder(
                        app: app, bundleID: bundleID, context: context, roots: allowedRoots(home: context.home),
                        installed: installed, systemLibrary: systemLibrary,
                        emit: { continuation.yield($0) })
                    finder.run(groups: appGroups(app.url))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The vendor in a bundle ID such as `com.vendor.App`: its second component, without case, when the ID has three or
    /// more and the vendor has three or more characters. `apple` is never a vendor, as it names folders of macOS itself
    /// (APP-003, D-196).
    static func vendor(of bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let vendor = parts[1].lowercased()
        return vendor.count >= 3 && vendor != "apple" ? vendor : nil
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
    let installed: AppsByName
    let systemLibrary: URL
    let emit: (ScanEvent) -> Void
    /// The bundle IDs of the other installed apps, without case (R-05).
    private let others: Set<String>
    /// The folders already reported as not accessible, so each is reported once (SAF-012).
    private var reported: Set<URL> = []
    /// The items already emitted, so one found by two rules is listed once.
    private var emitted: Set<URL> = []

    static let category = ItemCategory(
        id: "appLeftovers", name: LocalizedStringResource("App leftovers", bundle: #bundle))

    init(
        app: InstalledApp, bundleID: String, context: ScanContext, roots: [URL], installed: AppsByName,
        systemLibrary: URL, emit: @escaping (ScanEvent) -> Void
    ) {
        self.app = app
        self.bundleID = bundleID
        self.context = context
        self.roots = roots
        self.installed = installed
        self.systemLibrary = systemLibrary
        self.emit = emit
        others = Set(installed.allBundleIDs.map { $0.lowercased() }).subtracting([bundleID.lowercased()])
    }

    mutating func run(groups: [String]) {
        for (relative, suffixes) in Applications.namedByBundleID {
            for suffix in suffixes { probe(in: folder(relative), name: bundleID + suffix, match: .bundleID) }
        }
        for group in groups where Applications.isSingleComponent(group) {
            probe(in: folder("Library/Group Containers"), name: group, match: .appGroup(group))
        }
        scanByHostPreferences()
        scanLaunchAgents(in: folder("Library/LaunchAgents"), systemWide: false)
        scanByName()
        scanSystemWide()
    }

    private func folder(_ relative: String) -> URL {
        context.home.appending(path: relative, directoryHint: .isDirectory)
    }

    /// Looks for `folder/name` directly, without listing the folder, so no other app's entry is read.
    private mutating func probe(in parent: URL, name: String, match: LeftoverMatch, systemWide: Bool = false) {
        guard !Task.isCancelled else { return }
        let url = parent.appending(path: name)
        switch Self.existence(of: url) {
        case .missing: return
        case .denied: reportDenied(parent)
        case .present: add(url, match, systemWide: systemWide)
        }
    }

    /// The folders searched by name (APP-003).
    private static let nameFolders = ["Library/Application Support", "Library/Caches", "Library/Logs"]

    /// Medium and Low (APP-003, D-196): the entries of Application Support, Caches and Logs, each judged by its
    /// whole name without case. An entry named like the bundle ID itself was found as High. An entry another installed
    /// app also goes by, or whose name is another app's bundle ID and a suffix, is left out (R-05).
    private mutating func scanByName() {
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent].map { $0.lowercased() })
        let vendor = Applications.vendor(of: bundleID)
        let own = bundleID.lowercased()
        for relative in Self.nameFolders {
            for url in list(folder(relative)) where Self.existence(of: url) == .present {
                guard !Task.isCancelled else { return }
                let name = url.lastPathComponent
                let lower = name.lowercased()
                let match: LeftoverMatch
                if lower == own {
                    continue
                } else if names.contains(lower), !belongsToAnotherApp(lower) {
                    match = .appName(name)
                } else if lower == vendor, !belongsToAnotherApp(lower) {
                    match = .vendorName(name)
                } else if lower.hasPrefix(own + "."),
                    !others.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") })
                {
                    match = .idPrefix(name)
                } else {
                    continue
                }
                add(url, match)
            }
        }
    }

    /// Whether another installed app goes by `name` or has it as its vendor (R-05).
    private func belongsToAnotherApp(_ name: String) -> Bool {
        installed.bundleIDs(named: name).contains { $0.lowercased() != bundleID.lowercased() }
            || others.contains { Applications.vendor(of: $0) == name }
    }

    /// APP-004: the system-wide folders, matched like the user-level ones. Their items are listed and never planned.
    private mutating func scanSystemWide() {
        for (relative, name) in [("Application Support", bundleID), ("Preferences", bundleID + ".plist")] {
            probe(in: systemLibrary.appending(path: relative), name: name, match: .bundleID, systemWide: true)
        }
        let helpers = systemLibrary.appending(path: "PrivilegedHelperTools", directoryHint: .isDirectory)
        for url in list(helpers) where Self.existence(of: url) == .present {
            let name = url.lastPathComponent
            if name == bundleID || name.hasPrefix(bundleID + ".") { add(url, .helperTool, systemWide: true) }
        }
        for folder in ["LaunchAgents", "LaunchDaemons"] {
            scanLaunchAgents(in: systemLibrary.appending(path: folder, directoryHint: .isDirectory), systemWide: true)
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
    private mutating func scanLaunchAgents(in folder: URL, systemWide: Bool) {
        for url in list(folder) where url.pathExtension == "plist" {
            guard !Task.isCancelled else { return }
            // Only a regular file is read: opening a FIFO would wait for a writer.
            guard Self.isRegularFile(url), let data = try? Data(contentsOf: url),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                Applications.logger.error("Cannot read a launch agent plist")
                continue
            }
            let label = plist["Label"] as? String ?? ""
            let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first ?? ""
            if label == bundleID {
                add(url, .agentLabel(exact: true), systemWide: systemWide)
            } else if label.hasPrefix(bundleID + ".") {
                add(url, .agentLabel(exact: false), systemWide: systemWide)
            } else if program.hasPrefix(app.url.path + "/") {
                add(url, .agentProgram, systemWide: systemWide)
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

    /// Emits the item at `url` if the guard admits it and no exclusion hides it (SAF-007, SET-001). A system-wide item
    /// lies outside the allowed roots on purpose, so the guard would refuse it: it is listed as disabled instead, and
    /// no plan can hold it (APP-004). Exclusions still hide it.
    private mutating func add(_ url: URL, _ match: LeftoverMatch, systemWide: Bool = false) {
        guard !Task.isCancelled, !emitted.contains(url), !context.hides(url),
            systemWide || ScanAccess(url, allowedRoots: roots, protection: context.protection).admits(url, emit),
            let (snapshot, modified) = ScanAccess.measure(url, emit)
        else { return }
        emitted.insert(url)
        emit(
            .item(
                ScanItem(
                    url: url, snapshot: snapshot, tier: .yourData, method: .trash, reason: match.reason,
                    source: .applications, modified: modified, confidence: match.confidence,
                    category: Self.category, selection: selection(match, at: url, systemWide: systemWide),
                    appName: app.name)))
    }

    private func selection(_ match: LeftoverMatch, at url: URL, systemWide: Bool) -> ItemSelection {
        if systemWide {
            return .disabled(LocalizedStringResource("Needs admin — not removable in this version", bundle: #bundle))
        }
        return match.startsSelected(at: url) ? .selected : .unselected
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &info) } ?? -1 }
        return result == 0 && info.st_mode & S_IFMT == S_IFREG
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
