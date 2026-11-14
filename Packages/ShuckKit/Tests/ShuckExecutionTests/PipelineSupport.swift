import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

// What several pipeline tests share: a sub-tool with the scan context its fixtures need, and the synthetic rule the
// rule pipeline tests use. Everything stays inside the fixture root (SAF-016).

extension ActionResult {
    var isDone: Bool {
        if case .done = self { return true }
        return false
    }
}

extension ActionResult where SkipReason == ItemOutcome.SkipReason {
    /// The code of the skip this result is, `nil` for any other result.
    var skipCode: SkipCode? {
        if case .skipped(let reason) = self { return reason.code }
        return nil
    }
}

/// A sub-tool with the scan context that finds its fixtures.
struct Rig {
    let subTool: any SubTool
    let context: ScanContext

    /// Whatever the sub-tool lists in the fixture root.
    func scan() async -> [ScanItem] {
        await items(from: subTool, context: context)
    }

    func plan(_ items: [ScanItem], _ pathGuard: PathGuard) throws -> Plan {
        try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
    }

    /// The plan of everything the sub-tool lists, or only of what it selects.
    func plan(_ pathGuard: PathGuard, selectedOnly: Bool = false) async throws -> Plan {
        try plan(await scan().filter { !selectedOnly || $0.selection == .selected }, pathGuard)
    }

    /// The apps this Mac is taken to have: a cache whose app is unknown is never selected (CAC-009).
    static let appNames = StubAppNames(
        ["com.example.Notes": "Notes", "com.example.Mail": "Mail", "com.example.Recent": "Recent"],
        byName: ["Firefox": ["org.mozilla.firefox"]])

    static func cachesAndLogs(_ root: FixtureRoot, running: Set<String> = []) -> Rig {
        Rig(
            subTool: CachesAndLogs(appNames: appNames),
            context: ScanContext(
                home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running)))
    }

    static func developerJunk(_ root: FixtureRoot, running: Set<String> = []) -> Rig {
        Rig(
            subTool: DeveloperJunk(),
            context: ScanContext(
                home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running)))
    }

    /// Developer Junk with one project folder, `Developer` (DEV-006).
    static func nodeModules(_ root: FixtureRoot) -> Rig {
        let projects = [root.url.appending(path: "Developer")]
        return Rig(
            subTool: DeveloperJunk(projectFolders: projects),
            context: ScanContext(
                home: root.url, ownership: OwnershipMap(home: root.url, projectFolders: projects),
                protection: root.pathGuardConfiguration(), runningApps: StubRunningApps([])))
    }

    /// Developer Junk's tool items, with tools found only inside the fixture root.
    static func tools(_ root: FixtureRoot) -> Rig {
        Rig(
            subTool: DeveloperJunk(),
            context: ScanContext(home: root.url, protection: root.pathGuardConfiguration(), toolRoot: root.url))
    }
}

extension Date {
    /// Older than every "stale" rule of the sub-tools.
    static var longAgo: Date { Date.now.addingTimeInterval(-40 * 86_400) }
}

extension FixtureRoot {
    /// A folder with files in it, all long unused, as a stale cache is. Creating a file changes its folder's date, so
    /// the folders' dates are set last.
    @discardableResult
    func staleFolder(_ path: String) throws -> URL {
        try file("\(path)/data.db", size: 4096, modified: .longAgo)
        try file("\(path)/sub/more.db", size: 4096, modified: .longAgo)
        let folder = try url(path)
        for url in [folder.appending(path: "sub"), folder] {
            try FileManager.default.setAttributes([.modificationDate: Date.longAgo], ofItemAtPath: url.path)
        }
        return folder
    }

    /// An item the sub-tool `source` never listed, as a caller that skips the scan could hand to a plan.
    func unlisted(
        _ folder: URL, source: ToolID, tier: Tier = .rebuildable, method: ActionMethod = .delete,
        scope: ItemScope = .item
    ) throws -> ScanItem {
        ScanItem(
            url: folder, snapshot: try #require(ItemSnapshot.read(folder)), tier: tier, method: method,
            reason: "Not a rule's target", source: source, scope: scope, selection: .selected)
    }
}

/// Synthetic rules, from which `RulePipelineTests` and `PlanToRunTests` build items (SAF-016: no real rule, app or tool).
struct RuleFixture {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let cache: URL
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let stale = Date(timeIntervalSince1970: 1_700_000_000)
    let category = ItemCategory(id: "fixture", name: "Fixture caches")

    init(_ root: FixtureRoot, _ pathGuard: PathGuard) throws {
        self.root = root
        self.pathGuard = pathGuard
        cache = try root.folder("Library/Caches/Fixture")
    }

    func rule(
        scope: ItemScope = .item, detection: CleanupRule.Detection? = nil, apps: Set<String> = []
    ) throws -> CleanupRule {
        try CleanupRule(
            id: "fixture", name: "Fixture", description: "Fixture cache", category: category,
            detection: detection ?? .folder(cache),
            action: .paths([RulePath(root: cache, pattern: "*.cache")], method: .delete, scope: scope),
            tier: .rebuildable, selection: .modifiedAtLeast(days: 30), explanation: "Can be rebuilt",
            documentation: #require(URL(string: "https://example.test/cache")), apps: apps)
    }

    func scanned(_ url: URL, rule: CleanupRule, running: Set<String> = []) throws -> ScanItem {
        try rule.scanItem(
            at: url, snapshot: #require(ItemSnapshot.read(url)),
            modified: #require(RuleMatch.modificationDate(at: url)),
            source: FixtureSubTool.id, runningApps: StubRunningApps(running), now: now)
    }

    func plan(_ items: [ScanItem]) throws -> Plan {
        try Plan(subTool: FixtureSubTool(tier: .rebuildable, method: .delete), items: items, pathGuard: pathGuard)
    }
}

extension FixtureRoot {
    /// A "Your data" Trash item made by hand, as R-03's probe makes it: with no rule unless one is given.
    func byHand(_ url: URL, source: ToolID, ruleMatch: RuleMatch? = nil) throws -> ScanItem {
        ScanItem(
            url: url, snapshot: try #require(ItemSnapshot.read(url)), tier: .yourData, method: .trash,
            reason: "By hand", source: source, modified: ModificationDate.read(at: url), ruleMatch: ruleMatch)
    }

    /// The three items of R-03's probe: a folder in a project folder, a whole project and an archive's date folder, each
    /// a "Your data" Trash item with no rule.
    func rulelessItems() throws -> [ScanItem] {
        try folder("Developer")
        try folder("Developer/thesis")
        try folder("Developer/app")
        try folder("Library/Developer/Xcode/Archives")
        try folder("Library/Developer/Xcode/Archives/2026-11-10")
        return try ["Developer/thesis", "Developer/app", "Library/Developer/Xcode/Archives/2026-11-10"].map {
            try byHand(url($0), source: .developerJunk)
        }
    }
}
