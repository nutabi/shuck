import Foundation
import os

/// "What can developer tools rebuild?": leftovers of developer tools, listed by rule (DEV-001). So far it has three,
/// Xcode's DerivedData (DEV-R01), its device support files (DEV-R02) and the simulators' caches (DEV-R04); the other
/// rules arrive one at a time (M2-T11 onwards).
public struct DeveloperJunk: SubTool {
    /// Xcode's bundle ID, for the rule's running-app check (SAF-009, D-110).
    static let xcodeBundleID = "com.apple.dt.Xcode"
    /// The Simulator app's bundle ID, which also uses the simulators' caches (SAF-009, D-110).
    static let simulatorBundleID = "com.apple.iphonesimulator"
    /// DerivedData is stale after this many days without a change (DEV-005, SET-002).
    static let staleDays = 30
    private static let logger = Logger(tool: .developerJunk)

    public init() {}

    public var info: ToolInfo {
        ToolInfo(
            id: .developerJunk, name: LocalizedStringResource("Developer Junk", bundle: #bundle),
            summary: LocalizedStringResource("What can developer tools rebuild?", bundle: #bundle),
            symbolName: "hammer", availability: .available)
    }

    /// Two rules, Xcode Archives and Docker, are "Your data" (section 8.2); the first rule is rebuildable only.
    public var tiers: Set<Tier> { [.rebuildable, .yourData] }

    /// DerivedData, each platform's device support folder that exists, such as `iOS DeviceSupport`, and the
    /// simulators' caches. The device support folders are found by name, so the roots stay as narrow as the rules'
    /// targets and leave out Archives and the rest of Xcode. Never the simulators' devices (DEV-007, D-119).
    public func allowedRoots(home: URL) -> [URL] {
        [Self.derivedData(home: home)] + Self.deviceSupportFolders(home: home) + [Self.simulatorCaches(home: home)]
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
                "Xcode builds this project again when you next need it.", bundle: #bundle),
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

    public func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                scanDerivedData(context) { continuation.yield($0) }
                scanDeviceSupport(context) { continuation.yield($0) }
                scanSimulatorCaches(context) { continuation.yield($0) }
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
            guard context.ownership.owners(of: folder).contains(id),
                let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true, values.isSymbolicLink != true,
                let snapshot = ItemSnapshot.read(folder, while: { !Task.isCancelled }),
                let modified = RuleMatch.modificationDate(at: folder)
            else { continue }
            let activity = FolderActivity.newest(in: folder, modified: modified)
            let missing = DerivedDataProject.workspace(in: folder).map(DerivedDataProject.isMissing) ?? false
            let stale = rule.selection.selects(modified: activity, now: now)
            do {
                emit(
                    .item(
                        try rule.scanItem(
                            at: folder, snapshot: snapshot, modified: modified, source: id,
                            runningApps: context.runningApps, now: now,
                            reason: Self.reason(missing: missing, stale: stale),
                            lastActivity: activity, selectedRegardless: missing)))
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
                    let snapshot = ItemSnapshot.read(folder, while: { !Task.isCancelled }),
                    let modified = RuleMatch.modificationDate(at: folder)
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
                let snapshot = ItemSnapshot.read(entry, while: { !Task.isCancelled }),
                let modified = RuleMatch.modificationDate(at: entry)
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
