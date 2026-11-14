import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Plans (SAF-004) and the snapshots the executor re-validates against (SAF-008, SAF-013).
struct PlanTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    // MARK: - Tier and method (SAF-004)

    static let allowed: Set<String> = [
        "rebuildable-delete", "rebuildable-tool", "yourData-trash", "yourData-tool",
        "yourData-launchctl",
    ]

    @Test(arguments: Tier.allCases, ActionMethod.allCases)
    func planAcceptsOnlyTheMethodsATierAllowsSAF004(tier: Tier, method: ActionMethod) throws {
        let file = try root.file("Downloads/item.bin", size: 10)
        let command = try ToolCommand(executable: file.path, arguments: ["clean"], environment: ["PATH": "/bin"])
        let item =
            method == .tool
            ? PlannedItem(
                command: command, allocatedSize: 4096, tier: tier,
                category: ItemCategory(id: "fixture", name: "Fixture"))
            : try root.planned(file, tier: tier, method: method)
        let isAllowed = Self.allowed.contains("\(tier.rawValue)-\(method.rawValue)")

        #expect(tier.allows(method) == isAllowed)
        if isAllowed {
            let plan = try Plan(tool: .largeFiles, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
            #expect(plan.items == [item])
        } else {
            let error = #expect(throws: PlanError.self) {
                try Plan(tool: .largeFiles, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
            }
            #expect(error == .methodNotAllowed(file.path, tier: tier, method: method))
        }
    }

    /// A Delete without a rule has no evidence that the item is safe to lose (D-132).
    // MARK: - Dependencies (APP-005, APP-011, SAF-011)

    @Test func aPlanAcceptsADependencyOnAnEarlierItemOnlyAPP005() throws {
        let bundle = try root.folder("Applications/Fixture.app")
        let cache = try root.folder("Library/Caches/com.example.fixture")
        let other = try root.folder("Library/Caches/com.example.other")
        let first = try root.planned(bundle, tier: .yourData, method: .trash)
        let second = try root.planned(cache, tier: .yourData, method: .trash)

        func refused(_ items: [PlannedItem]) -> PlanError? {
            #expect(throws: PlanError.self) {
                try Plan(tool: .applications, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
            }
        }
        // On an earlier item.
        let onEarlier = try root.planned(cache, tier: .yourData, method: .trash, dependency: ItemDependency(first))
        let plan = try Plan(
            tool: .applications, allowedRoots: [root.url], items: [first, onEarlier], pathGuard: pathGuard)
        #expect(plan.items == [first, onEarlier])
        // On a later item.
        let onLater = try root.planned(bundle, tier: .yourData, method: .trash, dependency: ItemDependency(second))
        #expect(refused([onLater, second]) == .dependencyNotEarlier(bundle.path))
        // On itself.
        let onSelf = try root.planned(cache, tier: .yourData, method: .trash, dependency: ItemDependency(second))
        #expect(refused([first, onSelf]) == .dependencyNotEarlier(cache.path))
        // On an item that is not in the plan.
        let unknown = ItemDependency(try root.planned(other, tier: .yourData, method: .trash))
        let onUnknown = try root.planned(cache, tier: .yourData, method: .trash, dependency: unknown)
        #expect(refused([first, onUnknown]) == .dependencyNotEarlier(cache.path))
        // The same target with another method is another item.
        let otherMethod = ItemDependency(target: first.target, method: .launchctl)
        let onOtherMethod = try root.planned(cache, tier: .yourData, method: .trash, dependency: otherMethod)
        #expect(refused([first, onOtherMethod]) == .dependencyNotEarlier(cache.path))
    }

    @Test func aPlanRefusesADeleteItemWithoutARuleSAF008() throws {
        let cache = try root.file("Library/Caches/cache.db", size: 10)
        let item = PlannedItem(
            url: cache, tier: .rebuildable, method: .delete, snapshot: try #require(ItemSnapshot.read(cache)),
            modified: ModificationDate.read(at: cache))

        let error = #expect(throws: PlanError.self) {
            try Plan(tool: .cachesAndLogs, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
        }
        #expect(error == .ruleRequired(cache.path))
        #expect(error?.path == cache.path)
        #expect(
            try Plan(tool: .cachesAndLogs, allowedRoots: [root.url], items: [root.planned(cache)], pathGuard: pathGuard)
                .items.count == 1)
    }

    @Test func planRejectsAnItemThePathGuardRejectsSAF007() throws {
        let key = try root.file(".ssh/id_ed25519", size: 10)
        let item = PlannedItem(
            url: key, tier: .yourData, method: .trash, snapshot: try #require(ItemSnapshot.read(key)))
        let error = #expect(throws: PlanError.self) {
            try Plan(tool: .largeFiles, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
        }
        let protected = root.url.appending(path: ".ssh").path
        #expect(error == .rejected(key.path, .protectedLocation(key.path, protected: protected)))
    }

    /// SET-001: an exclusion is a protected location, so a plan refuses what is inside it and what holds it.
    @Test(arguments: ["Documents/Keep", "Documents/Keep/inner", "Documents"])
    func planRejectsAnItemInsideOrHoldingAnExclusionSET001SAF007(target: String) throws {
        let inner = try root.file("Documents/Keep/inner/note.txt", size: 10)
        let exclusion = try root.url("Documents/Keep/inner")
        let guarded = PathGuard(configuration: root.pathGuardConfiguration(userExclusions: [exclusion]))
        let url = try root.url(target)
        let item = PlannedItem(
            url: url, tier: .yourData, method: .trash, snapshot: try #require(ItemSnapshot.read(url)))

        let error = #expect(throws: PlanError.self) {
            try Plan(tool: .largeFiles, allowedRoots: [root.url], items: [item], pathGuard: guarded)
        }

        #expect(error == .rejected(url.path, .protectedLocation(url.path, protected: exclusion.path)))
        #expect(FileManager.default.fileExists(atPath: inner.path))
    }

    // MARK: - A folder's contents (CAC-004)

    @Test func onlyDeleteRemovesTheContentsOfAFolderNotAFileCAC004SAF004() throws {
        let cache = try root.folder("Library/Caches/com.example.app")
        for method in [ActionMethod.trash, .tool, .launchctl] {
            let tier: Tier = Tier.rebuildable.allows(method) ? .rebuildable : .yourData
            let item = PlannedItem(
                url: cache, tier: tier, method: method, snapshot: try #require(ItemSnapshot.read(cache)),
                scope: .contents)
            let error = #expect(throws: PlanError.self) {
                try Plan(tool: .cachesAndLogs, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
            }
            #expect(error == .contentsNotAllowed(cache.path, method: method))
            #expect(error?.path == cache.path)
        }

        let log = try root.file("Library/Logs/app.log", size: 10)
        let ofFile = try root.planned(log, scope: .contents)
        let fileError = #expect(throws: PlanError.self) {
            try Plan(tool: .cachesAndLogs, allowedRoots: [root.url], items: [ofFile], pathGuard: pathGuard)
        }
        #expect(fileError == .contentsOfNonFolder(log.path))
    }

    @Test func aSubToolsPlanKeepsEachItemsScopeCAC004() throws {
        let cache = try root.folder("Library/Caches/com.example.app")
        let log = try root.file("Library/Logs/app.log", size: 10)
        let subTool = FixtureSubTool(tier: .rebuildable, method: .delete)
        let items = try [(cache, ItemScope.contents), (log, .item)].map { url, scope in
            ScanItem(
                url: url, snapshot: ItemSnapshot.read(url) ?? ItemSnapshot(kind: .file, allocatedSize: 0),
                tier: .rebuildable, method: .delete, reason: "Fixture file", source: FixtureSubTool.id, scope: scope,
                ruleMatch: RuleMatch(rule: try root.fixtureRule(for: url, scope: scope), modified: .now))
        }
        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        #expect(plan.items.map(\.scope) == [.contents, .item])
    }

    @Test func aPersonalFileKeepsItsIdentityIntoThePlanSAF008() throws {
        let file = try root.file("Downloads/Installer.dmg", size: 10)
        let identity = try #require(FileIdentity.read(file))
        let personal = PersonalFile(
            url: file, identity: identity, snapshot: try #require(ItemSnapshot.read(file)), modified: nil)
        let item = try #require(personal.scanItem(source: .largeFiles, reason: "Large file"))
        let plan = try Plan(subTool: LargeFiles(), items: [item], pathGuard: pathGuard)
        #expect(plan.items.map(\.identity) == [identity])
    }

    // MARK: - Snapshots

    @Test func snapshotsMeasureAllocatedSizeSAF013() throws {
        let file = try root.file("Movies/clip.mov", size: 100_000)
        let fileSnapshot = try #require(ItemSnapshot.read(file))
        #expect(fileSnapshot.kind == .file && fileSnapshot.allocatedSize >= 100_000)

        let package = try root.folder("Documents/Book.pages")
        try root.file("Documents/Book.pages/Data/one.bin", size: 50_000)
        try root.file("Documents/Book.pages/Data/two.bin", size: 50_000)
        try root.symlink("Documents/Book.pages/link", to: file)
        let packageSnapshot = try #require(ItemSnapshot.read(package))
        // The two files, but not the 100 KB file the symlink points to.
        #expect(packageSnapshot.kind == .folder)
        #expect((100_000..<200_000).contains(packageSnapshot.allocatedSize))

        let link = try root.symlink("Desktop/clip.mov", to: file)
        #expect(ItemSnapshot.read(link)?.kind == .symlink)
        #expect(ItemSnapshot.read(root.url.appending(path: "missing")) == nil)
    }

    @Test func snapshotsMatchWithinToleranceSAF008() {
        let small = ItemSnapshot(kind: .file, allocatedSize: 10_000)
        #expect(small.matches(ItemSnapshot(kind: .file, allocatedSize: 10_000 + 64 * 1024)))
        #expect(!small.matches(ItemSnapshot(kind: .file, allocatedSize: 10_000 + 64 * 1024 + 1)))
        #expect(!small.matches(ItemSnapshot(kind: .folder, allocatedSize: 10_000)))

        let large = ItemSnapshot(kind: .file, allocatedSize: 1_000_000_000)
        #expect(large.matches(ItemSnapshot(kind: .file, allocatedSize: 990_000_000)))
        #expect(!large.matches(ItemSnapshot(kind: .file, allocatedSize: 989_999_999)))
    }
}
