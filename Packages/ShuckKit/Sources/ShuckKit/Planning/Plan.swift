import Foundation

/// One item the user selected, as shown at review time.
public struct PlannedItem: Equatable, Sendable, Identifiable {
    public let target: ItemTarget
    public var id: ItemTarget { target }
    public var url: URL? { target.url }
    public let category: ItemCategory
    public let selection: ItemSelection
    public let allocatedSize: Int64
    public let tier: Tier
    public let method: ActionMethod
    /// The item as the scan measured it; the executor compares it with the item just before acting (SAF-008).
    public let snapshot: ItemSnapshot?
    /// Whether the action removes the item or only what is inside it (CAC-004).
    public let scope: ItemScope
    /// Which file the scan found, if the executor must skip another file put at its path since (SAF-008, D-103).
    public let identity: FileIdentity?

    public init(
        url: URL, tier: Tier, method: ActionMethod, snapshot: ItemSnapshot, scope: ItemScope = .item,
        identity: FileIdentity? = nil, category: ItemCategory = .personalFiles, selection: ItemSelection = .unselected
    ) {
        self.target = .path(url)
        self.category = category
        self.selection = selection
        self.allocatedSize = snapshot.allocatedSize
        self.tier = tier
        self.method = method
        self.snapshot = snapshot
        self.scope = scope
        self.identity = identity
    }

    public init(
        command: ToolCommand, allocatedSize: Int64, tier: Tier, category: ItemCategory,
        selection: ItemSelection = .unselected
    ) {
        target = .command(command)
        self.allocatedSize = allocatedSize
        self.tier = tier
        method = .tool
        self.category = category
        self.selection = selection
        snapshot = nil
        scope = .item
        identity = nil
    }

    init(_ item: ScanItem) {
        target = item.target
        tier = item.tier
        method = item.method
        snapshot = item.snapshot
        scope = item.scope
        identity = item.identity
        allocatedSize = item.allocatedSize
        category = item.category
        selection = item.selection
    }
}

/// The exact list of operations shown at review time; the executor performs exactly this list (PRD section 8.1).
///
/// A plan belongs to one tool or sub-tool (FCL-002). Creating one checks every item: its method must be allowed by
/// its tier (SAF-004), only a folder deleted permanently may keep the folder and lose its contents (CAC-004), and its
/// path must pass the path guard (SAF-007).
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
            let subject = item.target.description
            guard item.tier.allows(item.method) else {
                throw .methodNotAllowed(subject, tier: item.tier, method: item.method)
            }
            guard item.selection.isSelectable else { throw .notSelectable(subject) }
            if item.scope == .contents {
                guard item.method == .delete else { throw .contentsNotAllowed(subject, method: item.method) }
                guard item.snapshot?.kind == .folder else { throw .contentsOfNonFolder(subject) }
            }
            // A tool command names no file to delete. Its executable and arguments were validated as data;
            // M2-T10 adds detection and execution. File targets always pass the guard (SAF-007).
            guard let url = item.url else { continue }
            guard item.method != .tool else { throw .commandRequired(subject) }
            do {
                try pathGuard.validate(url, allowedRoots: allowedRoots)
            } catch {
                throw .rejected(subject, error)
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
            guard item.source == subTool.id else { throw .otherSubTool(item.target.description, item.source) }
            guard subTool.tiers.contains(item.tier) else { throw .tierNotAllowed(item.target.description, item.tier) }
        }
        try self.init(
            tool: subTool.id, allowedRoots: subTool.allowedRoots(home: pathGuard.configuration.home),
            items: items.map(PlannedItem.init),
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
    /// The item asks to remove only a folder's contents with a method other than Delete (CAC-004).
    case contentsNotAllowed(String, method: ActionMethod)
    /// The item asks to remove only a folder's contents, but it is not a folder (CAC-004).
    case contentsOfNonFolder(String)
    /// A disabled item cannot enter a reviewed plan, even if a caller selects it directly.
    case notSelectable(String)
    /// Tool cleanup must carry the reviewed command, never a file standing in for it (SAF-010).
    case commandRequired(String)
    /// The path guard rejected the item (SAF-007).
    case rejected(String, PathGuardError)
}

extension PlanError {
    /// The path or command of the item the plan was refused at.
    public var path: String {
        switch self {
        case .otherSubTool(let path, _), .tierNotAllowed(let path, _), .methodNotAllowed(let path, _, _),
            .contentsNotAllowed(let path, _), .contentsOfNonFolder(let path), .rejected(let path, _),
            .notSelectable(let path), .commandRequired(let path):
            path
        }
    }
}
