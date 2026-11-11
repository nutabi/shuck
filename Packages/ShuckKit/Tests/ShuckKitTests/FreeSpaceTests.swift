import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The measured change in free space after a run, and the reasons it can differ from the estimate (SAF-013, R-06).
struct FreeSpaceTests {
    private let gigabyte: Int64 = 1_000_000_000

    @Test func theVolumeOfAFixtureRootReportsItsFreeSpaceSAF013() throws {
        let root = try FixtureRoot()

        let available = try #require(FreeSpace.available(at: root.url))

        #expect(available > 0)
    }

    @Test func aPathThatDoesNotExistHasNoFreeSpace() throws {
        let root = try FixtureRoot()

        #expect(FreeSpace.available(at: try root.url("missing/folder")) == nil)
    }

    @Test func aChangeCloseToTheEstimateNeedsNoExplanationSAF013() {
        let change = FreeSpaceChange(
            before: 10 * gigabyte, after: 12 * gigabyte - 5_000_000, deleted: 2 * gigabyte, toolEstimate: nil)

        #expect(change.measured == 2 * gigabyte - 5_000_000)
        #expect(change.estimate == 2 * gigabyte)
        #expect(change.gaps.isEmpty)
    }

    @Test func farLessFreedThanDeletedIsExplainedBySnapshotsAndClonesR06() {
        let change = FreeSpaceChange(
            before: 10 * gigabyte, after: 10 * gigabyte, deleted: 2 * gigabyte, toolEstimate: nil)

        #expect(change.measured == 0)
        #expect(change.gaps == [.snapshotsAndClones, .otherActivity])
    }

    @Test func moreFreedThanDeletedIsExplainedByOtherActivityOnly() {
        let change = FreeSpaceChange(
            before: 10 * gigabyte, after: 13 * gigabyte, deleted: 2 * gigabyte, toolEstimate: nil)

        #expect(change.gaps == [.otherActivity])
    }

    @Test func aToolsEstimateIsAlwaysExplainedD125() {
        let change = FreeSpaceChange(before: 10 * gigabyte, after: 11 * gigabyte, deleted: 0, toolEstimate: gigabyte)

        #expect(change.estimate == gigabyte)
        #expect(change.gaps == [.toolEstimate])
    }

    @Test func aToolThatFreedLessIsNotBlamedOnSnapshots() {
        let change = FreeSpaceChange(before: 10 * gigabyte, after: 10 * gigabyte, deleted: 0, toolEstimate: gigabyte)

        #expect(change.gaps == [.toolEstimate, .otherActivity])
    }

    /// D-125: an unavailable simulator's cleanup has no size. Whatever it frees is its own, not other apps'; but if
    /// less is free afterwards, something else used the space.
    @Test func aToolOfUnknownSizeExplainsSpaceFreedBeyondTheEstimateD125() {
        let freedMore = FreeSpaceChange(
            before: 10 * gigabyte, after: 13 * gigabyte, deleted: gigabyte, toolEstimate: nil, toolSizeUnknown: true)
        let freedLess = FreeSpaceChange(
            before: 10 * gigabyte, after: 9 * gigabyte, deleted: 0, toolEstimate: nil, toolSizeUnknown: true)

        #expect(freedMore.estimate == gigabyte)
        #expect(freedMore.gaps == [.toolSizeUnknown])
        #expect(freedLess.gaps == [.toolSizeUnknown, .otherActivity])
    }

    /// A run that only moved items to the Trash expects to free nothing; the Trash's summary says why.
    @Test func aRunThatFreedNothingExpectedNothing() {
        let change = FreeSpaceChange(before: 10 * gigabyte, after: 10 * gigabyte - 1_000, deleted: 0, toolEstimate: nil)

        #expect(change.measured == -1_000)
        #expect(change.estimate == 0)
        #expect(change.gaps.isEmpty)
    }

    @Test func lessFreeSpaceAfterTheRunIsExplainedByOtherActivity() {
        let change = FreeSpaceChange(before: 10 * gigabyte, after: 9 * gigabyte, deleted: 0, toolEstimate: nil)

        #expect(change.measured == -gigabyte)
        #expect(change.gaps == [.otherActivity])
    }

    /// The smallest difference that needs words grows with the estimate: a tenth of it, at least 10 MB.
    @Test func theUnexplainedMarginIsATenthOfTheEstimate() {
        let within = FreeSpaceChange(
            before: 0, after: 100 * gigabyte - 9 * gigabyte, deleted: 100 * gigabyte, toolEstimate: nil)
        let beyond = FreeSpaceChange(
            before: 0, after: 100 * gigabyte - 11 * gigabyte, deleted: 100 * gigabyte, toolEstimate: nil)

        #expect(within.gaps.isEmpty)
        #expect(beyond.gaps == [.snapshotsAndClones, .otherActivity])
    }
}
