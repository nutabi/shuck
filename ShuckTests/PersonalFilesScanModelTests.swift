import Foundation
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// Large Files and Old Files share one personal-files scan; each shows its own list of it (FCL-006, FCL-012).
///
/// The scan is replaced by made-up events, so these tests never touch the file system.
@MainActor
struct PersonalFilesScanModelTests {
    let context = ScanContext(home: URL(filePath: "/StubHome", directoryHint: .isDirectory))

    func file(
        _ path: String, size: Int64, modified: Date? = nil, lastOpened: LastOpened? = nil,
        readOnly: ReadOnlyReason? = nil
    ) -> PersonalFile {
        PersonalFile(
            url: context.home.appending(path: path), snapshot: ItemSnapshot(kind: .file, allocatedSize: size),
            modified: modified, lastOpened: lastOpened, readOnly: readOnly)
    }

    @Test func oneScanFillsEveryPersonalFilesListFCL006() async throws {
        let scans = Mutex(0)
        let events: [PersonalFilesEvent] = [
            .files([file("Movies/big.mov", size: 5_000), file("Documents/small.txt", size: 10)]),
            .notAccessible(context.home.appending(path: "Locked")),
            .unreadable(context.home.appending(path: "Broken")),
            .files([file("go/pkg/mod", size: 9_000, readOnly: .managedBy(.developerJunk))]),
        ]
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let everything = StubPersonalSubTool()
        let model = FileCleanupModel(subTools: [largeFiles, everything], context: context) { _, _ in
            scans.withLock { $0 += 1 }
            return AsyncStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }

        await model.scan(largeFiles)?.value

        #expect(scans.withLock { $0 } == 1)
        #expect(model.personalFilesResults[largeFiles.id]?.rows.map(\.name) == ["mod", "big.mov"])
        #expect(
            Set(model.personalFilesResults[everything.id]?.rows.map(\.name) ?? []) == ["mod", "big.mov", "small.txt"])
        for id in [largeFiles.id, everything.id] {
            guard case .scanned = model.state(of: id) else {
                Issue.record("\(id.rawValue) not scanned: \(model.state(of: id))")
                continue
            }
        }
        // The reclaimable estimate leaves out the read-only Go module cache (FCL-011).
        guard case .scanned(let summary) = model.state(of: largeFiles.id) else { return }
        #expect(summary.itemCount == 1)
        #expect(summary.reclaimableBytes == 5_000)
        #expect(summary.notAccessibleCount == 1)
        #expect(summary.unreadableCount == 1)
    }

    @Test func filesNoSubToolListsAreNotKept() async {
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let files = [file("a.mov", size: 5_000), file("b.txt", size: 10)]
        let model = FileCleanupModel(subTools: [largeFiles], context: context) { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                continuation.finish()
            }
        }

        await model.scan(largeFiles)?.value

        #expect(model.personalFiles.items.keys.map(\.lastPathComponent) == ["a.mov"])
    }

    @Test func aPersonalFilesScanMarksEveryPersonalFilesSubToolAndCancellingEmptiesTheLists() async {
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let everything = StubPersonalSubTool()
        let files = [file("a.mov", size: 5_000)]
        let model = FileCleanupModel(subTools: [largeFiles, everything], context: context) { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                // Never finishes, like a scan of a large home folder.
            }
        }

        let scan = model.scan(largeFiles)
        #expect(model.state(of: everything.id) == .scanning)
        #expect(model.scan(everything) == nil)

        scan?.cancel()
        await scan?.value
        #expect(model.state(of: largeFiles.id) == .stopped)
        #expect(model.personalFilesResults[largeFiles.id]?.rows.isEmpty == true)
    }

    /// Stop on either page stops the scan both share (FCL-006, SAF-014).
    @Test func stoppingOnePersonalFilesSubToolStopsTheSharedScanSAF014() async {
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let oldFiles = OldFiles(minimumSize: 1_000) { _ in nil }
        let files = [file("a.mov", size: 5_000)]
        let model = FileCleanupModel(subTools: [largeFiles, oldFiles], context: context) { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                // Never finishes, like a scan of a large home folder.
            }
        }

        let scan = model.scan(largeFiles)
        model.cancelScan(oldFiles)
        await scan?.value

        for id in [largeFiles.id, oldFiles.id] {
            #expect(model.state(of: id) == .stopped)
            #expect(model.results(of: id)?.isEmpty == true)
        }
        #expect(model.canScan(largeFiles) && model.canScan(oldFiles))
        // Opening the other page doesn't start the shared scan again (D-91).
        #expect(model.scanIfNotScanned(oldFiles) == nil)
    }

    @Test func largeFilesListsTheLargestFirstLRG002() {
        let model = FileCleanupModel(subTools: [LargeFiles()], context: context)
        #expect(
            model.personalFilesResults[.largeFiles]?.sortOrder == [KeyPathComparator(\ResultRow.size, order: .reverse)])
        #expect(model.personalFilesResults[.largeFiles]?.dateColumn == .modified)
    }

    @Test func oldFilesListsTheLongestUnopenedFirstByLastOpenedDateOLD003() async {
        let yearsAgo = Date.now.addingTimeInterval(-3 * 365 * 86_400)
        let lastYear = Date.now.addingTimeInterval(-400 * 86_400)
        let files = [
            file("Movies/older.mov", size: 5_000, lastOpened: LastOpened(date: lastYear, source: .lastUsed)),
            file("Movies/oldest.mov", size: 5_000, lastOpened: LastOpened(date: yearsAgo, source: .modified)),
            file("Movies/recent.mov", size: 5_000, lastOpened: LastOpened(date: .now, source: .added)),
        ]
        let oldFiles = OldFiles(minimumSize: 1_000)
        let model = FileCleanupModel(subTools: [oldFiles], context: context) { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                continuation.finish()
            }
        }

        await model.scan(oldFiles)?.value

        let results = model.personalFilesResults[.oldFiles]
        #expect(results?.sortOrder == [KeyPathComparator(\ResultRow.sortDate)])
        #expect(results?.dateColumn == .lastOpened)
        #expect(results?.rows.map(\.name) == ["oldest.mov", "older.mov"])
        #expect(results?.rows.map(\.dateSource) == [.modified, nil])
    }

    /// Only files of at least Old Files' minimum size need a Spotlight lookup (OLD-002, D-59).
    @Test func theSharedScanLooksUpLastOpenedDatesWithOldFilesMinimumSizeOLD002() async {
        let minimums = Mutex<[Int64?]>([])
        let scan: FileCleanupModel.PersonalFilesScan = { _, reader in
            minimums.withLock { $0.append(reader?.minimumSize) }
            return AsyncStream { $0.finish() }
        }
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let withOldFiles = FileCleanupModel(
            subTools: [largeFiles, OldFiles(minimumSize: 500)], context: context, personalFilesScan: scan)
        let largeFilesOnly = FileCleanupModel(subTools: [largeFiles], context: context, personalFilesScan: scan)

        await withOldFiles.scan(largeFiles)?.value
        await largeFilesOnly.scan(largeFiles)?.value

        #expect(minimums.withLock { $0 } == [500, nil])
    }
}

/// A personal-files sub-tool that lists every file.
private struct StubPersonalSubTool: PersonalFilesSubTool {
    let info = ToolInfo(
        id: ToolID(rawValue: "TSP"), name: "Everything", summary: "Lists every personal file.", symbolName: "doc",
        availability: .available)

    func includes(_ file: PersonalFile) -> Bool { true }
    func reason(for file: PersonalFile) -> LocalizedStringResource { "Stub" }
}
