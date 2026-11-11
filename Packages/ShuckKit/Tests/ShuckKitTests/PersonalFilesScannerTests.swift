import Foundation
import ShuckKit
import ShuckKitTestSupport
import Synchronization
import Testing

/// The personal-files scan that Large Files and Old Files share (FCL-006, FCL-008 to FCL-011, SAF-011, SAF-012,
/// SAF-014).
struct PersonalFilesScannerTests {
    let root: FixtureRoot

    init() throws {
        root = try FixtureRoot()
    }

    private func scanner(
        userExclusions: [URL] = [], batchSize: Int = 256,
        readValues: @escaping PersonalFilesScanner.ValueReader = EntryValues.read,
        report: @escaping PersonalFilesScanner.Report = PersonalFilesScanner.logFinished
    ) -> PersonalFilesScanner {
        PersonalFilesScanner(
            context: ScanContext(
                home: root.url, protection: root.pathGuardConfiguration(userExclusions: userExclusions)),
            batchSize: batchSize, readValues: readValues, report: report)
    }

    /// Runs a scan to the end. Items are keyed by their path inside the fixture root.
    private func scan(_ scanner: PersonalFilesScanner) async throws -> (
        items: [String: PersonalFile], notAccessible: [String], unreadable: [String]
    ) {
        var state = PersonalFilesState()
        for await event in scanner.scan() {
            state.apply(event)
        }
        for url in state.items.keys { try root.requireInside(url) }
        return (
            Dictionary(uniqueKeysWithValues: state.items.map { (relative($0.key), $0.value) }),
            state.notAccessible.map(relative).sorted(), state.unreadable.map(relative).sorted()
        )
    }

    private func relative(_ url: URL) -> String {
        String(url.path.dropFirst(root.url.path.count + 1))
    }

    // MARK: - Scope (FCL-008)

    @Test func theScopeLeavesOutLibraryHiddenItemsAppsAndExclusionsFCL008() async throws {
        try root.file("Documents/report.pdf", size: 1_000)
        try root.file("Downloads/a/b/c/deep.zip", size: 1_000)
        try root.file("Library/Caches/com.example/cache.db", size: 1_000)
        try root.file("Library/Preferences/com.example.plist", size: 10)
        try root.file(".cache/tool/blob", size: 1_000)
        try root.file(".zshrc", size: 10)
        try root.file("Applications/Tool.app/Contents/MacOS/Tool", size: 1_000)
        try root.file("Excluded/kept.mov", size: 1_000)
        // Hidden files below the top level are personal files.
        try root.file("Projects/app/.env", size: 10)

        let result = try await scan(scanner(userExclusions: [try root.url("Excluded")]))

        #expect(Set(result.items.keys) == ["Documents/report.pdf", "Downloads/a/b/c/deep.zip", "Projects/app/.env"])
        #expect(result.items.values.allSatisfy { $0.readOnly == nil })
    }

    @Test func exclusionsMatchWhateverTheirCaseAndUnicodeFormFCL008() async throws {
        try root.file("Excluded/kept.mov", size: 1_000)
        try root.file("Caf\u{E9}/menu.pdf", size: 1_000)
        try root.file("Documents/report.pdf", size: 1_000)

        // One exclusion differs in case. The other spells é as e and a combining accent, as a pasted path might.
        let result = try await scan(scanner(userExclusions: [try root.url("EXCLUDED"), try root.url("Cafe\u{301}")]))

        #expect(Set(result.items.keys) == ["Documents/report.pdf"])
    }

    @Test func eachDeviceBackupIsOneItemFCL008() async throws {
        try root.file("Library/Application Support/MobileSync/Backup/00008110-A/Manifest.db", size: 8_000)
        try root.file("Library/Application Support/MobileSync/Backup/00008110-A/3f/3f2a", size: 8_000)
        try root.file("Library/Application Support/AddressBook/AddressBook-v22.abcddb", size: 1_000)

        let result = try await scan(scanner())

        let backup = try #require(result.items["Library/Application Support/MobileSync/Backup/00008110-A"])
        #expect(result.items.count == 1)
        #expect(backup.snapshot.kind == .folder)
        #expect(backup.snapshot.allocatedSize >= 16_000)
        #expect(backup.readOnly == nil)
    }

    // MARK: - Packages and placeholders (FCL-009, FCL-010)

    @Test func aPackageIsOneItemWithItsTotalSizeFCL009() async throws {
        try root.file("Documents/Notes.rtfd/TXT.rtf", size: 4_000)
        try root.file("Documents/Notes.rtfd/image.png", size: 12_000)

        let result = try await scan(scanner())

        let package = try #require(result.items["Documents/Notes.rtfd"])
        #expect(result.items.count == 1)
        #expect(package.snapshot.kind == .folder)
        #expect(package.snapshot.allocatedSize >= 16_000)
    }

    @Test func iCloudPlaceholdersAreLeftOutFCL010() async throws {
        try root.file("Documents/local.pdf", size: 1_000)
        try root.file("Documents/cloud.pdf", size: 1_000)

        let result = try await scan(
            scanner { url in
                var values = EntryValues.read(url)
                if url.lastPathComponent == "cloud.pdf" { values?.isPlaceholder = true }
                return values
            })

        #expect(Set(result.items.keys) == ["Documents/local.pdf"])
    }

    /// An evicted package or folder is skipped as a whole: nothing measures it or reads inside it (FCL-010, D-129).
    @Test func placeholderPackagesAndFoldersAreLeftOutFCL010() async throws {
        try root.file("Documents/Cloud.rtfd/TXT.rtf", size: 1_000)
        try root.file("Documents/Cloud Folder/inside.pdf", size: 1_000)
        try root.file("Pictures/Cloud.photoslibrary/database", size: 1_000)
        try root.file("go/pkg/mod/cache/blob", size: 1_000)
        try root.file("Documents/local.pdf", size: 1_000)
        let evicted: Set<String> = ["Cloud.rtfd", "Cloud Folder", "Cloud.photoslibrary", "mod"]
        let read = Mutex<[String]>([])

        let result = try await scan(
            scanner { url in
                read.withLock { $0.append(url.lastPathComponent) }
                var values = EntryValues.read(url)
                if evicted.contains(url.lastPathComponent) { values?.isPlaceholder = true }
                return values
            })

        #expect(Set(result.items.keys) == ["Documents/local.pdf"])
        // The walk never looked inside the evicted folders.
        #expect(read.withLock { !$0.contains("inside.pdf") && !$0.contains("TXT.rtf") && !$0.contains("cache") })
    }

    /// A downloaded file that iCloud keeps stays listed and is marked synced (FCL-010, FCL-012, D-129).
    @Test func downloadedSyncedFilesAreListedAndMarkedFCL010() async throws {
        try root.file("Documents/synced.pdf", size: 1_000)
        try root.file("Documents/local.pdf", size: 1_000)
        try root.file("Documents/Synced.rtfd/TXT.rtf", size: 1_000)

        let result = try await scan(
            scanner { url in
                var values = EntryValues.read(url)
                if url.lastPathComponent.hasPrefix("Synced") || url.lastPathComponent.hasPrefix("synced") {
                    values?.isSynced = true
                }
                return values
            })

        #expect(try #require(result.items["Documents/synced.pdf"]).isSynced)
        #expect(try #require(result.items["Documents/Synced.rtfd"]).isSynced)
        #expect(try #require(result.items["Documents/local.pdf"]).isSynced == false)
    }

    @Test func entryValuesReadAFileFromDisk() throws {
        let file = try root.file("Documents/a.bin", size: 8_000, modified: Date(timeIntervalSince1970: 1_000_000))
        let values = try #require(EntryValues.read(file))
        #expect(values.isRegularFile && !values.isDirectory && !values.isPlaceholder && !values.isSynced)
        #expect(values.allocatedSize >= 8_000)
        #expect(values.modified == Date(timeIntervalSince1970: 1_000_000))
        #expect(EntryValues.read(try root.url("Documents/missing")) == nil)
    }

    /// Each item carries its file identity, so totals can count a hard-linked file once (FCL-007).
    @Test func hardLinksAreTwoItemsWithOneIdentityFCL007() async throws {
        try root.file("Movies/a.mov", size: 4_000)
        try root.hardLink("Backup/a.mov", to: "Movies/a.mov")
        try root.file("Documents/Notes.rtfd/TXT.rtf", size: 4_000)

        let result = try await scan(scanner())

        let original = try #require(result.items["Movies/a.mov"]?.identity)
        #expect(result.items["Backup/a.mov"]?.identity == original)
        let package = try #require(result.items["Documents/Notes.rtfd"]?.identity)
        #expect(package != original)
        #expect(ReclaimableTotal(result.items.values).count == 2)
    }

    // MARK: - Read-only items (FCL-011, section 8.4)

    @Test func aToolOwnedStoreIsOneReadOnlyItemPointingAtItsSubToolFCL011() async throws {
        try root.file("go/pkg/mod/github.com/example/lib@v1.0.0/lib.go", size: 4_000)
        try root.file("go/pkg/mod/cache/download/lib.zip", size: 4_000)
        try root.file("go/bin/tool", size: 1_000)

        let result = try await scan(scanner())

        let store = try #require(result.items["go/pkg/mod"])
        #expect(store.readOnly == .managedBy(.developerJunk))
        #expect(store.snapshot.allocatedSize >= 8_000)
        #expect(store.scanItem(source: .largeFiles, reason: "Large") == nil)
        #expect(Set(result.items.keys) == ["go/pkg/mod", "go/bin/tool"])
    }

    /// SET-001, FCL-008: exclusions hide even stores normally shown read-only for another sub-tool (FCL-011).
    @Test(arguments: ["go/pkg/mod", "go/pkg", "GO/PKG/MOD"])
    func anExcludedToolOwnedStoreIsNotListedSET001(exclusion: String) async throws {
        try root.file("go/pkg/mod/github.com/example/lib@v1.0.0/lib.go", size: 4_000)
        try root.file("go/bin/tool", size: 1_000)
        try root.file("Documents/notes.txt", size: 10)

        let result = try await scan(scanner(userExclusions: [try root.url(exclusion)]))

        #expect(Set(result.items.keys) == ["go/bin/tool", "Documents/notes.txt"])
        #expect(result.notAccessible.isEmpty)
        #expect(result.unreadable.isEmpty)
    }

    @Test func protectedLibrariesAreListedReadOnly() async throws {
        try root.file("Pictures/Photos Library.photoslibrary/database/Photos.sqlite", size: 8_000)
        try root.file("Music/Music/Media/song.m4a", size: 8_000)
        try root.file("Pictures/holiday.jpg", size: 1_000)

        let result = try await scan(scanner())

        #expect(result.items["Pictures/Photos Library.photoslibrary"]?.readOnly == .protected)
        #expect(result.items["Music/Music"]?.readOnly == .protected)
        #expect(result.items["Pictures/holiday.jpg"]?.readOnly == nil)
        #expect(result.items.count == 3)
    }

    /// The path guard ignores case when it compares protected names (D-79), so the scan does too: otherwise it would
    /// list the files inside as selectable, and the guard would then refuse the plan.
    @Test func aProtectedNameInAnotherCaseIsOneReadOnlyItemSAF007() async throws {
        try root.file("Backups/backups.BACKUPDB/Mac/2026-11-01/report.pdf", size: 4_000)
        try root.file("Backups/notes.txt", size: 10)

        let result = try await scan(scanner())

        let backup = try #require(result.items["Backups/backups.BACKUPDB"])
        #expect(backup.readOnly == .protected)
        #expect(backup.snapshot.allocatedSize >= 4_000)
        #expect(Set(result.items.keys) == ["Backups/backups.BACKUPDB", "Backups/notes.txt"])
    }

    @Test func aWritableItemBecomesAYourDataTrashItem() throws {
        let file = PersonalFile(
            url: try root.url("Movies/clip.mov"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 10), modified: nil)
        let item = try #require(file.scanItem(source: .oldFiles, reason: "Old"))
        #expect(item.tier == .yourData && item.method == .trash && item.source == .oldFiles)
    }

    // MARK: - Errors, symlinks, cancelling (SAF-012, SAF-014)

    @Test func anUnreadableFolderIsReportedAndTheScanGoesOnSAF012() async throws {
        try root.file("Documents/Locked/secret.txt", size: 10)
        try root.folder("Documents/Locked/Inner")
        try root.file("Documents/open.txt", size: 10)
        let locked = try root.url("Documents/Locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let result = try await scan(scanner())

        #expect(result.notAccessible == ["Documents/Locked"])
        #expect(result.unreadable.isEmpty)
        #expect(Set(result.items.keys) == ["Documents/open.txt"])
    }

    @Test func aFolderThatFailsToListForAnotherReasonIsReportedSAF011() async throws {
        // A file that reads as a folder, as if a folder were replaced by a file during the scan. Listing it fails with
        // "not a directory", not with a permission error.
        try root.file("Documents/Replaced", size: 10)
        try root.file("Documents/open.txt", size: 10)

        let result = try await scan(
            scanner { url in
                var values = EntryValues.read(url)
                if url.lastPathComponent == "Replaced" {
                    values?.isDirectory = true
                    values?.isRegularFile = false
                }
                return values
            })

        #expect(result.unreadable == ["Documents/Replaced"])
        #expect(result.notAccessible.isEmpty)
        #expect(Set(result.items.keys) == ["Documents/open.txt"])
    }

    @Test func symlinksAreNeverFollowed() async throws {
        try root.file("Documents/real.txt", size: 10)
        try root.symlink("Documents/inside", to: try root.url("Documents/real.txt"))
        try root.symlink("Documents/outside", to: URL(filePath: "/usr/share"))

        let result = try await scan(scanner())

        #expect(Set(result.items.keys) == ["Documents/real.txt"])
    }

    @Test func cancellingTheReadingTaskStopsTheScanSAF014() async throws {
        for index in 0..<40 { try root.file("Pile/\(index).bin", size: 10) }
        let reads = Mutex(0)
        // The tenth entry waits until the scan is cancelled, so the test knows exactly where the scan stands.
        let scanner = scanner(batchSize: 1) { url in
            if reads.withLock({
                $0 += 1
                return $0
            }) == 10 {
                let deadline = Date.now.addingTimeInterval(5)
                while !Task.isCancelled, Date.now < deadline { Thread.sleep(forTimeInterval: 0.001) }
            }
            return EntryValues.read(url)
        }

        let reader = Task {
            var count = 0
            for await event in scanner.scan() {
                if case .files(let files) = event { count += files.count }
            }
            return count
        }
        while reads.withLock({ $0 }) < 10 { try await Task.sleep(for: .milliseconds(5)) }
        reader.cancel()
        let received = await reader.value
        try await Task.sleep(for: .milliseconds(200))

        #expect(received < 40)
        #expect(reads.withLock { $0 } == 10)
    }

    // MARK: - Performance baseline (NFR-PERF-002)

    @Test func aFinishedScanReportsHowManyEntriesItLookedAtNFRPERF002() async throws {
        try root.file("Documents/report.pdf", size: 10)
        try root.file("Documents/Notes.rtfd/TXT.rtf", size: 10)
        try root.file("Downloads/a/b.zip", size: 10)
        let reports = Mutex<[(entries: Int, duration: Duration)]>([])

        _ = try await scan(
            scanner(report: { entries, duration in reports.withLock { $0.append((entries, duration)) } }))

        // Documents, report.pdf, Notes.rtfd, Downloads, a and b.zip. The package counts once.
        let report = try #require(reports.withLock { $0.count == 1 ? $0.first : nil })
        #expect(report.entries == 6)
        #expect(report.duration > .zero)
    }

    @Test func foldersReadInParallelSendEveryFileOnceInFullBatchesNFRPERF002() async throws {
        for folder in 0..<30 {
            for subfolder in 0..<3 {
                try root.file("Projects/p\(folder)/s\(subfolder)/a.txt", size: 10)
                try root.file("Projects/p\(folder)/s\(subfolder)/b.txt", size: 10)
            }
        }
        let reports = Mutex<[Int]>([])
        var batches: [[PersonalFile]] = []

        for await event in scanner(batchSize: 4, report: { entries, _ in reports.withLock { $0.append(entries) } })
            .scan()
        {
            if case .files(let files) = event { batches.append(files) }
        }

        let paths = batches.joined().map { relative($0.url) }
        #expect(paths.count == 180)
        #expect(Set(paths).count == 180)
        // Only the last batch may be short: every task fills the same batch.
        #expect(batches.dropLast().allSatisfy { $0.count == 4 })
        // Projects, 30 folders, 90 subfolders and 180 files.
        #expect(reports.withLock { $0 } == [301])
    }

    // MARK: - Shared state (FCL-006)

    @Test func theStateKeepsOneEntryPerPathAndForgetsRemovedItemsFCL006() throws {
        let file = PersonalFile(
            url: try root.url("Movies/clip.mov"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 10), modified: nil)
        var state = PersonalFilesState()
        state.apply(.files([file, file]))
        state.apply(.notAccessible(try root.url("Locked")))
        #expect(state.items.count == 1)
        #expect(state.notAccessible.count == 1)

        state.remove([file.url])
        #expect(state.items.isEmpty)
    }
}
