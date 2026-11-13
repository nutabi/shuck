import Foundation
import ShuckKit
import Testing

@testable import Shuck

/// The results list Large Files and Old Files show (FCL-012).
///
/// The files are made up: the list reads nothing from disk, so these tests never touch the file system.
@MainActor
struct PersonalFilesResultsTests {
    let home = URL(filePath: "/StubHome", directoryHint: .isDirectory)

    func file(
        _ path: String, size: Int64 = 1_000, modified: Date? = nil, readOnly: ReadOnlyReason? = nil
    ) -> PersonalFile {
        PersonalFile(
            url: home.appending(path: path), snapshot: ItemSnapshot(kind: .file, allocatedSize: size),
            modified: modified, readOnly: readOnly)
    }

    func names(_ results: PersonalFilesResults) -> [String] {
        results.rows.map(\.name)
    }

    func row(_ path: String, size: Int64 = 1_000, modified: Date? = nil) -> ResultRow {
        ResultRow(file(path, size: size, modified: modified), home: home)
    }

    @Test func rowsStreamInAndStaySortedFCL012() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size, order: .reverse)])

        await results.apply(.files([file("b", size: 2_000), file("c", size: 1_000)]))
        #expect(names(results) == ["b", "c"])

        await results.apply(.notAccessible(home.appending(path: "Locked")))
        await results.apply(.files([file("a", size: 3_000)]))
        #expect(names(results) == ["a", "b", "c"])
    }

    @Test func everyColumnSortsFCL012() async {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        await results.apply(
            .files([
                file("Movies/clip.mov", size: 3_000, modified: old),
                file("Downloads/Setup.dmg", size: 1_000, modified: .now),
                file("Documents/notes.txt", size: 2_000),
            ]))
        #expect(names(results) == ["Setup.dmg", "notes.txt", "clip.mov"])

        results.sortOrder = [KeyPathComparator(\.name, comparator: .localizedStandard)]

        await results.finishSorting()
        #expect(names(results) == ["clip.mov", "notes.txt", "Setup.dmg"])

        // A row without a date sorts as the oldest.
        results.sortOrder = [KeyPathComparator(\.sortDate)]
        await results.finishSorting()
        #expect(names(results) == ["notes.txt", "clip.mov", "Setup.dmg"])

        results.sortOrder = [KeyPathComparator(\.folder, comparator: .localizedStandard)]

        await results.finishSorting()
        #expect(names(results) == ["notes.txt", "Setup.dmg", "clip.mov"])

        // "Disk Image", "QuickTime movie", "text": the comparison ignores case.
        results.sortOrder = [KeyPathComparator(\.kind, comparator: .localizedStandard)]
        await results.finishSorting()
        #expect(names(results) == ["Setup.dmg", "clip.mov", "notes.txt"])
    }

    @Test func onlyIncludedFilesAreListed() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)]) {
            $0.snapshot.allocatedSize >= 2_000
        }
        await results.apply(.files([file("small", size: 1_999), file("large", size: 2_000)]))
        #expect(names(results) == ["large"])
    }

    @Test func aFileListedAgainReplacesItsRow() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        await results.apply(.files([file("a", size: 1_000)]))
        await results.apply(.files([file("a", size: 5_000)]))
        #expect(results.rows.map(\.size) == [5_000])
    }

    @Test func nothingIsSelectedAtFirstAndTheTotalIsTheSelectionsSizeFCL012() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        await results.apply(.files([file("a", size: 1_000), file("b", size: 2_000), file("c", size: 4_000)]))
        #expect(results.selection.isEmpty)
        #expect(results.selectedBytes == 0)

        results.selection = [home.appending(path: "a"), home.appending(path: "c")]
        #expect(results.selectedBytes == 5_000)
        #expect(results.actionableSelection.map(\.name) == ["a", "c"])
    }

    @Test func readOnlyRowsAreLeftOutOfTheTotalFCL011() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        await results.apply(
            .files([
                file("a", size: 1_000),
                file("go/pkg/mod", size: 8_000, readOnly: .managedBy(.developerJunk)),
            ]))
        results.selection = [home.appending(path: "a")]
        #expect(!results.selectionIncludesReadOnly)

        results.selection.insert(home.appending(path: "go/pkg/mod"))
        #expect(results.selectionIncludesReadOnly)
        #expect(results.selectedBytes == 1_000)
        #expect(results.actionableSelection.map(\.name) == ["a"])
    }

    @Test func removedRowsLeaveTheListAndTheSelectionFCL006() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        await results.apply(.files([file("a", size: 1_000), file("b", size: 2_000)]))
        results.selection = [home.appending(path: "a"), home.appending(path: "b")]

        results.remove([home.appending(path: "a")])

        #expect(names(results) == ["b"])
        #expect(results.selection == [home.appending(path: "b")])
        #expect(results.selectedBytes == 2_000)
    }

    @Test func rowsShowTheFolderUnderHomeAsTilde() {
        #expect(ResultRow.folder(of: home.appending(path: "Downloads/a.dmg"), home: home) == "~/Downloads")
        #expect(ResultRow.folder(of: home.appending(path: "a.dmg"), home: home) == "~")
        #expect(ResultRow.folder(of: URL(filePath: "/Volumes/Data/a.dmg"), home: home) == "/Volumes/Data")
    }

    @Test func rowsShowTheKindFromTheNameExtension() {
        let file = ItemSnapshot(kind: .file, allocatedSize: 0)
        let folder = ItemSnapshot(kind: .folder, allocatedSize: 0)
        #expect(ResultRow.kind(of: URL(filePath: "/a.dmg"), snapshot: file) == "Disk Image")
        #expect(ResultRow.kind(of: URL(filePath: "/README"), snapshot: file) == "Document")
        #expect(ResultRow.kind(of: URL(filePath: "/Backup/00008110"), snapshot: folder) == "Folder")
    }

    /// The column shows the date Old Files judged by and labels it when it is not the last-opened date (D-130).
    @Test func theLastOpenedColumnShowsTheDecidingDateAndLabelsItOLD002() {
        let opened = Date(timeIntervalSince1970: 1_600_000_000)
        let modified = Date(timeIntervalSince1970: 1_500_000_000)
        func file(_ name: String, _ lastOpened: LastOpened?) -> PersonalFile {
            PersonalFile(
                url: home.appending(path: name), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
                modified: modified, lastOpened: lastOpened)
        }

        let used = ResultRow(
            file("used.mov", LastOpened(date: opened, source: .lastUsed)), home: home, dateColumn: .lastOpened)
        #expect(used.date == opened && used.dateSource == nil)
        for source in [LastOpened.Source.modified, .added] {
            let row = ResultRow(
                file("a.dmg", LastOpened(date: opened, source: source)), home: home, dateColumn: .lastOpened)
            #expect(row.date == opened && row.dateSource == source)
        }
        // A file that was not looked up has no last-opened date to show.
        let notLookedUp = ResultRow(file("small.txt", nil), home: home, dateColumn: .lastOpened)
        #expect(notLookedUp.date == nil && notLookedUp.dateSource == nil)

        // The modified column shows the modified date, unlabelled.
        let modifiedRow = ResultRow(
            file("b.dmg", LastOpened(date: opened, source: .added)), home: home, dateColumn: .modified)
        #expect(modifiedRow.date == modified && modifiedRow.dateSource == nil)
    }

    @Test func aLastOpenedListSortsByTheDateItShows() async {
        let results = PersonalFilesResults(
            home: home, sortOrder: [KeyPathComparator(\.sortDate)], dateColumn: .lastOpened)
        await results.apply(
            .files([
                PersonalFile(
                    url: home.appending(path: "recent"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
                    modified: Date(timeIntervalSince1970: 100),
                    lastOpened: LastOpened(date: Date(timeIntervalSince1970: 900), source: .lastUsed)),
                PersonalFile(
                    url: home.appending(path: "stale"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
                    modified: Date(timeIntervalSince1970: 100),
                    lastOpened: LastOpened(date: Date(timeIntervalSince1970: 500), source: .added)),
            ]))
        #expect(names(results) == ["stale", "recent"])
    }

    // MARK: Merging batches (TD-09, NFR-PERF-001)

    /// What the list showed before it merged batches: every row sorted again after each batch.
    func fullSort(_ rows: [ResultRow], adding incoming: [ResultRow], by order: [KeyPathComparator<ResultRow>])
        -> [ResultRow]
    {
        let incomingIDs = Set(incoming.map(\.id))
        return (rows.filter { !incomingIDs.contains($0.id) } + incoming).sorted(using: order)
    }

    /// Random batches with few distinct sizes, dates and names, so most rows tie on some column, and some files listed
    /// again with a new size.
    func randomBatches(seed: UInt64) -> [[ResultRow]] {
        var random = SplitMix64(seed: seed)
        let dates = [nil, Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)]
        return (0..<40).map { _ in
            (0..<Int.random(in: 0...30, using: &random)).map { _ in
                let folder = ["Downloads", "Movies", ""].randomElement(using: &random) ?? ""
                let name = ["a.dmg", "B.mov", "c", "a10.txt", "a9.txt"].randomElement(using: &random) ?? ""
                let path = "\(folder)/\(Int.random(in: 0..<200, using: &random))/\(name)"
                return row(
                    path, size: Int64.random(in: 1...4, using: &random) * 1_000,
                    modified: dates.randomElement(using: &random) ?? nil)
            }
        }
    }

    nonisolated static let sortOrders: [[KeyPathComparator<ResultRow>]] = [
        [KeyPathComparator(\.size, order: .reverse)],
        [KeyPathComparator(\.sortDate)],
        [KeyPathComparator(\.name, comparator: .localizedStandard)],
        [KeyPathComparator(\.kind, comparator: .localizedStandard), KeyPathComparator(\.size)],
        [
            KeyPathComparator(\.folder, comparator: .localizedStandard, order: .reverse),
            KeyPathComparator(\.sortDate, order: .reverse),
        ],
    ]

    @Test(arguments: sortOrders)
    func mergedBatchesMatchAFullSortTiesIncluded(order: [KeyPathComparator<ResultRow>]) throws {
        for seed in UInt64(1)...20 {
            let results = PersonalFilesResults(home: home, sortOrder: order)
            var expected: [ResultRow] = []
            for batch in randomBatches(seed: seed) {
                results.insert(batch)
                expected = fullSort(expected, adding: batch, by: order)
                try #require(results.rows == expected, "seed \(seed)")
            }
        }
    }

    @Test func aSortOrderChangeSortsAgainAndLaterBatchesFollowIt() async throws {
        let bySize = [KeyPathComparator(\ResultRow.size)]
        let byName = [KeyPathComparator(\ResultRow.name, comparator: .localizedStandard)]
        let results = PersonalFilesResults(home: home, sortOrder: bySize)
        var expected: [ResultRow] = []
        for (index, batch) in randomBatches(seed: 7).enumerated() {
            if index == 20 {
                results.sortOrder = byName
                await results.finishSorting()
                expected.sort(using: byName)
                try #require(results.rows == expected)
            }
            results.insert(batch)
            expected = fullSort(expected, adding: batch, by: index < 20 ? bySize : byName)
            try #require(results.rows == expected)
        }
    }

    @Test func aRemovedFileListedAgainComesBackOnce() {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.insert([row("a", size: 1_000), row("b", size: 2_000)])
        results.remove([home.appending(path: "a")])
        results.insert([row("a", size: 3_000)])
        #expect(names(results) == ["b", "a"])

        results.insert([row("b", size: 4_000)])
        #expect(results.rows.map(\.size) == [3_000, 4_000])

        results.removeAll()
        results.insert([row("a", size: 1_000)])
        #expect(names(results) == ["a"])
    }

    @Test func groupsFollowEveryChangeOfTheRowsLRG003() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.insert([row("Movies/a", size: 3_000), row("Movies/b", size: 1_000), row("Downloads/c", size: 2_000)])
        #expect(results.groups.map(\.topFolder) == ["Movies", "Downloads"])
        #expect(results.groups.first?.rows.map(\.name) == ["b", "a"])

        results.insert([row("Downloads/d", size: 5_000)])
        #expect(results.groups.map(\.topFolder) == ["Downloads", "Movies"])

        results.sortOrder = [KeyPathComparator(\.size, order: .reverse)]

        await results.finishSorting()
        #expect(results.groups.last?.rows.map(\.name) == ["a", "b"])

        results.remove([home.appending(path: "Downloads/d")])
        #expect(results.groups.map(\.topFolder) == ["Movies", "Downloads"])

        results.removeAll()
        #expect(results.groups.isEmpty)
    }

    /// FCL-012, LRG-003: preview, Finder and review follow visible folder sections, rather than interleaving files
    /// from different groups. A partial selection keeps that order and ignores URLs no longer listed.
    @Test(arguments: [true, false])
    func selectedURLsFollowTheDisplayedOrderLRG003(grouped: Bool) async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size, order: .reverse)])
        let holiday = row("Movies/Holiday.mov", size: 6_000)
        let installer = row("Downloads/Installer.dmg", size: 2_000)
        let clip = row("Movies/Clip.mov", size: 1_000)
        results.insert([holiday, installer, clip])
        let all = Set([holiday.id, installer.id, clip.id])

        #expect(
            results.ordered(all, grouped: grouped)
                == (grouped ? [holiday.id, clip.id, installer.id] : [holiday.id, installer.id, clip.id]))
        #expect(
            results.ordered([clip.id, installer.id, home.appending(path: "missing")], grouped: grouped)
                == (grouped ? [clip.id, installer.id] : [installer.id, clip.id]))
        #expect(results.ordered([], grouped: grouped).isEmpty)

        results.sortOrder = [KeyPathComparator(\.size)]

        await results.finishSorting()
        #expect(
            results.ordered(all, grouped: grouped)
                == (grouped ? [clip.id, holiday.id, installer.id] : [clip.id, installer.id, holiday.id]))
        results.remove([clip.id])
        #expect(
            results.ordered(all, grouped: grouped)
                == (grouped ? [holiday.id, installer.id] : [installer.id, holiday.id]))
    }

    // MARK: Sorting off the main actor and incremental totals (NFR-PERF-001)

    func sizeRows() -> [ResultRow] {
        [
            row("Movies/b.mov", size: 3_000, modified: Date(timeIntervalSince1970: 3)),
            row("Downloads/a.dmg", size: 1_000, modified: Date(timeIntervalSince1970: 9)),
            row("Documents/c.txt", size: 2_000),
        ]
    }

    @Test(arguments: [
        ([KeyPathComparator(\ResultRow.size)], ["a.dmg", "c.txt", "b.mov"]),
        ([KeyPathComparator(\ResultRow.size, order: .reverse)], ["b.mov", "c.txt", "a.dmg"]),
        ([KeyPathComparator(\ResultRow.name, comparator: .localizedStandard)], ["a.dmg", "b.mov", "c.txt"]),
        (
            [KeyPathComparator(\ResultRow.name, comparator: .localizedStandard, order: .reverse)],
            ["c.txt", "b.mov", "a.dmg"]
        ),
        ([KeyPathComparator(\ResultRow.sortDate)], ["c.txt", "b.mov", "a.dmg"]),
        ([KeyPathComparator(\ResultRow.sortDate, order: .reverse)], ["a.dmg", "b.mov", "c.txt"]),
        ([KeyPathComparator(\ResultRow.folder, comparator: .localizedStandard)], ["c.txt", "a.dmg", "b.mov"]),
        ([KeyPathComparator(\ResultRow.kind, comparator: .localizedStandard)], ["a.dmg", "b.mov", "c.txt"]),
    ])
    func aSortOrderChangeSortsOffTheMainActorNFRPERF001(
        order: [KeyPathComparator<ResultRow>], expected: [String]
    ) async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.id.path)])
        results.insert(sizeRows())
        results.sortOrder = order
        await results.finishSorting()
        #expect(names(results) == expected)
    }

    @Test func theTableKeepsThePreviousOrderUntilTheSortFinishesNFRPERF001() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.insert(sizeRows())
        results.sortOrder = [KeyPathComparator(\.size, order: .reverse)]
        #expect(names(results) == ["a.dmg", "c.txt", "b.mov"])
        await results.finishSorting()
        #expect(names(results) == ["b.mov", "c.txt", "a.dmg"])
    }

    @Test func aStaleSortNeverOverwritesANewerOneNFRPERF001() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.insert(sizeRows())
        // Both sorts start before either finishes; only the second may land.
        results.sortOrder = [KeyPathComparator(\.size, order: .reverse)]
        results.sortOrder = [KeyPathComparator(\.name, comparator: .localizedStandard)]
        await results.finishSorting()
        #expect(names(results) == ["a.dmg", "b.mov", "c.txt"])
        // Give a discarded sort time to land, if it wrongly would.
        await Task.yield()
        #expect(names(results) == ["a.dmg", "b.mov", "c.txt"])
    }

    @Test func rowsChangedWhileSortingJoinTheSortedListNFRPERF001() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.insert(sizeRows())
        results.sortOrder = [KeyPathComparator(\.size, order: .reverse)]
        // While the sort runs: a new row, a replaced row and a removed row.
        results.insert([row("new.bin", size: 2_500), row("Downloads/a.dmg", size: 9_000)])
        results.remove([home.appending(path: "Documents/c.txt")])
        await results.finishSorting()
        #expect(names(results) == ["a.dmg", "b.mov", "new.bin"])

        results.removeAll()
        results.sortOrder = [KeyPathComparator(\.size)]
        results.removeAll()
        await results.finishSorting()
        #expect(results.rows.isEmpty)
    }

    /// The totals match a recount of every row (the old footer) after each step.
    func expectTotalsMatchRecount(_ results: PersonalFilesResults, _ step: String) {
        let rows = results.actionableSelection
        #expect(results.actionableCount == rows.count, "\(step)")
        #expect(results.selectedBytes == rows.reduce(0) { $0 + $1.size }, "\(step)")
        #expect(
            results.selectionIncludesReadOnly
                == results.rows.contains { results.selection.contains($0.id) && $0.readOnly != nil }, "\(step)")
    }

    @Test func theTotalsFollowEverySelectionChangeNFRPERF001() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        await results.apply(
            .files([
                file("a", size: 1_000), file("b", size: 2_000), file("c", size: 4_000),
                file("go/pkg", size: 8_000, readOnly: .managedBy(.developerJunk)),
            ]))
        let a = home.appending(path: "a")
        let b = home.appending(path: "b")
        let pkg = home.appending(path: "go/pkg")

        results.selection = [a, b]
        expectTotalsMatchRecount(results, "select two")
        #expect(results.actionableCount == 2 && results.selectedBytes == 3_000)

        results.selection.remove(a)
        expectTotalsMatchRecount(results, "deselect one")
        #expect(results.selectedBytes == 2_000)

        results.selection.insert(pkg)
        expectTotalsMatchRecount(results, "read-only")
        #expect(results.readOnlyCount == 1 && results.selectedBytes == 2_000)

        results.selectAll()
        expectTotalsMatchRecount(results, "select all")
        #expect(results.actionableCount == 3 && results.selectedBytes == 7_000)

        // A file listed again with another size or read-only mark updates the totals.
        await results.apply(.files([file("b", size: 500), file("c", size: 4_000, readOnly: .protected)]))
        expectTotalsMatchRecount(results, "rescan")
        #expect(results.actionableCount == 2 && results.selectedBytes == 1_500)

        results.remove([a, pkg])
        expectTotalsMatchRecount(results, "remove")
        #expect(results.actionableCount == 1 && results.readOnlyCount == 1 && results.selectedBytes == 500)

        results.selection = []
        expectTotalsMatchRecount(results, "select none")
        #expect(results.actionableCount == 0 && results.readOnlyCount == 0 && results.selectedBytes == 0)

        results.selectAll()
        results.removeAll()
        expectTotalsMatchRecount(results, "new scan")
        #expect(results.actionableCount == 0 && results.readOnlyCount == 0 && results.selectedBytes == 0)
    }
}

/// A size that could not be measured fully reads "At least" (SAF-012, NFR-A11Y-001, D-NEXT-partial-size).
@MainActor
struct PartialSizeTests {
    let home = URL(filePath: "/StubHome", directoryHint: .isDirectory)

    func partial(_ path: String, size: Int64, isComplete: Bool) -> PersonalFile {
        PersonalFile(
            url: home.appending(path: path),
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: size, isComplete: isComplete), modified: nil,
            readOnly: nil)
    }

    @Test func aRowKeepsItsSnapshotsCompletenessSAF012() {
        let whole = ResultRow(partial("whole", size: 5_000, isComplete: true), home: home)
        let lower = ResultRow(partial("lower", size: 5_000, isComplete: false), home: home)

        #expect(whole.isComplete && !lower.isComplete)
        #expect(whole.size == lower.size, "The mark changes the words, never the number")
    }

    @Test func theMarkDoesNotChangeSortingOrTotalsSAF012() async {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size, order: .reverse)])

        await results.apply(
            .files([
                partial("small", size: 1_000, isComplete: true), partial("big", size: 9_000, isComplete: false),
            ]))

        #expect(results.rows.map(\.name) == ["big", "small"])
        #expect(results.rows.map(\.size) == [9_000, 1_000])
    }

    @Test func onlyAnIncompleteSnapshotIsALowerBoundSAF012NFRA11Y001() throws {
        #expect(SizeText.isComplete(nil), "A tool's command has no snapshot and no lower bound")
        #expect(SizeText.isComplete(ItemSnapshot(kind: .folder, allocatedSize: 1)))
        #expect(!SizeText.isComplete(ItemSnapshot(kind: .folder, allocatedSize: 1, isComplete: false)))
    }
}

/// A random number generator with a seed, so a failing random test can be run again.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

}
