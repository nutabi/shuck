import Foundation
import ShuckKit
import ShuckKitTestSupport
import Synchronization
import Testing

/// Old Files lists personal files not opened for at least a period and at least a minimum size (OLD-001), by the latest
/// of their last-opened, modified and added dates (OLD-002, D-130).
struct OldFilesTests {
    let root: FixtureRoot
    /// A minimum the file system's 4 KiB blocks can match exactly, so allocated sizes land on either side of it.
    let minimum: Int64 = 1 << 20
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        root = try FixtureRoot()
    }

    private func file(
        _ path: String, size: Int64? = nil, modified: Date? = nil, lastOpened: LastOpened? = nil
    ) -> PersonalFile {
        PersonalFile(
            url: root.url.appending(path: path), snapshot: ItemSnapshot(kind: .file, allocatedSize: size ?? minimum),
            modified: modified, lastOpened: lastOpened)
    }

    private func opened(_ date: Date) -> LastOpened { LastOpened(date: date, source: .lastUsed) }

    @Test func listsFilesNotOpenedForAtLeastThePeriodOLD001() throws {
        let oldFiles = OldFiles(periodMonths: 12, minimumSize: minimum)
        let cutoff = try #require(Calendar.current.date(byAdding: .month, value: -12, to: now))

        #expect(oldFiles.cutoff(now: now) == cutoff)
        #expect(oldFiles.includes(file("a.mov", lastOpened: opened(cutoff)), now: now))
        #expect(oldFiles.includes(file("b.mov", lastOpened: opened(cutoff.addingTimeInterval(-86_400))), now: now))
        #expect(!oldFiles.includes(file("c.mov", lastOpened: opened(cutoff.addingTimeInterval(1))), now: now))

        // A shorter period lists the file opened just after the 12-month cutoff.
        let sixMonths = OldFiles(periodMonths: 6, minimumSize: minimum)
        #expect(sixMonths.includes(file("c.mov", lastOpened: opened(cutoff.addingTimeInterval(1))), now: now))
    }

    @Test func filesBelowTheMinimumSizeAreNotListedUnlessItIsZeroOLD001() {
        let longAgo = now.addingTimeInterval(-5 * 365 * 86_400)
        let small = file("notes.txt", size: minimum - 1, lastOpened: opened(longAgo))

        #expect(!OldFiles(minimumSize: minimum).includes(small, now: now))
        #expect(OldFiles(minimumSize: minimum).includes(file("big.mov", lastOpened: opened(longAgo)), now: now))
        #expect(OldFiles(minimumSize: 0).includes(small, now: now))
    }

    /// The scan works out the latest date (``LastOpenedReader``); Old Files judges by it alone, never by the modified
    /// date the scan also records, which can be older (D-130).
    @Test func onlyTheLastOpenedDateCountsOLD002() {
        let oldFiles = OldFiles(minimumSize: minimum)
        let longAgo = now.addingTimeInterval(-5 * 365 * 86_400)
        let lastWeek = now.addingTimeInterval(-7 * 86_400)

        #expect(!oldFiles.includes(file("a.mov", modified: longAgo, lastOpened: opened(lastWeek)), now: now))
        #expect(oldFiles.includes(file("b.mov", modified: longAgo, lastOpened: opened(longAgo)), now: now))
        // Without a last-opened date, nothing shows the file is old.
        #expect(!oldFiles.includes(file("c.mov", modified: longAgo), now: now))
    }

    @Test func aFileWithNoDateIsNotListed() {
        #expect(!OldFiles(minimumSize: 0).includes(file("a.mov"), now: now))
    }

    @Test func theReasonNamesTheDateThatDecidedOLD002() {
        let oldFiles = OldFiles(periodMonths: 24)
        let longAgo = now.addingTimeInterval(-5 * 365 * 86_400)
        func reason(_ source: LastOpened.Source) -> String {
            String(
                localized: oldFiles.reason(for: file("a.mov", lastOpened: LastOpened(date: longAgo, source: source))))
        }

        #expect(reason(.lastUsed) == "Not opened in 24 months")
        #expect(reason(.modified) == "Not modified in 24 months")
        #expect(reason(.added) == "Added more than 24 months ago")
        #expect(OldFiles(periodMonths: 1).period == "1 month")
    }

    @Test func aScanLooksUpLastOpenedDatesForLargeEnoughFilesOnlyOLD001OLD002() async throws {
        let longAgo = Date.now.addingTimeInterval(-3 * 365 * 86_400)
        let recently = Date.now.addingTimeInterval(-86_400)
        let addedLongAgo = longAgo.addingTimeInterval(-86_400)
        try root.file("Movies/opened-long-ago.mov", size: Int(minimum), modified: recently)
        try root.file("Movies/opened-recently.mov", size: Int(minimum), modified: longAgo)
        try root.file("Downloads/never-opened.dmg", size: Int(minimum), modified: longAgo)
        try root.file("Downloads/changed-recently.dmg", size: Int(minimum), modified: recently)
        try root.file("Downloads/copied-recently.dmg", size: Int(minimum), modified: longAgo)
        try root.file("Documents/small.txt", size: 10, modified: longAgo)
        let lookups = Mutex<Set<String>>([])
        let oldFiles = OldFiles(
            minimumSize: minimum,
            lastUsedDate: { url in
                lookups.withLock { _ = $0.insert(url.lastPathComponent) }
                switch url.lastPathComponent {
                case "opened-long-ago.mov": return longAgo
                case "opened-recently.mov": return recently
                default: return nil
                }
            },
            // A day before the files' modified dates, so no date ties with another.
            addedDate: { url in url.lastPathComponent == "copied-recently.dmg" ? recently : addedLongAgo })

        var items: [String: ScanItem] = [:]
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        for await event in oldFiles.scan(context) {
            guard case .item(let item) = event else { continue }
            let url = try root.requireInside(#require(item.url))
            items[url.lastPathComponent] = item
        }

        // The file opened long ago changed yesterday, and the old file was copied yesterday: neither is old (D-130).
        #expect(Set(items.keys) == ["never-opened.dmg"])
        #expect(items.values.allSatisfy { $0.tier == .yourData && $0.method == .trash && $0.source == .oldFiles })
        #expect(items["never-opened.dmg"].map { String(localized: $0.reason) } == "Not modified in 12 months")
        #expect(!lookups.withLock { $0.contains("small.txt") })
    }

    @Test func theDefaultsAre12MonthsAnd50MBOLD001() {
        let oldFiles = OldFiles()
        #expect(oldFiles.periodMonths == 12)
        #expect(oldFiles.minimumSize == 50_000_000)
        #expect(oldFiles.lastOpenedReader?.minimumSize == 50_000_000)
        #expect(OldFiles.presetPeriodMonths == [3, 6, 12, 24])
        #expect(oldFiles.tiers == [.yourData])
        #expect(oldFiles.allowedRoots(home: root.url) == [root.url])
        #expect(LargeFiles().lastOpenedReader == nil)
    }
}
