import Foundation

/// One file, folder, bundle, launchd job or tool-cleanup target found by a scan (PRD section 8.1).
///
/// Every field SAF-001 lists is a required initializer argument, so an item cannot exist without them. Only the
/// confidence level is optional, because only some tools use it (APP-003).
public struct ScanItem: Equatable, Sendable, Identifiable {
    public let target: ItemTarget
    public var id: ItemTarget { target }
    public var url: URL? { target.url }
    /// The item's kind and allocated size when it was scanned (SAF-013). The plan keeps it for re-validation (SAF-008).
    public let snapshot: ItemSnapshot?
    /// Allocated size for a path, or the tool's estimate for a command (DEV-003, SAF-013).
    public let allocatedSize: Int64
    public let category: ItemCategory
    public let selection: ItemSelection
    public let tier: Tier
    public let method: ActionMethod
    /// Why the item is listed, shown next to it.
    public let reason: LocalizedStringResource
    /// The sub-tool whose scan found the item.
    public let source: ToolID
    public let confidence: Confidence?
    /// Whether the action removes the item or only what is inside it (CAC-004).
    public let scope: ItemScope
    /// Which file the scan found, if re-validation must tell it from another file later put at its path, such as a
    /// re-downloaded installer (SAF-008). `nil` for an item that may be recreated between scan and run and still be
    /// what the user chose, such as a DerivedData folder (D-103).
    public let identity: FileIdentity?

    public init(
        url: URL, snapshot: ItemSnapshot, tier: Tier, method: ActionMethod, reason: LocalizedStringResource,
        source: ToolID, confidence: Confidence? = nil, scope: ItemScope = .item, identity: FileIdentity? = nil,
        category: ItemCategory = .personalFiles, selection: ItemSelection = .unselected
    ) {
        self.target = .path(url)
        self.snapshot = snapshot
        self.allocatedSize = snapshot.allocatedSize
        self.category = category
        self.selection = selection
        self.tier = tier
        self.method = method
        self.reason = reason
        self.source = source
        self.confidence = confidence
        self.scope = scope
        self.identity = identity
    }

    /// A command carries its estimate without a fictional file kind or snapshot. No command runs in T03 (M2-T10).
    public init(
        command: ToolCommand, allocatedSize: Int64, tier: Tier, reason: LocalizedStringResource, source: ToolID,
        category: ItemCategory, selection: ItemSelection = .unselected
    ) {
        target = .command(command)
        snapshot = nil
        self.allocatedSize = allocatedSize
        self.tier = tier
        method = .tool
        self.reason = reason
        self.source = source
        self.category = category
        self.selection = selection
        confidence = nil
        scope = .item
        identity = nil
    }
}

/// What an action removes: the item itself, or only what is inside a folder (CAC-004).
public enum ItemScope: String, Codable, Sendable {
    /// The item itself, whatever its kind.
    case item
    /// Everything inside a folder, which is kept, as Caches & Logs keeps each cache folder an app expects to find
    /// (CAC-004). Only Delete removes a folder's contents; a plan refuses it for any other method or kind (SAF-004).
    case contents
}

/// How sure a scan is that an item belongs to what it matched, for example an app's leftovers (APP-003).
public enum Confidence: String, Codable, Sendable, CaseIterable {
    /// An exact bundle ID or a declared app group. Only these are selected by default.
    case high
    /// An app or vendor name match in Application Support, Caches or Logs.
    case medium
    /// Any other heuristic.
    case low
}

/// What a scan reports as it goes. Results stream in (FCL-012), so the UI shows items before the scan ends.
public enum ScanEvent: Equatable, Sendable {
    case item(ScanItem)
    /// A folder macOS does not let the scan read, shown as "Not accessible" with guidance (SAF-012, ONB-002). The scan
    /// goes on.
    case notAccessible(URL)
    /// A folder the scan could not read for another reason, such as a disk error (SAF-011). The scan goes on.
    case unreadable(URL)
}

/// What every scan gets from its caller.
public struct ScanContext: Sendable {
    /// The home folder: the real one in the app, the fixture root in tests (SAF-016).
    public let home: URL
    /// Which sub-tool owns each location; a scan skips what is not its own (FCL-005).
    public let ownership: OwnershipMap
    /// The path guard's configuration: a scan leaves out protected locations and the user's exclusions (section 8.4,
    /// SET-001).
    public let protection: PathGuardConfiguration

    /// Without `protection`, a scan uses the production list for `home` with Shuck's own bundle. Tests pass the
    /// fixture root's configuration (D-41).
    public init(home: URL, ownership: OwnershipMap? = nil, protection: PathGuardConfiguration? = nil) {
        self.home = home
        self.ownership = ownership ?? OwnershipMap(home: home)
        self.protection =
            protection ?? .production(home: home, appBundle: Bundle.main.bundleURL, userExclusions: [])
    }
}
