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

    @Test func rowsStreamInAndStaySortedFCL012() {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size, order: .reverse)])

        results.apply(.files([file("b", size: 2_000), file("c", size: 1_000)]))
        #expect(names(results) == ["b", "c"])

        results.apply(.notAccessible(home.appending(path: "Locked")))
        results.apply(.files([file("a", size: 3_000)]))
        #expect(names(results) == ["a", "b", "c"])
    }

    @Test func everyColumnSortsFCL012() {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.apply(
            .files([
                file("Movies/clip.mov", size: 3_000, modified: old),
                file("Downloads/Setup.dmg", size: 1_000, modified: .now),
                file("Documents/notes.txt", size: 2_000),
            ]))
        #expect(names(results) == ["Setup.dmg", "notes.txt", "clip.mov"])

        results.sortOrder = [KeyPathComparator(\.name, comparator: .localizedStandard)]
        #expect(names(results) == ["clip.mov", "notes.txt", "Setup.dmg"])

        // A row without a date sorts as the oldest.
        results.sortOrder = [KeyPathComparator(\.sortDate)]
        #expect(names(results) == ["notes.txt", "clip.mov", "Setup.dmg"])

        results.sortOrder = [KeyPathComparator(\.folder, comparator: .localizedStandard)]
        #expect(names(results) == ["notes.txt", "Setup.dmg", "clip.mov"])

        // "Disk Image", "QuickTime movie", "text": the comparison ignores case.
        results.sortOrder = [KeyPathComparator(\.kind, comparator: .localizedStandard)]
        #expect(names(results) == ["Setup.dmg", "clip.mov", "notes.txt"])
    }

    @Test func onlyIncludedFilesAreListed() {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)]) {
            $0.snapshot.allocatedSize >= 2_000
        }
        results.apply(.files([file("small", size: 1_999), file("large", size: 2_000)]))
        #expect(names(results) == ["large"])
    }

    @Test func aFileListedAgainReplacesItsRow() {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.apply(.files([file("a", size: 1_000)]))
        results.apply(.files([file("a", size: 5_000)]))
        #expect(results.rows.map(\.size) == [5_000])
    }

    @Test func nothingIsSelectedAtFirstAndTheTotalIsTheSelectionsSizeFCL012() {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.apply(.files([file("a", size: 1_000), file("b", size: 2_000), file("c", size: 4_000)]))
        #expect(results.selection.isEmpty)
        #expect(results.selectedBytes == 0)

        results.selection = [home.appending(path: "a"), home.appending(path: "c")]
        #expect(results.selectedBytes == 5_000)
        #expect(results.actionableSelection.map(\.name) == ["a", "c"])
    }

    @Test func readOnlyRowsAreLeftOutOfTheTotalFCL011() {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.apply(
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

    @Test func removedRowsLeaveTheListAndTheSelectionFCL006() {
        let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size)])
        results.apply(.files([file("a", size: 1_000), file("b", size: 2_000)]))
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

    @Test func theLastOpenedColumnShowsSpotlightsDateOrALabelledFallbackOLD002() {
        let opened = Date(timeIntervalSince1970: 1_600_000_000)
        let modified = Date(timeIntervalSince1970: 1_500_000_000)
        let used = PersonalFile(
            url: home.appending(path: "used.mov"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
            modified: modified, lastOpened: LastOpened(date: opened, source: .lastUsed))
        let neverOpened = PersonalFile(
            url: home.appending(path: "new.dmg"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
            modified: modified, lastOpened: LastOpened(date: modified, source: .modified))
        let notLookedUp = PersonalFile(
            url: home.appending(path: "small.txt"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
            modified: modified)
        let noDate = PersonalFile(
            url: home.appending(path: "odd"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1), modified: nil)

        let usedRow = ResultRow(used, home: home, dateColumn: .lastOpened)
        #expect(usedRow.date == opened && !usedRow.dateIsModifiedFallback)
        for file in [neverOpened, notLookedUp] {
            let row = ResultRow(file, home: home, dateColumn: .lastOpened)
            #expect(row.date == modified && row.dateIsModifiedFallback)
        }
        #expect(!ResultRow(noDate, home: home, dateColumn: .lastOpened).dateIsModifiedFallback)

        // The modified column never marks a fallback.
        let modifiedRow = ResultRow(used, home: home, dateColumn: .modified)
        #expect(modifiedRow.date == modified && !modifiedRow.dateIsModifiedFallback)
    }

    @Test func aLastOpenedListSortsByTheDateItShows() {
        let results = PersonalFilesResults(
            home: home, sortOrder: [KeyPathComparator(\.sortDate)], dateColumn: .lastOpened)
        results.apply(
            .files([
                PersonalFile(
                    url: home.appending(path: "recent"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
                    modified: Date(timeIntervalSince1970: 100),
                    lastOpened: LastOpened(date: Date(timeIntervalSince1970: 900), source: .lastUsed)),
                PersonalFile(
                    url: home.appending(path: "stale"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 1),
                    modified: Date(timeIntervalSince1970: 500)),
            ]))
        #expect(names(results) == ["stale", "recent"])
    }
}
