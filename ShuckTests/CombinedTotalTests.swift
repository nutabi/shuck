import Foundation
import ShuckKit
import Testing

@testable import Shuck

/// The landing page's total counts each file once across sub-tools (FCL-007).
///
/// The scans are replaced by made-up events, so these tests never touch the file system.
@MainActor
struct CombinedTotalTests {
    let context = ScanContext(home: URL(filePath: "/StubHome", directoryHint: .isDirectory))
    let yearsAgo = Date.now.addingTimeInterval(-3 * 365 * 86_400)

    func file(_ path: String, size: Int64, modified: Date = .now, identity: FileIdentity? = nil) -> PersonalFile {
        PersonalFile(
            url: context.home.appending(path: path), identity: identity,
            snapshot: ItemSnapshot(kind: .file, allocatedSize: size), modified: modified)
    }

    func model(_ subTools: [any SubTool], files: [PersonalFile]) -> FileCleanupModel {
        FileCleanupModel(subTools: subTools, context: context) { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                continuation.finish()
            }
        }
    }

    @Test func aFileBothLargeAndOldCountsOnceFCL007() async throws {
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let oldFiles = OldFiles(minimumSize: 1_000)
        let bigAndOld = file("Movies/old.mov", size: 5_000, modified: yearsAgo)
        let model = model(
            [largeFiles, oldFiles],
            files: [bigAndOld, file("Movies/new.mov", size: 2_000), file("notes.txt", size: 10, modified: yearsAgo)])

        #expect(model.combinedTotal == nil)
        await model.scan(largeFiles)?.value

        guard case .scanned(let large) = model.state(of: largeFiles.id),
            case .scanned(let old) = model.state(of: oldFiles.id)
        else {
            Issue.record("Not scanned")
            return
        }
        #expect(large.reclaimableBytes == 7_000)
        #expect(old.reclaimableBytes == 5_000)
        #expect(
            model.combinedTotal == .init(reclaimableBytes: 7_000, scannedCount: 2, availableCount: 2),
            "The old movie is counted twice")

        // Once trashed, the file leaves both lists and the total (FCL-006).
        model.remove([bigAndOld.url])
        #expect(model.combinedTotal?.reclaimableBytes == 2_000)
    }

    @Test func twoPathsToOneFileCountOnceFCL007() async {
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let identity = FileIdentity(volume: 1, file: 42)
        let model = model(
            [largeFiles],
            files: [
                file("Movies/a.mov", size: 5_000, identity: identity),
                file("Backup/a.mov", size: 5_000, identity: identity),
            ])

        await model.scan(largeFiles)?.value

        // Both paths are listed, but trashing them frees the space of one file.
        #expect(model.personalFilesResults[largeFiles.id]?.rows.count == 2)
        guard case .scanned(let summary) = model.state(of: largeFiles.id) else {
            Issue.record("Not scanned")
            return
        }
        #expect(summary.reclaimableBytes == 5_000)
        #expect(model.combinedTotal?.reclaimableBytes == 5_000)
    }

    /// Other sub-tools never share a location with the personal files (FCL-005), so their estimates are added. Planned
    /// sub-tools cannot scan, so they do not count as missing from the total.
    @Test func theTotalAddsOtherSubToolsAndSaysHowManyScanned() async throws {
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let other = FixedSubTool(bytes: 3_000)
        let planned = try #require(ToolRegistry.standard.subTools.first { $0.info.availability != .available })
        let model = model([largeFiles, other, planned], files: [file("a.mov", size: 5_000)])

        await model.scan(other)?.value
        #expect(model.combinedTotal == .init(reclaimableBytes: 3_000, scannedCount: 1, availableCount: 2))

        await model.scan(largeFiles)?.value
        #expect(model.combinedTotal == .init(reclaimableBytes: 8_000, scannedCount: 2, availableCount: 2))
    }
}

/// A sub-tool outside the personal files whose scan finds one item of `bytes`.
private struct FixedSubTool: SubTool {
    let info = ToolInfo(
        id: ToolID(rawValue: "TSF"), name: "Fixed", summary: "Finds one item.", symbolName: "testtube.2",
        availability: .available)
    let tiers: Set<Tier> = [.rebuildable]
    let bytes: Int64

    func allowedRoots(home: URL) -> [URL] { [] }

    func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        let item = ScanItem(
            url: context.home.appending(path: "Library/Caches/stub"),
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: bytes), tier: .rebuildable, method: .delete,
            reason: "Stub", source: info.id)
        return AsyncStream { continuation in
            continuation.yield(.item(item))
            continuation.finish()
        }
    }
}
