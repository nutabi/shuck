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
    /// A rule-backed item retains the exact rule and modification date the scan matched (D-100, D-105).
    public let ruleMatch: RuleMatch?
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
    /// The modification date the run compares just before acting, read with ``ModificationDate``: the item's own, or
    /// for an item whose scope is its contents, the newest inside it (SAF-008, D-132). `nil` for a command, and for an
    /// item whose date could not be read, which the run then skips.
    public let modified: Date?
    /// The bundle IDs of the apps that use the item. While one of them runs, the item is not acted on (SAF-009).
    public let apps: Set<String>
    /// The name of the app the item belongs to, which a page groups items by (CAC-002). `nil` when the sub-tool does not
    /// group by app.
    public let appName: String?
    /// The project a DerivedData folder was built from, as Xcode recorded it, so two projects of one name can be told
    /// apart (D-138). It is read from a file, shown as text only and never acted on. `nil` for other items.
    public let project: URL?

    public init(
        url: URL, snapshot: ItemSnapshot, tier: Tier, method: ActionMethod, reason: LocalizedStringResource,
        source: ToolID, modified: Date? = nil, confidence: Confidence? = nil, scope: ItemScope = .item,
        identity: FileIdentity? = nil,
        category: ItemCategory = .personalFiles, selection: ItemSelection = .unselected, ruleMatch: RuleMatch? = nil,
        apps: Set<String> = [], appName: String? = nil, project: URL? = nil
    ) {
        self.target = .path(url)
        self.snapshot = snapshot
        self.allocatedSize = snapshot.allocatedSize
        self.category = category
        self.selection = selection
        self.ruleMatch = ruleMatch
        self.tier = tier
        self.method = method
        self.reason = reason
        self.source = source
        self.confidence = confidence
        self.scope = scope
        self.identity = identity
        self.modified = modified
        self.apps = apps
        self.appName = appName
        self.project = project
    }

    /// A command carries its estimate without a fictional file kind or snapshot. No command runs in T03 (M2-T10).
    public init(
        command: ToolCommand, allocatedSize: Int64, tier: Tier, reason: LocalizedStringResource, source: ToolID,
        category: ItemCategory, selection: ItemSelection = .unselected, ruleMatch: RuleMatch? = nil,
        apps: Set<String> = []
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
        self.ruleMatch = ruleMatch
        confidence = nil
        scope = .item
        identity = nil
        modified = nil
        self.apps = apps
        appName = nil
        project = nil
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
    /// The apps running now; a scan disables the items of a running app (SAF-009, CAC-003).
    public let runningApps: any RunningApps
    /// The folder tools are looked for under: `/` in the app, so a tool is found where it is installed, and the fixture
    /// root in a UI test, so a test never reaches a real tool (SAF-016, D-114). `nil` finds none, so a scan that does
    /// not ask for tools never lists a tool's rule (DEV-002, D-124).
    public let toolRoot: URL?

    /// Whether the user's exclusions hide the path `url`, which a scan found: it is inside an exclusion or holds one.
    public func hides(_ url: URL) -> Bool {
        protection.overlapsUserExclusion(lexical: url)
    }

    /// Whether the user's exclusions hide `item`: the scan would not list it (SET-001, D-149). A path item is hidden
    /// when it is inside an exclusion or holds one; a tool command, when the folder it is sized from is.
    public func hides(_ item: ScanItem) -> Bool {
        if let url = item.url { return hides(url) }
        guard let rule = item.ruleMatch?.rule.id else { return false }
        var executable: String?
        if case .command(let command) = item.target { executable = command.executable }
        return DeveloperJunk.toolFolders(ruleID: rule, home: home, executable: executable)
            .contains { protection.overlapsUserExclusion($0) }
    }

    /// Without `protection`, a scan uses the production list for `home` with Shuck's own bundle. Tests pass the
    /// fixture root's configuration (D-41). Without `runningApps`, a scan asks this Mac which apps run; the app's
    /// fixture-root mode passes a stub (D-110).
    public init(
        home: URL, ownership: OwnershipMap? = nil, protection: PathGuardConfiguration? = nil,
        runningApps: any RunningApps = SystemRunningApps(), toolRoot: URL? = nil
    ) {
        self.home = home
        self.runningApps = runningApps
        self.toolRoot = toolRoot
        self.ownership = ownership ?? OwnershipMap(home: home)
        self.protection =
            protection ?? .production(home: home, appBundle: Bundle.main.bundleURL, userExclusions: [])
    }
}
