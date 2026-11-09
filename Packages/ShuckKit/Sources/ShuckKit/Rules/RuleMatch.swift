import Foundation

/// The rule a scan matched and the target's modification date then. A plan freezes both, so execution can check
/// the reviewed rule again without asking a mutable registry (D-100). A command has no file modification date.
public struct RuleMatch: Equatable, Sendable {
    public let rule: CleanupRule
    public let modified: Date?

    public init(rule: CleanupRule, modified: Date?) {
        self.rule = rule
        self.modified = modified
    }

    /// A fresh stat, without following a final symlink or using URL resource-value caches. This compares the target's
    /// own modification date; size re-validation still measures its contents (SAF-008).
    public static func modificationDate(at url: URL) -> Date? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
    }
}

extension CleanupRule {
    /// Whether an item still describes this rule's target and action. This never grants permission to act: the path
    /// guard, snapshots and the tier-method check are mandatory separately (SAF-004, SAF-007, SAF-008).
    public func accepts(_ target: ItemTarget, tier: Tier, method: ActionMethod, scope: ItemScope) -> Bool {
        guard self.tier == tier, action.method == method else { return false }
        switch (action, target) {
        case (.paths(let paths, _, let expectedScope), .path(let url)):
            return scope == expectedScope && paths.contains { $0.matches(url) }
        case (.command(let expected), .command(let command)):
            return scope == .item && command == expected
        default: return false
        }
    }

    /// Builds a measured path item. The scanner supplies the snapshot and date it read, avoiding a second walk of
    /// a large folder. A missing rule's data stays hidden (DEV-002); the planner still guards each target (SAF-007).
    /// The item cannot be selected while one of the rule's apps is in `runningApps` (SAF-009).
    public func scanItem(
        at url: URL, snapshot: ItemSnapshot, modified: Date, source: ToolID, runningApps: any RunningApps,
        now: Date = .now, disabledReason: LocalizedStringResource? = nil
    ) throws(RuleItemError) -> ScanItem {
        guard detection.isAvailable else { throw .unavailable }
        guard case .paths(_, let method, let scope) = action,
            accepts(.path(url), tier: tier, method: method, scope: scope),
            scope != .contents || snapshot.kind == .folder
        else { throw .targetMismatch }
        return ScanItem(
            url: url, snapshot: snapshot, tier: tier, method: method, reason: explanation, source: source,
            scope: scope, identity: method == .trash ? FileIdentity.read(url) : nil,
            category: category,
            selection: itemSelection(
                modified: modified, now: now, disabledReason: disabledReason, running: runningApps),
            ruleMatch: RuleMatch(rule: self, modified: modified), apps: apps)
    }

    /// A tool estimate is informational; it is never parsed into deletion paths (DEV-003, R-07).
    public func scanItem(
        estimatedBytes: Int64, source: ToolID, runningApps: any RunningApps, modified: Date? = nil, now: Date = .now,
        disabledReason: LocalizedStringResource? = nil
    ) throws(RuleItemError) -> ScanItem {
        guard detection.isAvailable else { throw .unavailable }
        guard case .command(let command) = action else { throw .targetMismatch }
        guard estimatedBytes >= 0 else { throw .invalidEstimate }
        return ScanItem(
            command: command, allocatedSize: estimatedBytes, tier: tier, reason: explanation, source: source,
            category: category,
            selection: itemSelection(
                modified: modified, now: now, disabledReason: disabledReason, running: runningApps),
            ruleMatch: RuleMatch(rule: self, modified: nil), apps: apps)
    }

    private func itemSelection(
        modified: Date?, now: Date, disabledReason: LocalizedStringResource?, running: any RunningApps
    ) -> ItemSelection {
        if let disabledReason { return .disabled(disabledReason) }
        let selection: ItemSelection = selection.selects(modified: modified, now: now) ? .selected : .unselected
        return selection.unlessRunning(apps, in: running)
    }
}

public enum RuleItemError: Error, Equatable {
    case unavailable
    case targetMismatch
    case invalidEstimate
}
