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
        let item = PlannedItem(url: file, tier: tier, method: method, snapshot: try #require(ItemSnapshot.read(file)))
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

    @Test func yourDataIsNeverDeletedSAF004() {
        #expect(!Tier.yourData.allows(.delete))
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
