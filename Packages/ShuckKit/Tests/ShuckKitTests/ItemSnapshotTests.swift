import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// What a snapshot says about an item, and how the two readers of `lstat` errors sort them (SAF-012, R-10, M3-T01).
struct ItemSnapshotTests {
    let root: FixtureRoot

    init() throws {
        root = try FixtureRoot()
    }

    // MARK: - An incomplete size (R-10, SAF-012)

    @Test func aFolderWithAnUnreadableSubfolderIsMeasuredPartlyAndMarkedIncompleteSAF012() throws {
        let folder = try root.folder("Library/Caches/App")
        try root.file("Library/Caches/App/open.bin", size: 100_000)
        try root.folder("Library/Caches/App/Locked", permissions: 0o000)

        let snapshot = try #require(ItemSnapshot.read(folder))

        #expect(snapshot.kind == .folder)
        #expect(!snapshot.isComplete)
        // What could be read is still counted: the readable file, so the size is a lower bound, not zero.
        #expect(snapshot.allocatedSize >= 100_000)
        #expect(ItemSnapshot.check(folder) == .found(snapshot))
    }

    @Test func aFullyReadableFolderIsCompleteSAF012() throws {
        let folder = try root.folder("Library/Caches/App")
        try root.file("Library/Caches/App/open.bin", size: 100_000)
        try root.folder("Library/Caches/App/Inner")
        try root.file("Library/Caches/App/Inner/deep.bin", size: 50_000)

        let snapshot = try #require(ItemSnapshot.read(folder))

        #expect(snapshot.isComplete)
        #expect(snapshot.allocatedSize >= 150_000)
    }

    @Test func aFileAndASymlinkAreAlwaysCompleteSAF012() throws {
        let file = try root.file("Downloads/clip.mov", size: 4_096)
        let link = try root.url("Downloads/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        #expect(try #require(ItemSnapshot.read(file)).isComplete)
        let linkSnapshot = try #require(ItemSnapshot.read(link))
        #expect(linkSnapshot.kind == .symlink && linkSnapshot.isComplete)
    }

    /// Execution compares kind and size only (SAF-008, D-48): an incomplete size does not change what matches.
    @Test func matchesIgnoresWhetherTheSizeIsCompleteSAF012() {
        let planned = ItemSnapshot(kind: .folder, allocatedSize: 1_000_000)
        let incomplete = ItemSnapshot(kind: .folder, allocatedSize: 1_000_000, isComplete: false)
        let smaller = ItemSnapshot(kind: .folder, allocatedSize: 100_000, isComplete: false)

        #expect(planned.matches(incomplete))
        #expect(incomplete.matches(planned))
        #expect(!planned.matches(smaller))
        #expect(!ItemSnapshot(kind: .file, allocatedSize: 1_000_000).matches(incomplete))
    }

    // MARK: - One classifier for lstat errors (SAF-012)

    @Test func theClassifierSortsEachErrnoSAF012() {
        #expect(LstatFailure(errno: ENOENT) == .missing)
        #expect(LstatFailure(errno: ENOTDIR) == .missing)
        #expect(LstatFailure(errno: EPERM) == .notAccessible)
        #expect(LstatFailure(errno: EACCES) == .notAccessible)
        #expect(LstatFailure(errno: ENAMETOOLONG) == .other)
        #expect(LstatFailure(errno: ELOOP) == .other)
        #expect(LstatFailure(errno: EIO) == .other)
    }

    /// Re-validation: a permission error is not accessible; every other error, including an unusual one, is missing.
    @Test func reValidationKeepsItsOutcomeForEachErrorClassSAF012() throws {
        let locked = try root.folder("Library/Caches/Locked", permissions: 0o000)
        let file = try root.file("Downloads/clip.mov", size: 4_096)
        let tooLong = root.url.appending(path: String(repeating: "a", count: 300))

        // EACCES
        #expect(ItemSnapshot.check(locked.appending(path: "inside.db")) == .notAccessible)
        // ENOENT
        #expect(ItemSnapshot.check(root.url.appending(path: "Downloads/gone.mov")) == .missing)
        // ENOTDIR
        #expect(ItemSnapshot.check(file.appending(path: "inside")) == .missing)
        // ENAMETOOLONG, an error that is neither class
        #expect(ItemSnapshot.check(tooLong) == .missing)
    }

    /// Restore's check of the Trash: only a missing path means the Trash was emptied; every other error means Shuck
    /// cannot tell.
    @Test func restorabilityKeepsItsOutcomeForEachErrorClassSAF012() async throws {
        let locked = try root.folder(".Trash/Locked", permissions: 0o000)
        let file = try root.file(".Trash/clip.mov", size: 100)
        let tooLong = root.url.appending(path: String(repeating: "a", count: 300))
        let cases: [(URL, Restorability)] = [
            (locked.appending(path: "inside.db"), .notAccessible),  // EACCES
            (root.url.appending(path: ".Trash/gone.mov"), .trashEmptied),  // ENOENT
            (file.appending(path: "inside"), .trashEmptied),  // ENOTDIR
            (tooLong, .notAccessible),  // ENAMETOOLONG, an error that is neither class
        ]

        let folder = root.historyFolder
        let log = try HistoryLog(folder: folder)
        let run = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_793_577_600)
        for (index, (trashed, _)) in cases.enumerated() {
            let path = try root.url("Movies/item\(index).mov").path
            try await log.append(
                .result(
                    run: run, tool: .largeFiles, operation: .trash, path: path, tier: .yourData, status: .ok,
                    trashedPath: trashed.path, identity: nil, bytes: 100, timestamp: timestamp))
        }

        let entries = try HistoryLog.read(folder: folder).entries()
        #expect(entries.map(\.restorability.kindName) == cases.map { $0.1.kindName })
    }
}

extension Restorability {
    /// The case without its payload, so a test compares outcomes.
    fileprivate var kindName: String {
        switch self {
        case .restorable: "restorable"
        case .trashEmptied: "trashEmptied"
        case .notAccessible: "notAccessible"
        case .unknownLocation: "unknownLocation"
        case .restored: "restored"
        case .permanent: "permanent"
        case .reversedByOppositeAction: "reversedByOppositeAction"
        }
    }
}
