import Foundation
import os

/// "What can developer tools rebuild?": leftovers of developer tools, listed by rule (DEV-001). So far it has nine:
/// Xcode's DerivedData (DEV-R01), its device support files (DEV-R02), the simulators' caches (DEV-R04) and the stale
/// `node_modules` of the user's project folders (DEV-R06); as commands of the tools that own the data, unavailable
/// simulators (DEV-R03), the npm and pip caches and Homebrew's cleanup (DEV-R07 to DEV-R09); and one rule for "Your
/// data": Xcode's archives (DEV-R05). The other rules arrive one at a time.
public struct DeveloperJunk: SubTool {
    /// Xcode's bundle ID, for the rule's running-app check (SAF-009, D-110).
    static let xcodeBundleID = "com.apple.dt.Xcode"
    /// The Simulator app's bundle ID, which also uses the simulators' caches (SAF-009, D-110).
    static let simulatorBundleID = "com.apple.iphonesimulator"
    /// DerivedData is stale after this many days without a change (DEV-005, SET-002).
    static let staleDays = 30
    /// An Xcode archive is a folder with this extension.
    static let archiveSuffix = ".xcarchive"
    static let logger = Logger(tool: .developerJunk)

    /// The developer project folders from Settings (SET-003) that DEV-R06 scans for `node_modules`. The app rebuilds the
    /// sub-tool when the user changes them, so a scan, a plan and a run all see one list (D-152).
    public let projectFolders: [URL]

    /// - Parameter projectFolders: Folders inside the home folder, with symlinks resolved as the home folder's are. One
    ///   outside it is ignored, whatever is passed (``projects(home:)``).
    public init(projectFolders: [URL] = []) {
        self.projectFolders = projectFolders
    }

    /// The project folders that lie strictly inside `home`, without repeats. The allowed roots stay inside the home
    /// folder, so a folder outside it, or the home folder itself, is never scanned (SET-003, D-152).
    public func projects(home: URL) -> [URL] {
        var seen: Set<[String]> = []
        return projectFolders.filter { folder in
            folder.isFileURL && !folder.pathComponents.contains("..") && folder.isStrictlyInside(home)
                && seen.insert(folder.pathComponents.map(PathGuard.fold)).inserted
        }
    }

    public var info: ToolInfo {
        ToolInfo(
            id: .developerJunk, name: LocalizedStringResource("Developer Junk", bundle: #bundle),
            summary: LocalizedStringResource("What can developer tools rebuild?", bundle: #bundle),
            symbolName: "hammer", availability: .available)
    }

    /// Two rules, Xcode Archives and Docker, are "Your data" (section 8.2). Archives is the first of them.
    public var tiers: Set<Tier> { [.rebuildable, .yourData] }

    /// DerivedData, each platform's device support folder that exists, such as `iOS DeviceSupport`, and the
    /// simulators' caches and Xcode's Archives. The device support folders are found by name, so the roots stay narrow
    /// and leave out the rest of Xcode. Never the simulators' devices (DEV-007, D-119). The Archives root is one level
    /// wider than DEV-R05's targets, which are inside its date folders: the rule's pattern and the scan keep an item
    /// to the bundles (D-145). The project folders from Settings are roots too, for `node_modules` at the depths DEV-R06's
    /// patterns allow: the rule's match, not the root, is what keeps a Delete to a `node_modules` (D-141, D-153).
    public func allowedRoots(home: URL) -> [URL] {
        [Self.derivedData(home: home)] + Self.deviceSupportFolders(home: home)
            + [Self.simulatorCaches(home: home), Self.archives(home: home)] + resolvedProjects(home: home)
    }

    public var requiresRule: Bool { true }

    /// The project folders that still resolve strictly inside the resolved home folder. One replaced by a link to a
    /// folder elsewhere is dropped, so a target in it cannot leave the home folder (SAF-007 (c), R-16).
    private func resolvedProjects(home: URL) -> [URL] {
        guard let resolvedHome = ResolvedPath(home)?.url else { return [] }
        return projects(home: home).filter { ResolvedPath($0)?.url.isStrictlyInside(resolvedHome) == true }
    }

    static func archives(home: URL) -> URL {
        home.appending(path: "Library/Developer/Xcode/Archives", directoryHint: .isDirectory)
    }

    static func simulatorCaches(home: URL) -> URL {
        home.appending(path: "Library/Developer/CoreSimulator/Caches", directoryHint: .isDirectory)
    }

    static func derivedData(home: URL) -> URL {
        home.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
    }

    static func xcode(home: URL) -> URL {
        home.appending(path: "Library/Developer/Xcode", directoryHint: .isDirectory)
    }

    /// The platforms' device support folders that exist (`iOS DeviceSupport`, `watchOS DeviceSupport`, ...), by name.
    /// Links and files are not folders of Xcode's.
    static func deviceSupportFolders(home: URL) -> [URL] {
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: xcode(home: home), includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        return children.filter { folder in
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return folder.lastPathComponent.hasSuffix(DeviceSupportVersion.suffix)
                && folder.lastPathComponent.count > DeviceSupportVersion.suffix.count
                && values?.isDirectory == true && values?.isSymbolicLink != true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// DEV-R01: one item per project folder in DerivedData, which Xcode rebuilds when the project is built again.
    /// Selected when nothing in it changed for 30 days or when its project is gone (DEV-005, DEV-008, D-112).
    static func derivedDataRule(home: URL) throws(RuleError) -> CleanupRule {
        let root = derivedData(home: home)
        guard let documentation = URL(string: "https://github.com/vashpan/xcode-dev-cleaner") else {
            throw .invalidDocumentation
        }
        return try CleanupRule(
            id: "DEV-R01", name: LocalizedStringResource("Xcode DerivedData", bundle: #bundle),
            description: LocalizedStringResource(
                "Build products and indexes Xcode keeps for each project.", bundle: #bundle),
            category: ItemCategory(id: "xcode", name: LocalizedStringResource("Xcode", bundle: #bundle)),
            detection: .folder(root), action: .paths([RulePath(root: root, pattern: "*")], method: .delete),
            tier: .rebuildable, selection: .modifiedAtLeast(days: staleDays),
            explanation: LocalizedStringResource(
                "Xcode builds this project again when you next need it. Its Swift package checkouts go too, and Xcode needs an internet connection to download them again. Its compilation cache goes too, so the next build is slower.",
                bundle: #bundle),
            documentation: documentation, apps: [xcodeBundleID])
    }

    /// DEV-R02: one item per version folder in each `*DeviceSupport` folder, which Xcode copies from a device again.
    /// Every version is selected except the newest of its platform (D-118).
    static func deviceSupportRule(home: URL) throws(RuleError) -> CleanupRule {
        let root = xcode(home: home)
        guard let documentation = URL(string: "https://github.com/vashpan/xcode-dev-cleaner") else {
            throw .invalidDocumentation
        }
        return try CleanupRule(
            id: "DEV-R02", name: LocalizedStringResource("Xcode Device Support Files", bundle: #bundle),
            description: LocalizedStringResource(
                "Symbols Xcode copies from a device so it can debug that version of its system.", bundle: #bundle),
            category: ItemCategory(id: "xcode", name: LocalizedStringResource("Xcode", bundle: #bundle)),
            detection: .folder(root),
            action: .paths([RulePath(root: root, pattern: "*\(DeviceSupportVersion.suffix)/*")], method: .delete),
            tier: .rebuildable, selection: .always,
            explanation: LocalizedStringResource(
                "Xcode copies this again the next time you connect a device that runs this version.", bundle: #bundle),
            documentation: documentation, apps: [xcodeBundleID])
    }

    /// DEV-R04: one item per file or folder directly inside CoreSimulator's `Caches`, which the simulators rebuild the
    /// next time they start. Selected, and disabled while Xcode or Simulator runs. The simulators' devices next to it
    /// belong to `simctl` and are no rule's target (DEV-007, D-119).
    static func simulatorCachesRule(home: URL) throws(RuleError) -> CleanupRule {
        let root = simulatorCaches(home: home)
        guard
            let documentation = URL(
                string: "https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device")
        else { throw .invalidDocumentation }
        return try CleanupRule(
            id: "DEV-R04", name: LocalizedStringResource("Simulator Caches", bundle: #bundle),
            description: LocalizedStringResource(
                "Caches the iOS Simulator keeps, such as its system libraries cache.", bundle: #bundle),
            category: ItemCategory(id: "xcode", name: LocalizedStringResource("Xcode", bundle: #bundle)),
            detection: .folder(root), action: .paths([RulePath(root: root, pattern: "*")], method: .delete),
            tier: .rebuildable, selection: .always,
            explanation: LocalizedStringResource(
                "The simulators build this again the next time one starts.", bundle: #bundle),
            documentation: documentation, apps: [xcodeBundleID, simulatorBundleID])
    }

    /// DEV-R05: one item per `.xcarchive` bundle, which Xcode keeps in a folder for each day, such as
    /// `Archives/2026-11-11/App 11-11-26, 9.41 AM.xcarchive`. The PRD's `Archives/*` is shorthand for these bundles
    /// (D-145). The archive of a build that was distributed is the user's own data: it is moved to the Trash, never
    /// selected, and Xcode cannot rebuild it.
    static func archivesRule(home: URL) throws(RuleError) -> CleanupRule {
        let root = archives(home: home)
        guard
            let documentation = URL(
                string:
                    "https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information"
            )
        else { throw .invalidDocumentation }
        return try CleanupRule(
            id: "DEV-R05", name: LocalizedStringResource("Xcode Archives", bundle: #bundle),
            description: LocalizedStringResource(
                "Builds you archived in Xcode, for testing, for distribution or for the App Store.", bundle: #bundle),
            category: ItemCategory(
                id: "xcode-archives", name: LocalizedStringResource("Xcode Archives", bundle: #bundle)),
            detection: .folder(root),
            action: .paths([RulePath(root: root, pattern: "*/*\(archiveSuffix)")], method: .trash),
            tier: .yourData, selection: .never,
            explanation: LocalizedStringResource(
                "Apple says to keep the archive of every build you distribute. Xcode cannot make it again.",
                bundle: #bundle),
            documentation: documentation, apps: [xcodeBundleID])
    }

    /// DEV-R03: `xcrun simctl delete unavailable`, which removes the simulators whose runtime is no longer installed.
    /// The simulators' device data belongs to `simctl`, so only its command may change it (SAF-010, DEV-007). Selected,
    /// with no size: Shuck would have to read `simctl`'s output to know which simulators it would remove, and output
    /// never chooses a target (R-07, D-125).
    static func unavailableSimulatorsRule(_ tools: ToolLocations) throws(RuleError) -> CleanupRule {
        let xcrun = tools.executable("xcrun", in: ["usr/bin"])
        guard
            let documentation = URL(
                string: "https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device")
        else { throw .invalidDocumentation }
        return try CleanupRule(
            id: "DEV-R03", name: LocalizedStringResource("Unavailable Simulators", bundle: #bundle),
            description: LocalizedStringResource(
                "Simulators whose system version is no longer installed, so Xcode can't start them.", bundle: #bundle),
            category: ItemCategory(id: "xcode", name: LocalizedStringResource("Xcode", bundle: #bundle)),
            detection: .executable(xcrun),
            action: .command(try tools.command(xcrun, ["simctl", "delete", "unavailable"])), tier: .rebuildable,
            selection: .always,
            explanation: LocalizedStringResource(
                "Xcode's own tool removes the simulators that can no longer start. You can create new ones in Xcode.",
                bundle: #bundle),
            documentation: documentation)
    }

    public func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                scanDerivedData(context) { continuation.yield($0) }
                scanDeviceSupport(context) { continuation.yield($0) }
                scanSimulatorCaches(context) { continuation.yield($0) }
                scanArchives(context) { continuation.yield($0) }
                scanNodeModules(context) { continuation.yield($0) }
                scanUnavailableSimulators(context) { continuation.yield($0) }
                scanNpmCache(context) { continuation.yield($0) }
                scanPipCache(context) { continuation.yield($0) }
                scanHomebrew(context) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func scanDerivedData(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        let root = Self.derivedData(home: context.home)
        guard let rule = try? Self.derivedDataRule(home: context.home), rule.detection.isAvailable else { return }
        let folders: [URL]
        do {
            folders = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            let error = error as NSError
            Self.logger.error(
                "Cannot list DerivedData: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            emit(error.code == NSFileReadNoPermissionError ? .notAccessible(root) : .unreadable(root))
            return
        }
        let now = Date.now
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !Task.isCancelled else { return }
            // A file or a link is not a project; and a folder another sub-tool owns is not ours (FCL-005).
            guard context.ownership.owners(of: folder).contains(id), Self.isRealFolder(folder),
                access(folder, context).admits(folder, emit),
                let (snapshot, modified) = ScanAccess.measure(folder, emit)
            else { continue }
            let activity = FolderActivity.newest(in: folder, modified: modified)
            let workspace = DerivedDataProject.workspace(in: folder)
            let missing = workspace.map(DerivedDataProject.isMissing) ?? false
            let stale = rule.selection.selects(modified: activity, now: now)
            do {
                emit(
                    .item(
                        try rule.scanItem(
                            at: folder, snapshot: snapshot, modified: modified, source: id,
                            runningApps: context.runningApps, now: now,
                            reason: Self.reason(missing: missing, stale: stale),
                            lastActivity: activity, selectedRegardless: missing, project: workspace)))
            } catch {
                Self.logger.error("Skipped a DerivedData folder: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func scanDeviceSupport(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        guard let rule = try? Self.deviceSupportRule(home: context.home), rule.detection.isAvailable else { return }
        let now = Date.now
        for platform in Self.deviceSupportFolders(home: context.home) {
            guard !Task.isCancelled else { return }
            let versions: [URL]
            do {
                versions = try FileManager.default.contentsOfDirectory(
                    at: platform, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            } catch {
                let error = error as NSError
                Self.logger.error(
                    "Cannot list device support: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                emit(error.code == NSFileReadNoPermissionError ? .notAccessible(platform) : .unreadable(platform))
                continue
            }
            // Only real folders count as versions, also when deciding which one is the newest.
            let folders = versions.filter { version in
                let values = try? version.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true
            }
            let newest = DeviceSupportVersion.newest(among: folders.map(\.lastPathComponent))
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !Task.isCancelled else { return }
                guard context.ownership.owners(of: folder).contains(id),
                    access(folder, context).admits(folder, emit),
                    let (snapshot, modified) = ScanAccess.measure(folder, emit)
                else { continue }
                let name = folder.lastPathComponent
                let versioned = DeviceSupportVersion.components(ofFolder: name) != nil
                let kept = newest.contains(name) || !versioned
                do {
                    emit(
                        .item(
                            try rule.scanItem(
                                at: folder, snapshot: snapshot, modified: modified, source: id,
                                runningApps: context.runningApps, now: now,
                                reason: Self.reason(newest: newest.contains(name), versioned: versioned),
                                unselected: kept)))
                } catch {
                    Self.logger.error("Skipped a device support folder: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    private func scanSimulatorCaches(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        let root = Self.simulatorCaches(home: context.home)
        guard let rule = try? Self.simulatorCachesRule(home: context.home), rule.detection.isAvailable else { return }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
        } catch {
            let error = error as NSError
            Self.logger.error(
                "Cannot list simulator caches: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            emit(error.code == NSFileReadNoPermissionError ? .notAccessible(root) : .unreadable(root))
            return
        }
        let now = Date.now
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !Task.isCancelled else { return }
            // A link is not the cache itself, and an entry another sub-tool owns is not ours (FCL-005).
            guard context.ownership.owners(of: entry).contains(id),
                (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
                access(entry, context).admits(entry, emit), let (snapshot, modified) = ScanAccess.measure(entry, emit)
            else { continue }
            do {
                emit(
                    .item(
                        try rule.scanItem(
                            at: entry, snapshot: snapshot, modified: modified, source: id,
                            runningApps: context.runningApps, now: now)))
            } catch {
                Self.logger.error("Skipped a simulator cache: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// One item per archive bundle inside Archives' date folders (DEV-R05). Only real folders count: a link, a file
    /// or a folder without the `.xcarchive` extension is not an archive. Items are never selected (SAF-002).
    private func scanArchives(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        let root = Self.archives(home: context.home)
        guard let rule = try? Self.archivesRule(home: context.home), rule.detection.isAvailable else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let days: [URL]
        do {
            days = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)
        } catch {
            let error = error as NSError
            Self.logger.error(
                "Cannot list Archives: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            emit(error.code == NSFileReadNoPermissionError ? .notAccessible(root) : .unreadable(root))
            return
        }
        let now = Date.now
        for day in days.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !Task.isCancelled else { return }
            guard Self.isRealFolder(day) else { continue }
            let bundles: [URL]
            do {
                bundles = try FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: keys)
            } catch {
                let error = error as NSError
                Self.logger.error(
                    "Cannot list an archive folder: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                emit(error.code == NSFileReadNoPermissionError ? .notAccessible(day) : .unreadable(day))
                continue
            }
            for bundle in bundles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !Task.isCancelled else { return }
                guard bundle.lastPathComponent.hasSuffix(Self.archiveSuffix), Self.isRealFolder(bundle),
                    context.ownership.owners(of: bundle).contains(id), access(bundle, context).admits(bundle, emit),
                    let (snapshot, modified) = ScanAccess.measure(bundle, emit)
                else { continue }
                do {
                    emit(
                        .item(
                            try rule.scanItem(
                                at: bundle, snapshot: snapshot, modified: modified, source: id,
                                runningApps: context.runningApps, now: now)))
                } catch {
                    Self.logger.error("Skipped an archive: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Whether the guard accepts `url` as a target of this sub-tool. It refuses anything inside a protected location or
    /// the user's exclusions, and any folder that contains one, so a scan hides it instead of listing a row a plan
    /// would refuse (SET-001, SAF-007, D-149). A folder Shuck may not read is told apart, to be reported (SAF-012).
    func access(_ url: URL, _ context: ScanContext) -> ScanAccess {
        ScanAccess(url, allowedRoots: allowedRoots(home: context.home), protection: context.protection)
    }

    static func isRealFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// One item for DEV-R03, if this Mac has simulators, `xcrun` is where tools are found and the active developer
    /// folder has `simctl`, which a Mac without Xcode does not (DEV-002). Whether any
    /// simulator is unavailable is only known to `simctl`, so the item is listed whenever Xcode has made simulators.
    private func scanUnavailableSimulators(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        let devices = Self.simulatorDevices(home: context.home)
        // The devices are no path the guard can validate: they are protected, and only `simctl` changes them. So the
        // exclusions are compared with the folder that holds them (SET-001, D-149).
        guard !Task.isCancelled,
            Self.toolFolder(ruleID: "DEV-R03", home: context.home)
                .map({ context.protection.overlapsUserExclusion($0) }) != true,
            let tools = ToolLocations(context), tools.hasSimctl, CleanupRule.Detection.folder(devices).isAvailable,
            let rule = try? Self.unavailableSimulatorsRule(tools), rule.detection.isAvailable
        else { return }
        do {
            emit(.item(try rule.scanItem(estimatedBytes: 0, source: id, runningApps: context.runningApps)))
        } catch {
            Self.logger.error("Skipped the unavailable simulators: \(String(describing: error), privacy: .public)")
        }
    }

    /// The simulators' device data. Only a check that it exists reads it; `simctl` is the only thing that changes it.
    static func simulatorDevices(home: URL) -> URL {
        home.appending(path: "Library/Developer/CoreSimulator/Devices", directoryHint: .isDirectory)
    }

    /// Why a version is kept unselected; `nil` for the rule's own explanation (DEV-R02).
    private static func reason(newest: Bool, versioned: Bool) -> LocalizedStringResource? {
        if newest { return LocalizedStringResource("The newest version Xcode has for this platform.", bundle: #bundle) }
        if !versioned { return LocalizedStringResource("Shuck could not tell which version this is.", bundle: #bundle) }
        return nil
    }

    /// Why a project is listed and, if it is selected, why (DEV-008).
    private static func reason(missing: Bool, stale: Bool) -> LocalizedStringResource? {
        if missing { return LocalizedStringResource("Its project is no longer on this Mac.", bundle: #bundle) }
        if stale { return LocalizedStringResource("Not built for \(staleDays) days or more.", bundle: #bundle) }
        return nil
    }
}
