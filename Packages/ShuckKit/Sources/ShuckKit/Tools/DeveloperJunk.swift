import Foundation
import os

/// "What can developer tools rebuild?": leftovers of developer tools, listed by rule (DEV-001). So far it has one,
/// Xcode's DerivedData (DEV-R01); the other rules arrive one at a time (M2-T08 onwards).
public struct DeveloperJunk: SubTool {
    /// Xcode's bundle ID, for the rule's running-app check (SAF-009, D-110).
    static let xcodeBundleID = "com.apple.dt.Xcode"
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

    public func allowedRoots(home: URL) -> [URL] { [Self.derivedData(home: home)] }

    static func derivedData(home: URL) -> URL {
        home.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
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

    public func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                scanDerivedData(context) { continuation.yield($0) }
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
            let activity = DerivedDataProject.lastActivity(in: folder, modified: modified)
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

    /// Why a project is listed and, if it is selected, why (DEV-008).
    private static func reason(missing: Bool, stale: Bool) -> LocalizedStringResource? {
        if missing { return LocalizedStringResource("Its project is no longer on this Mac.", bundle: #bundle) }
        if stale { return LocalizedStringResource("Not built for \(staleDays) days or more.", bundle: #bundle) }
        return nil
    }
}
