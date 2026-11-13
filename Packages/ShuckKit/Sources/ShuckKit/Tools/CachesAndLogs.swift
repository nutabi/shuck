import Foundation
import os

/// "Which caches and logs can go?": the entries of `~/Library/Caches` and `~/Library/Logs`, and sandboxed apps' caches
/// in `~/Library/Containers`, each named for the app it belongs to (CAC-001, CAC-002). An app rebuilds a cache and
/// writes new logs, so every item is rebuildable and removed with Delete.
///
/// A cache or a log folder keeps its place and loses what is inside it, as apps expect to find it (CAC-004). Caches
/// that Developer Junk's tools own, Shuck's own and Docker's are left to others by the ownership map (FCL-005).
public struct CachesAndLogs: SubTool {
    /// A cache is selected after this many days without a change (CAC-005 sets 7 for logs; D-120).
    static let staleCacheDays = 30
    /// A log is selected after this many days without a change (CAC-005, SET-002).
    static let staleLogDays = 7
    private static let logger = Logger(tool: .cachesAndLogs)
    /// The category of the two log rules, whose items are selected by age alone (CAC-005).
    static let logsCategoryID = "logs"

    private let appNames: any AppNames

    /// `appNames` names the apps in the items' groups; tests pass a fixed list.
    public init(appNames: any AppNames = SystemAppNames()) {
        self.appNames = appNames
    }

    public var info: ToolInfo {
        ToolInfo(
            id: .cachesAndLogs, name: LocalizedStringResource("Caches & Logs", bundle: #bundle),
            summary: LocalizedStringResource("Which caches and logs can go?", bundle: #bundle),
            symbolName: "tray.full", availability: .available)
    }

    public var tiers: Set<Tier> { [.rebuildable] }

    /// Library's `Caches`, `Logs` and `Containers`. Never `/Library/Caches`, `/Library/Logs` or `/private/var`, which
    /// need admin rights (CAC-008). A rule and the ownership map narrow what lies inside the roots, and the guard
    /// refuses the protected locations in them, such as Docker's container (DEV-007).
    public func allowedRoots(home: URL) -> [URL] {
        [Self.caches(home: home), Self.logs(home: home), Self.containers(home: home)]
    }

    public var requiresRule: Bool { true }

    static func caches(home: URL) -> URL {
        home.appending(path: "Library/Caches", directoryHint: .isDirectory)
    }

    static func logs(home: URL) -> URL {
        home.appending(path: "Library/Logs", directoryHint: .isDirectory)
    }

    static func containers(home: URL) -> URL {
        home.appending(path: "Library/Containers", directoryHint: .isDirectory)
    }

    /// The five places an item comes from. A folder's contents are deleted and the folder stays; a file is deleted
    /// itself (CAC-004), so each needs its own rule.
    enum Kind: CaseIterable {
        case cacheFolders, cacheFiles, logFolders, logFiles, containerCaches

        var isLog: Bool { self == .logFolders || self == .logFiles }
        var staleDays: Int { isLog ? CachesAndLogs.staleLogDays : CachesAndLogs.staleCacheDays }
    }

    /// One of the sub-tool's cleanup rules (DEV-001). Its items are Delete, selected when nothing in them changed for
    /// 30 days, or 7 for logs (CAC-005), except what macOS itself writes (D-120).
    static func rule(_ kind: Kind, home: URL) throws(RuleError) -> CleanupRule {
        let cachesCategory = ItemCategory(id: "caches", name: LocalizedStringResource("Caches", bundle: #bundle))
        let logsCategory = ItemCategory(id: logsCategoryID, name: LocalizedStringResource("Logs", bundle: #bundle))
        let containersCategory = ItemCategory(
            id: "container-caches", name: LocalizedStringResource("App Container Caches", bundle: #bundle))
        let cacheText = LocalizedStringResource("The app builds this cache again when it needs it.", bundle: #bundle)
        let logText = LocalizedStringResource("The app writes a new log when it needs one.", bundle: #bundle)
        let root: URL
        let pattern: String
        let scope: ItemScope
        let id: String
        let name: LocalizedStringResource
        let description: LocalizedStringResource
        let category: ItemCategory
        let explanation: LocalizedStringResource
        switch kind {
        case .cacheFolders:
            (id, root, pattern, scope, category, explanation) = (
                "CAC-R01", caches(home: home), "*", .contents, cachesCategory, cacheText
            )
            name = LocalizedStringResource("App Caches", bundle: #bundle)
            description = LocalizedStringResource(
                "What an app keeps in its folder in Library's Caches.", bundle: #bundle)
        case .cacheFiles:
            (id, root, pattern, scope, category, explanation) = (
                "CAC-R02", caches(home: home), "*", .item, cachesCategory, cacheText
            )
            name = LocalizedStringResource("Cache Files", bundle: #bundle)
            description = LocalizedStringResource("A file an app keeps directly in Library's Caches.", bundle: #bundle)
        case .logFolders:
            (id, root, pattern, scope, category, explanation) = (
                "CAC-R03", logs(home: home), "*", .contents, logsCategory, logText
            )
            name = LocalizedStringResource("App Logs", bundle: #bundle)
            description = LocalizedStringResource("What an app keeps in its folder in Library's Logs.", bundle: #bundle)
        case .logFiles:
            (id, root, pattern, scope, category, explanation) = (
                "CAC-R04", logs(home: home), "*", .item, logsCategory, logText
            )
            name = LocalizedStringResource("Log Files", bundle: #bundle)
            description = LocalizedStringResource("A file an app keeps directly in Library's Logs.", bundle: #bundle)
        case .containerCaches:
            (id, root, pattern, scope, category, explanation) = (
                "CAC-R05", containers(home: home), "*/Data/Library/Caches", .contents, containersCategory, cacheText
            )
            name = LocalizedStringResource("App Container Caches", bundle: #bundle)
            description = LocalizedStringResource(
                "What a sandboxed app keeps in its own Caches folder.", bundle: #bundle)
        }
        guard
            let documentation = URL(
                string:
                    "https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html"
            )
        else { throw .invalidDocumentation }
        return try CleanupRule(
            id: id, name: name, description: description, category: category,
            detection: .folder(root),
            action: .paths([RulePath(root: root, pattern: pattern)], method: .delete, scope: scope),
            tier: .rebuildable, selection: .modifiedAtLeast(days: kind.staleDays), explanation: explanation,
            documentation: documentation)
    }

    public func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                let byName = appNames.bundleIDsByName(home: context.home)
                scanEntries(
                    in: Self.caches(home: context.home), folders: .cacheFolders, files: .cacheFiles, byName, context
                ) { continuation.yield($0) }
                scanEntries(in: Self.logs(home: context.home), folders: .logFolders, files: .logFiles, byName, context)
                {
                    continuation.yield($0)
                }
                scanContainers(context) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The folders and files directly inside Caches or Logs. A link is not an entry, and an entry whose owner is not
    /// this sub-tool, or that the guard would refuse, is left out (FCL-005, SAF-007).
    ///
    /// A folder named after an app rather than a bundle ID, such as `Firefox`, is tied to the apps `byName` gives for
    /// it, so it is disabled while one of them runs (SAF-009, CAC-003). A name alone does not tell whose the folder
    /// is, so the app stays unknown and the folder unselected (CAC-009, D-189).
    private func scanEntries(
        in root: URL, folders: Kind, files: Kind, _ byName: AppsByName, _ context: ScanContext,
        _ emit: (ScanEvent) -> Void
    ) {
        guard let folderRule = try? Self.rule(folders, home: context.home), folderRule.detection.isAvailable,
            let fileRule = try? Self.rule(files, home: context.home)
        else { return }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            let error = error as NSError
            Self.logger.error(
                "Cannot list a folder: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            emit(error.code == NSFileReadNoPermissionError ? .notAccessible(root) : .unreadable(root))
            return
        }
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !Task.isCancelled else { return }
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isSymbolicLink != true, isOurs(entry, context, emit)
            else { continue }
            let name = entry.lastPathComponent
            if values.isDirectory == true {
                let bundleID = Self.bundleID(ofFolder: name)
                let appName = bundleID.flatMap(appNames.name(ofBundleID:))
                emitItem(
                    at: entry, rule: folderRule, bundleID: bundleID,
                    namedApps: bundleID == nil ? byName.bundleIDs(named: name) : [], group: appName ?? name,
                    knownApp: appName != nil, context, emit)
            } else {
                // A loose file names no app Shuck can look up.
                emitItem(
                    at: entry, rule: fileRule, bundleID: nil,
                    group: entry.deletingPathExtension().lastPathComponent, knownApp: false, context, emit)
            }
        }
    }

    /// Each container's `Data/Library/Caches`, named for the container's bundle ID. Reading a container needs Full Disk
    /// Access, so the first one macOS refuses is reported once and the scan goes on (CAC-001, SAF-012).
    private func scanContainers(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        let root = Self.containers(home: context.home)
        guard let rule = try? Self.rule(.containerCaches, home: context.home), rule.detection.isAvailable else {
            return
        }
        let containers: [URL]
        do {
            containers = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            let error = error as NSError
            Self.logger.error(
                "Cannot list containers: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            emit(error.code == NSFileReadNoPermissionError ? .notAccessible(root) : .unreadable(root))
            return
        }
        var reportedDenial = false
        for container in containers.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !Task.isCancelled else { return }
            let caches = container.appending(path: "Data/Library/Caches", directoryHint: .isDirectory)
            guard (try? container.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
                let values = try? caches.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true, values.isSymbolicLink != true, isOurs(caches, context, emit)
            else {
                // A container whose caches macOS hides from the scan is one unreadable folder, not one per app.
                if !reportedDenial, FileManager.default.fileExists(atPath: container.path),
                    (try? FileManager.default.contentsOfDirectory(atPath: container.path)) == nil
                {
                    reportedDenial = true
                    emit(.notAccessible(container))
                }
                continue
            }
            let bundleID = container.lastPathComponent
            let appName = appNames.name(ofBundleID: bundleID)
            emitItem(
                at: caches, rule: rule, bundleID: bundleID, group: appName ?? bundleID, knownApp: appName != nil,
                context, emit)
        }
    }

    /// Whether the ownership map gives `url` to this sub-tool and the guard accepts it (FCL-005, SAF-007). A folder
    /// the guard refuses because Shuck may not read it is reported as not accessible (SAF-012).
    private func isOurs(_ url: URL, _ context: ScanContext, _ emit: (ScanEvent) -> Void) -> Bool {
        context.ownership.owners(of: url).contains(id)
            && ScanAccess(url, allowedRoots: allowedRoots(home: context.home), protection: context.protection)
                .admits(url, emit)
    }

    /// Builds the item for a cache or log, if it has anything in it. A folder with nothing inside is not listed.
    ///
    /// `knownApp` is whether Shuck found the installed app the entry belongs to. A cache without one is listed but
    /// never selected by default: some apps keep state in Caches, and nothing says this entry is only a cache
    /// (CAC-009). A log is a log whoever wrote it, so its age alone decides (CAC-005).
    private func emitItem(
        at url: URL, rule: CleanupRule, bundleID: String?, namedApps: Set<String> = [], group: String,
        knownApp: Bool, _ context: ScanContext, _ emit: (ScanEvent) -> Void
    ) {
        guard case .paths(_, _, let scope) = rule.action else { return }
        if scope == .contents {
            guard let inside = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                emit(.notAccessible(url))
                return
            }
            if inside.isEmpty { return }
        }
        guard let (snapshot, modified) = ScanAccess.measure(url, emit) else { return }
        let now = Date.now
        let activity = scope == .contents ? FolderActivity.newest(in: url, modified: modified) : modified
        // macOS writes these too, and some hold work in progress, so they are listed but never selected (D-120).
        let apple = (bundleID ?? url.lastPathComponent).lowercased().hasPrefix("com.apple.")
        let unknownApp = !knownApp && rule.category.id != Self.logsCategoryID
        do {
            emit(
                .item(
                    try rule.scanItem(
                        at: url, snapshot: snapshot, modified: modified, source: id, runningApps: context.runningApps,
                        now: now,
                        reason: Self.reason(
                            rule: rule, apple: apple, unknownApp: unknownApp,
                            stale: rule.selection.selects(modified: activity, now: now)),
                        lastActivity: activity, unselected: apple || unknownApp,
                        apps: bundleID.map { [$0] } ?? namedApps,
                        appName: group)))
        } catch {
            Self.logger.error("Skipped a cache or log: \(String(describing: error), privacy: .public)")
        }
    }

    /// A folder named like an app's bundle ID, such as `com.example.Notes`: three or more dot-separated parts of
    /// letters, digits, `-` and `_`. Other names, such as `Firefox` or `foo.log`, are looked up by app name instead.
    static func bundleID(ofFolder name: String) -> String? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = { (part: Substring) in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
        return parts.count >= 3 && parts.allSatisfy(allowed) ? name : nil
    }

    /// Why an item is selected or kept, `nil` for the rule's own explanation.
    private static func reason(
        rule: CleanupRule, apple: Bool, unknownApp: Bool, stale: Bool
    ) -> LocalizedStringResource? {
        if apple {
            return LocalizedStringResource("Part of macOS or an Apple app, so it starts unselected.", bundle: #bundle)
        }
        if unknownApp {
            return LocalizedStringResource(
                "Shuck can't tell which app this belongs to, so it starts unselected.", bundle: #bundle)
        }
        guard stale, case .modifiedAtLeast(let days) = rule.selection else { return nil }
        return LocalizedStringResource("Not changed for \(days) days or more.", bundle: #bundle)
    }
}
