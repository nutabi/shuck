import Foundation
import ShuckKit
import ShuckKitTestSupport
import Synchronization
import Testing

/// "Last opened" is Spotlight's last-used date, or the content-modified date when Spotlight has none (OLD-002).
struct LastOpenedTests {
    let root: FixtureRoot
    let opened = Date(timeIntervalSince1970: 1_600_000_000)
    let modified = Date(timeIntervalSince1970: 1_500_000_000)

    init() throws {
        root = try FixtureRoot()
    }

    @Test func spotlightsLastUsedDateComesFirstOLD002() {
        let opened = opened
        let reader = LastOpenedReader(minimumSize: 0) { _ in opened }

        let lastOpened = reader.read(root.url.appending(path: "a.mov"), size: 10, modified: modified)

        #expect(lastOpened == LastOpened(date: opened, source: .lastUsed))
    }

    @Test func withoutALastUsedDateItFallsBackToTheModifiedDateOLD002() {
        let reader = LastOpenedReader(minimumSize: 0) { _ in nil }

        #expect(
            reader.read(root.url.appending(path: "a.mov"), size: 10, modified: modified)
                == LastOpened(date: modified, source: .modified))
        #expect(reader.read(root.url.appending(path: "a.mov"), size: 10, modified: nil) == nil)
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

    /// Whether Spotlight has a last-used date for a new fixture file depends on the Mac, so either answer passes; a
    /// fallback must carry the modified date.
    @Test func theSpotlightReaderAnswersForARealFile() throws {
        let file = try root.file("Downloads/new.dmg", size: 10, modified: modified)
        #expect(LastOpenedReader.spotlightLastUsedDate(root.url.appending(path: "Downloads/missing.dmg")) == nil)

        let lastOpened = try #require(LastOpenedReader(minimumSize: 0).read(file, size: 10, modified: modified))
        if lastOpened.source == .modified {
            #expect(lastOpened.date == modified)
        }
    }

    @Test func theScanLooksUpLastOpenedDatesForLargeEnoughItemsOLD002() async throws {
        try root.file("Movies/large.mov", size: 8_192, modified: modified)
        try root.file("Documents/small.txt", size: 10, modified: modified)
        try root.file("Documents/Report.rtfd/TXT.rtf", size: 8_192, modified: modified)
        let opened = opened
        let reader = LastOpenedReader(minimumSize: 8_192) { url in
            url.lastPathComponent == "large.mov" ? opened : nil
        }
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
