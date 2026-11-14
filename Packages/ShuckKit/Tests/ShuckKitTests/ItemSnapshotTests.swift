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

    @Test func onlyAFolderWithAnUnreadableSubfolderIsMarkedIncompleteSAF012() throws {
        // A fully readable folder, a file and a link are complete.
        let readable = try root.folder("Library/Caches/Readable")
        try root.file("Library/Caches/Readable/open.bin", size: 100_000)
        try root.file("Library/Caches/Readable/Inner/deep.bin", size: 50_000)
        let file = try root.file("Downloads/clip.mov", size: 4_096)
        let link = try root.symlink("Downloads/link", to: file)
        let readableSnapshot = try #require(ItemSnapshot.read(readable))
        #expect(readableSnapshot.isComplete && readableSnapshot.allocatedSize >= 150_000)
        #expect(try #require(ItemSnapshot.read(file)).isComplete)
        let linkSnapshot = try #require(ItemSnapshot.read(link))
        #expect(linkSnapshot.kind == .symlink && linkSnapshot.isComplete)

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

    /// Both readers of `lstat` errors keep their outcome for each class. Re-validation: a permission error is not
    /// accessible; every other error, including an unusual one, is missing. Restore's check of the Trash: only a
    /// missing path means the Trash was emptied; every other error means Shuck cannot tell.
    @Test func eachLstatErrorIsSortedAndKeepsItsOutcomeInBothReadersSAF008SAF012() async throws {
        let errnos: [(Int32, LstatFailure)] = [
            (ENOENT, .missing), (ENOTDIR, .missing), (EPERM, .notAccessible), (EACCES, .notAccessible),
            (ENAMETOOLONG, .other), (ELOOP, .other), (EIO, .other),
        ]
        for (code, failure) in errnos { #expect(LstatFailure(errno: code) == failure, "errno \(code)") }

        let locked = try root.folder(".Trash/Locked", permissions: 0o000)
        let file = try root.file(".Trash/clip.mov", size: 100)
        let tooLong = root.url.appending(path: String(repeating: "a", count: 300))
        let cases: [(path: URL, revalidation: ItemSnapshot.Check, restorability: Restorability)] = [
            (locked.appending(path: "inside.db"), .notAccessible, .notAccessible),  // EACCES
            (root.url.appending(path: ".Trash/gone.mov"), .missing, .trashEmptied),  // ENOENT
            (file.appending(path: "inside"), .missing, .trashEmptied),  // ENOTDIR
            (tooLong, .missing, .notAccessible),  // ENAMETOOLONG, an error that is neither class
        ]
        #expect(cases.map { ItemSnapshot.check($0.path) } == cases.map(\.revalidation))
        #expect(ItemSnapshot.check(locked) == .notAccessible)
        #expect(ItemSnapshot.check(file) == ItemSnapshot.read(file).map(ItemSnapshot.Check.found))

        let folder = root.historyFolder
        let log = try HistoryLog(folder: folder)
        let run = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_793_577_600)
        for (index, item) in cases.enumerated() {
            let path = try root.url("Movies/item\(index).mov").path
            try await log.append(
                .result(
                    run: run, tool: .largeFiles, operation: .trash, path: path, tier: .yourData, status: .ok,
                    trashedPath: item.path.path, identity: nil, bytes: 100, timestamp: timestamp))
        }

        let entries = try HistoryLog.read(folder: folder).entries()
        #expect(entries.map(\.restorability.kindName) == cases.map(\.restorability.kindName))
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
