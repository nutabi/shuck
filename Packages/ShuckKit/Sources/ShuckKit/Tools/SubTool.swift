import Foundation

/// What the sidebar and landing pages show for a tool or sub-tool.
public struct ToolInfo: Sendable {
    public let id: ToolID
    public let name: LocalizedStringResource
    /// One line: the question the tool answers or the job it does (FCL-004).
    public let summary: LocalizedStringResource
    /// An SF Symbols name.
    public let symbolName: String
    public let availability: Availability

    public init(
        id: ToolID, name: LocalizedStringResource, summary: LocalizedStringResource, symbolName: String,
        availability: Availability
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.availability = availability
    }
}

/// Whether a tool or sub-tool works yet. Planned ones are listed so the sidebar shows the whole app (FCL-001).
public enum Availability: Equatable, Sendable {
    case available
    /// Built in a later roadmap milestone, such as "M2" (PRD section 13).
    case planned(milestone: String)
}

/// An independent unit inside File Cleanup, with its own scan, results, review and action (FCL-002, FCL-003).
///
/// A new sub-tool conforms to this protocol and is added to ``ToolRegistry/standard``; nothing else changes.
public protocol SubTool: Sendable {
    var info: ToolInfo { get }
    /// The tiers its items can have (PRD section 8.2). A plan rejects an item with any other tier.
    var tiers: Set<Tier> { get }
    /// The folders its items must be inside, given to the path guard with each check (SAF-007 (c), D-43).
    func allowedRoots(home: URL) -> [URL]
    /// Whether every item must have a cleanup rule that accepts it, Trash included (SAF-004, SAF-008, D-163). True for
    /// sub-tools whose items come from rules; false for the personal files, which no rule describes.
    var requiresRule: Bool { get }
    /// Starts a scan. Items stream in until the stream finishes; cancelling the consuming task stops it (SAF-014).
    func scan(_ context: ScanContext) -> AsyncStream<ScanEvent>
}

extension SubTool {
    public var id: ToolID { info.id }
    public var requiresRule: Bool { false }
}

/// A sub-tool listed in the registry before its milestone builds it. It finds nothing and has no allowed roots, so
/// the path guard rejects any plan for it.
public struct PlannedSubTool: SubTool {
    public let info: ToolInfo
    public let tiers: Set<Tier>

    public init(info: ToolInfo, tiers: Set<Tier>) {
        self.info = info
        self.tiers = tiers
    }

    public func allowedRoots(home: URL) -> [URL] { [] }

    public func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { $0.finish() }
    }
}
