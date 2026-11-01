import Foundation

/// One item the user selected, as shown at review time.
public struct PlannedItem: Equatable, Sendable {
    public let url: URL
    public let tier: Tier
    public let method: ActionMethod
    /// The item as the scan measured it; the executor compares it with the item just before acting (SAF-008).
    public let snapshot: ItemSnapshot

    public init(url: URL, tier: Tier, method: ActionMethod, snapshot: ItemSnapshot) {
        self.url = url
        self.tier = tier
        self.method = method
        self.snapshot = snapshot
    }
}

/// The exact list of operations shown at review time; the executor performs exactly this list (PRD section 8.1).
///
/// A plan belongs to one tool or sub-tool (FCL-002). Creating one checks every item: its method must be allowed by
/// its tier (SAF-004) and its path must pass the path guard (SAF-007).
public struct Plan: Sendable {
    public let run: UUID
    public let tool: ToolID
    /// The allowed roots of the plan's tool or sub-tool, used again when the executor re-validates (SAF-008).
    public let allowedRoots: [URL]
    public let items: [PlannedItem]

    public init(
        tool: ToolID, allowedRoots: [URL], items: [PlannedItem], pathGuard: PathGuard, run: UUID = UUID()
    ) throws(PlanError) {
        for item in items {
            guard item.tier.allows(item.method) else {
                throw .methodNotAllowed(item.url.path, tier: item.tier, method: item.method)
            }
            do {
                try pathGuard.validate(item.url, allowedRoots: allowedRoots)
            } catch {
                throw .rejected(item.url.path, error)
            }
        }
        self.run = run
        self.tool = tool
        self.allowedRoots = allowedRoots
        self.items = items
    }
}

extension Plan {
    /// A plan for items that `subTool`'s scan found, with the sub-tool's allowed roots.
    ///
    /// Besides the usual checks, every item must come from `subTool` and have one of its tiers, so a run never mixes
    /// sub-tools (FCL-002).
    public init(subTool: any SubTool, items: [ScanItem], pathGuard: PathGuard, run: UUID = UUID()) throws(PlanError) {
        for item in items {
            guard item.source == subTool.id else { throw .otherSubTool(item.url.path, item.source) }
            guard subTool.tiers.contains(item.tier) else { throw .tierNotAllowed(item.url.path, item.tier) }
        }
        try self.init(
            tool: subTool.id, allowedRoots: subTool.allowedRoots(home: pathGuard.configuration.home),
            items: items.map { PlannedItem(url: $0.url, tier: $0.tier, method: $0.method, snapshot: $0.snapshot) },
            pathGuard: pathGuard, run: run)
    }
}

/// Why a plan could not be created. A plan is all or nothing: the review never shows a partly valid list.
public enum PlanError: Error, Equatable {
    /// The item was found by another sub-tool than the plan's (FCL-002).
    case otherSubTool(String, ToolID)
    /// The plan's sub-tool does not produce items of this tier.
    case tierNotAllowed(String, Tier)
    /// The item's tier does not allow its method, for example Delete for "Your data" (SAF-004).
    case methodNotAllowed(String, tier: Tier, method: ActionMethod)
    /// The path guard rejected the item (SAF-007).
    case rejected(String, PathGuardError)
}
