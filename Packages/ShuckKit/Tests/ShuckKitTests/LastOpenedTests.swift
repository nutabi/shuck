import Foundation
import ShuckKit
import ShuckKitTestSupport
import Synchronization
import Testing

/// "Last opened" is the latest of Spotlight's last-used date, the content-modified date and the date the file was added
/// to its folder, and says which one decided (OLD-002, D-130).
struct LastOpenedTests {
    let root: FixtureRoot
    let opened = Date(timeIntervalSince1970: 1_600_000_000)
    let modified = Date(timeIntervalSince1970: 1_500_000_000)

    init() throws {
        root = try FixtureRoot()
    }

    private func reader(opened: Date?, added: Date?) -> LastOpenedReader {
        LastOpenedReader(minimumSize: 0, lastUsedDate: { _ in opened }, addedDate: { _ in added })
    }

    /// A file a script rewrites daily, or one copied yesterday, must not look old because Spotlight saw it opened long
    /// ago (D-130).
    @Test(arguments: LastOpened.Source.allCases)
    func eachDateCanDecideAndTheLatestCountsOLD002(latest: LastOpened.Source) {
        let older = Date(timeIntervalSince1970: 1_000_000_000)
        let newest = Date(timeIntervalSince1970: 1_700_000_000)
        func date(_ source: LastOpened.Source) -> Date { source == latest ? newest : older }

        let lastOpened = reader(opened: date(.lastUsed), added: date(.added))
            .read(root.url.appending(path: "a.mov"), size: 10, modified: date(.modified))

        #expect(lastOpened == LastOpened(date: newest, source: latest))
    }

    @Test func aMissingDateIsIgnoredOLD002() {
        let url = root.url.appending(path: "a.mov")

        #expect(
            reader(opened: nil, added: nil).read(url, size: 10, modified: modified)
                == LastOpened(date: modified, source: .modified))
        #expect(
            reader(opened: nil, added: opened).read(url, size: 10, modified: nil)
                == LastOpened(date: opened, source: .added))
        #expect(reader(opened: nil, added: nil).read(url, size: 10, modified: nil) == nil)
    }

    @Test func whenDatesAreEqualOpenedIsNamedFirstOLD002() {
        let lastOpened = reader(opened: modified, added: modified)
            .read(root.url.appending(path: "a.mov"), size: 10, modified: modified)

        #expect(lastOpened == LastOpened(date: modified, source: .lastUsed))
    }

    /// Editing a document inside a package changes the file inside, not the package's own date (D-130).
    @Test func aFoldersModifiedDateIsTheNewestOfItAndItsDirectChildrenOLD002() throws {
        let child = Date(timeIntervalSince1970: 1_550_000_000)
        try root.file("Documents/Report.rtfd/TXT.rtf", size: 10, modified: child)
        try root.file("Documents/Report.rtfd/old.png", size: 10, modified: modified)
        let package = try root.url("Documents/Report.rtfd")
        let reader = reader(opened: nil, added: nil)

        #expect(
            reader.read(package, size: 10, modified: modified, isFolder: true)
                == LastOpened(date: child, source: .modified))
        // An item that is not a folder is not listed.
        #expect(
            reader.read(package, size: 10, modified: modified) == LastOpened(date: modified, source: .modified))
    }

    @Test func itemsBelowTheMinimumSizeAreNotLookedUp() {
        let lookups = Mutex(0)
        let opened = opened
        let reader = LastOpenedReader(minimumSize: 1_000) { _ in
            lookups.withLock { $0 += 1 }
            return opened
        }

        #expect(reader.read(root.url.appending(path: "small"), size: 999, modified: modified) == nil)
        #expect(lookups.withLock { $0 } == 0)
        #expect(reader.read(root.url.appending(path: "large"), size: 1_000, modified: modified)?.source == .lastUsed)
        #expect(lookups.withLock { $0 } == 1)
    }

    /// Whether Spotlight has a last-used date for a new fixture file depends on the Mac, so only a missing file's
    /// answer is certain. A file made just now was added to its folder just now, later than its old modified date.
    @Test func theRealReadersAnswerForARealFile() throws {
        let start = Date.now.addingTimeInterval(-60)
        let file = try root.file("Downloads/new.dmg", size: 10, modified: modified)
        let missing = root.url.appending(path: "Downloads/missing.dmg")
        #expect(LastOpenedReader.spotlightLastUsedDate(missing) == nil)
        #expect(LastOpenedReader.addedToFolderDate(missing) == nil)

        let added = try #require(LastOpenedReader.addedToFolderDate(file))
        #expect(added >= start)
        let lastOpened = try #require(LastOpenedReader(minimumSize: 0).read(file, size: 10, modified: modified))
        #expect(lastOpened.date >= start)
    }

    @Test func theScanLooksUpLastOpenedDatesForLargeEnoughItemsOLD002() async throws {
        try root.file("Movies/large.mov", size: 8_192, modified: modified)
        try root.file("Documents/small.txt", size: 10, modified: modified)
        try root.file("Documents/Report.rtfd/TXT.rtf", size: 8_192, modified: modified)
        let opened = opened
        let reader = LastOpenedReader(
            minimumSize: 8_192, lastUsedDate: { url in url.lastPathComponent == "large.mov" ? opened : nil },
            addedDate: { _ in nil })
        let scanner = PersonalFilesScanner(
            context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()), lastOpened: reader)

        var state = PersonalFilesState()
        for await event in scanner.scan() {
            state.apply(event)
        }
        let byName = Dictionary(uniqueKeysWithValues: state.items.values.map { ($0.url.lastPathComponent, $0) })

        #expect(byName["large.mov"]?.lastOpened == LastOpened(date: opened, source: .lastUsed))
        #expect(byName["Report.rtfd"]?.lastOpened?.source == .modified)
        #expect(byName["small.txt"]?.lastOpened == nil)
        #expect(byName["small.txt"]?.modified != nil)
    }

    @Test func withoutAReaderTheScanLooksUpNothing() async throws {
        try root.file("Movies/large.mov", size: 8_192, modified: modified)
        let scanner = PersonalFilesScanner(
            context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()))

        var state = PersonalFilesState()
        for await event in scanner.scan() {
            state.apply(event)
        }

        #expect(state.items.values.map(\.lastOpened) == [nil])
    }
}
