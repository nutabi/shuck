import Foundation

/// One file, folder, bundle, launchd job or tool-cleanup target found by a scan (PRD section 8.1).
///
/// Every field SAF-001 lists is a required initializer argument, so an item cannot exist without them. Only the
/// confidence level is optional, because only some tools use it (APP-003).
public struct ScanItem: Equatable, Sendable {
    public let url: URL
    /// The item's kind and allocated size when it was scanned (SAF-013). The plan keeps it for re-validation (SAF-008).
    public let snapshot: ItemSnapshot
    public let tier: Tier
    public let method: ActionMethod
    /// Why the item is listed, shown next to it.
    public let reason: LocalizedStringResource
    /// The sub-tool whose scan found the item.
    public let source: ToolID
    public let confidence: Confidence?

    public init(
        url: URL, snapshot: ItemSnapshot, tier: Tier, method: ActionMethod, reason: LocalizedStringResource,
        source: ToolID, confidence: Confidence? = nil
    ) {
        self.url = url
        self.snapshot = snapshot
        self.tier = tier
        self.method = method
        self.reason = reason
        self.source = source
        self.confidence = confidence
    }

    /// Allocated size in bytes (SAF-013).
    public var allocatedSize: Int64 { snapshot.allocatedSize }
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
    /// A folder the scan could not read, shown as "Not accessible" with guidance (SAF-012, ONB-002). The scan goes on.
    case notAccessible(URL)
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
