import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The measured change in free space after a run, and the reasons it can differ from the estimate (SAF-013, R-06).
struct FreeSpaceTests {
    @Test func theVolumeOfAFixtureRootReportsItsFreeSpaceAndAMissingPathHasNoneSAF013() throws {
        let root = try FixtureRoot()

        let available = try #require(FreeSpace.available(at: root.url))

        #expect(available > 0)
        #expect(FreeSpace.available(at: try root.url("missing/folder")) == nil)
    }

    struct Change: Sendable {
        let name: String
        let before: Int64
        let after: Int64
        let deleted: Int64
        var toolEstimate: Int64?
        var toolSizeUnknown = false
        let measured: Int64
        let estimate: Int64
        let gaps: [FreeSpaceChange.Gap]
    }

    private static let gigabyte: Int64 = 1_000_000_000

    /// The measured change against the estimate, and the reasons it can differ (SAF-013, R-06, D-125). The smallest
    /// difference that needs words grows with the estimate: a tenth of it, at least 10 MB.
    private static let changes: [Change] = {
        let gb = gigabyte
        return [
            Change(
                name: "close to the estimate", before: 10 * gb, after: 12 * gb - 5_000_000, deleted: 2 * gb,
                measured: 2 * gb - 5_000_000, estimate: 2 * gb, gaps: []),
            Change(
                name: "far less freed than deleted", before: 10 * gb, after: 10 * gb, deleted: 2 * gb, measured: 0,
                estimate: 2 * gb, gaps: [.snapshotsAndClones, .otherActivity]),
            Change(
                name: "more freed than deleted", before: 10 * gb, after: 13 * gb, deleted: 2 * gb, measured: 3 * gb,
                estimate: 2 * gb, gaps: [.otherActivity]),
            Change(
                name: "a tool's estimate", before: 10 * gb, after: 11 * gb, deleted: 0, toolEstimate: gb, measured: gb,
                estimate: gb, gaps: [.toolEstimate]),
            Change(
                name: "a tool that freed less", before: 10 * gb, after: 10 * gb, deleted: 0, toolEstimate: gb,
                measured: 0, estimate: gb, gaps: [.toolEstimate, .otherActivity]),
            Change(
                name: "a tool of unknown size freed more", before: 10 * gb, after: 13 * gb, deleted: gb,
                toolSizeUnknown: true, measured: 3 * gb, estimate: gb, gaps: [.toolSizeUnknown]),
            Change(
                name: "a tool of unknown size, less free after", before: 10 * gb, after: 9 * gb, deleted: 0,
                toolSizeUnknown: true, measured: -gb, estimate: 0, gaps: [.toolSizeUnknown, .otherActivity]),
            // A run that only moved items to the Trash expects to free nothing; the Trash's summary says why.
            Change(
                name: "nothing freed, nothing expected", before: 10 * gb, after: 10 * gb - 1_000, deleted: 0,
                measured: -1_000, estimate: 0, gaps: []),
            Change(
                name: "less free after the run", before: 10 * gb, after: 9 * gb, deleted: 0, measured: -gb, estimate: 0,
                gaps: [.otherActivity]),
            Change(
                name: "within a tenth of the estimate", before: 0, after: 91 * gb, deleted: 100 * gb,
                measured: 91 * gb, estimate: 100 * gb, gaps: []),
            Change(
                name: "beyond a tenth of the estimate", before: 0, after: 89 * gb, deleted: 100 * gb,
                measured: 89 * gb, estimate: 100 * gb, gaps: [.snapshotsAndClones, .otherActivity]),
        ]
    }()

    @Test(arguments: changes)
    func aChangeIsExplainedOnlyWhenItDiffersFromTheEstimateSAF013R06D125(_ change: Change) {
        let result = FreeSpaceChange(
            before: change.before, after: change.after, deleted: change.deleted, toolEstimate: change.toolEstimate,
            toolSizeUnknown: change.toolSizeUnknown)

        #expect(result.measured == change.measured, "\(change.name)")
        #expect(result.estimate == change.estimate, "\(change.name)")
        #expect(result.gaps == change.gaps, "\(change.name)")
    }
}

/// The second confirmation for an oversized Rebuildable item: its threshold is a quarter of the startup volume's used
/// space (SAF-015, D-144).
struct OversizeThresholdTests {
    private func item(_ name: String, size: Int64, tier: Tier = .rebuildable) -> PlannedItem {
        PlannedItem(
            url: URL(filePath: "/StubHome/Library/Caches/\(name)"), tier: tier,
            method: tier == .rebuildable ? .delete : .trash, snapshot: ItemSnapshot(kind: .folder, allocatedSize: size))
    }

    @Test func theVolumeOfAFixtureRootReportsItsUsedSpaceSAF015() throws {
        let root = try FixtureRoot()

        let used = try #require(FreeSpace.used(at: root.url))

        #expect(used > 0)
        #expect(FreeSpace.used(at: try root.url("missing/folder")) == nil)
    }

    /// SAF-015's fixture test: real folders, measured and planned as a scan plans them, against a made-up used space,
    /// since a fixture can never be a quarter of the real disk.
    @Test func aPlannedFixtureFolderLargerThanTheThresholdIsOversizedSAF015() throws {
        let root = try FixtureRoot()
        try root.file("Library/Caches/big/data", size: 256 * 1024)
        try root.file("Library/Caches/small/data", size: 4 * 1024)
        let big = try root.planned(try root.url("Library/Caches/big"))
        let small = try root.planned(try root.url("Library/Caches/small"))
        let plan = try Plan(
            tool: .cachesAndLogs, allowedRoots: [root.url], items: [small, big],
            pathGuard: PathGuard(configuration: root.pathGuardConfiguration()))
        let threshold = try #require(OversizeThreshold(usedSpace: 4 * 128 * 1024))

        #expect(threshold.oversized(plan.items) == [big])
    }

    @Test func onlyARebuildableItemLargerThanAQuarterOfTheUsedSpaceIsOversizedSAF015D144() throws {
        let threshold = try #require(OversizeThreshold(usedSpace: 400_000))
        #expect(threshold.bytes == 100_000)
        let items = [
            item("at", size: 100_000), item("over", size: 100_001), item("small", size: 10),
            // "Your data" has its own itemized review (SAF-002).
            item("mine", size: 300_000, tier: .yourData), item("huge", size: 900_000),
        ]

        #expect(threshold.oversized(items).compactMap(\.url?.lastPathComponent) == ["over", "huge"])
    }

    @Test func aToolsEstimateCountsLikeAnySize() throws {
        let threshold = try #require(OversizeThreshold(usedSpace: 400_000))
        let command = try ToolCommand(
            executable: "/StubTools/cleaner", arguments: ["clean"], environment: ["PATH": "/usr/bin"])
        let tool = PlannedItem(command: command, allocatedSize: 200_000, tier: .rebuildable, category: .personalFiles)

        #expect(threshold.oversized([tool]) == [tool])
    }

    /// Without the used space there is nothing to compare with, and no item needs a second confirmation.
    @Test func anUnknownUsedSpaceHasNoThreshold() {
        #expect(OversizeThreshold(usedSpace: nil) == nil)
        #expect(OversizeThreshold(usedSpace: 0) == nil)
    }
}
