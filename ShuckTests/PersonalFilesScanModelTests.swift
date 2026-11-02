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

    func file(_ path: String, size: Int64, readOnly: ReadOnlyReason? = nil) -> PersonalFile {
        PersonalFile(
            url: context.home.appending(path: path), snapshot: ItemSnapshot(kind: .file, allocatedSize: size),
            modified: nil, readOnly: readOnly)
    }

    @Test func oneScanFillsEveryPersonalFilesListFCL006() async throws {
        let scans = Mutex(0)
        let events: [PersonalFilesEvent] = [
            .files([file("Movies/big.mov", size: 5_000), file("Documents/small.txt", size: 10)]),
            .notAccessible(context.home.appending(path: "Locked")),
            .files([file("go/pkg/mod", size: 9_000, readOnly: .managedBy(.developerJunk))]),
        ]
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let everything = StubPersonalSubTool()
        let model = FileCleanupModel(subTools: [largeFiles, everything], context: context) { _ in
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
        #expect(model.results[largeFiles.id]?.rows.map(\.name) == ["mod", "big.mov"])
        #expect(Set(model.results[everything.id]?.rows.map(\.name) ?? []) == ["mod", "big.mov", "small.txt"])
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
    }

    @Test func filesNoSubToolListsAreNotKept() async {
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let files = [file("a.mov", size: 5_000), file("b.txt", size: 10)]
        let model = FileCleanupModel(subTools: [largeFiles], context: context) { _ in
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
        let model = FileCleanupModel(subTools: [largeFiles, everything], context: context) { _ in
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
        #expect(model.state(of: largeFiles.id) == .notScanned)
        #expect(model.results[largeFiles.id]?.rows.isEmpty == true)
    }

    @Test func largeFilesListsTheLargestFirstLRG002() {
        let model = FileCleanupModel(subTools: [LargeFiles()], context: context)
        #expect(model.results[.largeFiles]?.sortOrder == [KeyPathComparator(\ResultRow.size, order: .reverse)])
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
