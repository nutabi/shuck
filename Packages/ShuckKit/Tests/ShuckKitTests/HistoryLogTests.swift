import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The history log writer and reader (PRD section 8.5, SAF-005, HIS-001, NFR-SEC-005).
struct HistoryLogTests {
    let root: FixtureRoot
    let folder: URL
    let run = UUID()
    /// A whole second, so the timestamp survives the round trip through milliseconds exactly.
    let timestamp = Date(timeIntervalSince1970: 1_793_577_600)

    init() throws {
        root = try FixtureRoot()
        folder = root.historyFolder
    }

    private var intent: HistoryRecord {
        .intent(
            run: run, tool: .largeFiles, operation: .trash, path: "/Users/me/Movies/clip.mov", tier: .yourData,
            bytes: 4096, timestamp: timestamp)
    }

    private var result: HistoryRecord {
        .result(
            run: run, tool: .largeFiles, operation: .trash, path: "/Users/me/Movies/clip.mov", tier: .yourData,
            status: .ok, trashedPath: "/Users/me/.Trash/clip.mov", bytes: 4096, detail: "Moved to the Trash",
            timestamp: timestamp)
    }

    private func logLines() throws -> [[String: Any]] {
        let text = try String(contentsOf: folder.appending(path: HistoryLog.fileName), encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
    }

    private func appendRaw(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: folder.appending(path: HistoryLog.fileName))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func mode(of url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }

    // MARK: - Format

    @Test func recordsUseTheFieldsOfSection85HIS001() async throws {
        let log = try HistoryLog(folder: folder)
        try await log.append(intent)
        try await log.append(result)

        let lines = try logLines()
        try #require(lines.count == 2)
        #expect(Set(lines[0].keys) == ["v", "ts", "run", "tool", "phase", "op", "path", "bytes", "tier"])
        #expect(
            Set(lines[1].keys)
                == [
                    "v", "ts", "run", "tool", "phase", "op", "path", "trashedPath", "bytes", "tier", "status", "detail",
                ]
        )
        #expect(lines[0]["v"] as? Int == 1)
        #expect(lines[0]["ts"] as? String == "2026-11-02T00:00:00.000Z")
        #expect(lines[0]["run"] as? String == run.uuidString)
        #expect(lines[0]["tool"] as? String == "LRG")
        #expect(lines[0]["phase"] as? String == "intent")
        #expect(lines[0]["op"] as? String == "trash")
        #expect(lines[0]["tier"] as? String == "yourData")
        #expect(lines[1]["status"] as? String == "ok")
        #expect(lines[1]["trashedPath"] as? String == "/Users/me/.Trash/clip.mov")
    }

    @Test func recordsRoundTripThroughTheLogSAF005() async throws {
        let log = try HistoryLog(folder: folder)
        try await log.append(intent)
        try await log.append(result)

        let contents = try HistoryLog.read(folder: folder)
        #expect(contents.records == [intent, result])
        #expect(contents.unreadableLines.isEmpty)
    }

    @Test func theTrashedItemsIdentityRoundTripsAndRecordsWithoutItStillReadSAF005() async throws {
        let identity = FileIdentity(volume: 16_777_232, file: 9_876_543)
        let withIdentity = HistoryRecord.result(
            run: run, tool: .largeFiles, operation: .trash, path: "/Users/me/Movies/clip.mov", tier: .yourData,
            status: .ok, trashedPath: "/Users/me/.Trash/clip.mov", identity: identity, bytes: 4096,
            timestamp: timestamp)
        let log = try HistoryLog(folder: folder)
        try await log.append(withIdentity)
        // The same record as Shuck 0.1.0 wrote it, without the identity.
        try appendRaw(
            #"{"bytes":4096,"detail":"Moved to the Trash","op":"trash","path":"/Users/me/Movies/clip.mov","#
                + #""phase":"result","run":"\#(run.uuidString)","status":"ok","tier":"yourData","tool":"LRG","#
                + #""trashedPath":"/Users/me/.Trash/clip.mov","ts":"2026-11-02T00:00:00.000Z","v":1}"# + "\n")

        let lines = try logLines()
        #expect(lines[0]["identity"] as? [String: Int] == ["volume": 16_777_232, "file": 9_876_543])
        let contents = try HistoryLog.read(folder: folder)
        #expect(contents.records == [withIdentity, result])
        #expect(contents.records.map(\.identity) == [identity, nil])
        #expect(contents.unreadableLines.isEmpty)
    }

    // MARK: - Writing

    @Test func eachRecordIsOnDiskWhenAppendReturnsHIS001() async throws {
        let log = try HistoryLog(folder: folder)
        try await log.append(intent)
        // The writer is still open: the record must already be readable by someone else.
        #expect(try HistoryLog.read(folder: folder).records == [intent])
        try await log.append(result)
        #expect(try HistoryLog.read(folder: folder).records == [intent, result])
    }

    @Test func reopeningTheLogAppendsHIS001() async throws {
        do {
            let first = try HistoryLog(folder: folder)
            try await first.append(intent)
        }
        let second = try HistoryLog(folder: folder)
        try await second.append(result)
        #expect(try HistoryLog.read(folder: folder).records == [intent, result])
    }

    @Test func aFullFlushKeepsEveryRecordAndTheLogStaysOpenHIS001() async throws {
        let log = try HistoryLog(folder: folder)
        try await log.append(intent)
        try await log.flushFully()
        try await log.append(result)
        try await log.flushFully()
        #expect(try HistoryLog.read(folder: folder).records == [intent, result])
    }

    @Test func aLineCutShortByACrashIsReportedAndSkippedHIS001() async throws {
        do {
            let log = try HistoryLog(folder: folder)
            try await log.append(intent)
        }
        try appendRaw(#"{"v":1,"ts":"2026-11-02T00:00:"#)

        let afterCrash = try HistoryLog.read(folder: folder)
        #expect(afterCrash.records == [intent])
        #expect(afterCrash.unreadableLines == [2])

        let log = try HistoryLog(folder: folder)
        try await log.append(result)
        let contents = try HistoryLog.read(folder: folder)
        #expect(contents.records == [intent, result])
        #expect(contents.unreadableLines == [2])
    }

    @Test func linesFromANewerSchemaAreReportedHIS001() async throws {
        let log = try HistoryLog(folder: folder)
        try await log.append(intent)
        try appendRaw(#"{"v":2,"ts":"2026-11-02T00:00:00.000Z","something":"new"}"# + "\n")
        try await log.append(result)

        let contents = try HistoryLog.read(folder: folder)
        #expect(contents.records == [intent, result])
        #expect(contents.unreadableLines == [2])
    }

    @Test func aMissingLogReadsAsEmpty() throws {
        let contents = try HistoryLog.read(folder: folder)
        #expect(contents.records.isEmpty)
        #expect(contents.unreadableLines.isEmpty)
        // So does a data folder without a log.
        try root.folder(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID))
        #expect(try HistoryLog.read(folder: folder) == contents)
    }

    // MARK: - Permissions and symlinks

    /// SAF-011, SAF-012: an unreadable parent is an access error, never "No history yet". The writer also refuses
    /// to proceed, so it cannot perform an operation without its history log (SAF-005).
    @Test func anUnreadableParentIsReportedSAF011() throws {
        let parent = try root.folder("Locked", permissions: 0o000)
        let folder = parent.appending(path: "History")

        let readError = #expect(throws: HistoryError.self) { try HistoryLog.read(folder: folder) }
        #expect(readError == .cannotOpen(folder.path, errno: EACCES))
        let writeError = #expect(throws: HistoryError.self) { try HistoryLog(folder: folder) }
        #expect(writeError == .cannotOpen(folder.path, errno: EACCES))
    }

    /// HIS-001: ENOTDIR, like ENOENT, means the requested log does not exist.
    @Test func aFileInTheParentPathReadsAsEmptyHIS001() throws {
        let file = try root.file("NotAFolder")
        let contents = try HistoryLog.read(folder: file.appending(path: "History"))
        #expect(contents.records.isEmpty)
        #expect(contents.unreadableLines.isEmpty)
    }

    /// SAF-011: a lookup failure other than a missing path is reported even without permission restrictions.
    @Test func aLoopInTheParentPathIsReportedSAF011() throws {
        let loop = root.url.appending(path: "Loop")
        try root.symlink("Loop", to: loop)
        let folder = loop.appending(path: "History")
        let error = #expect(throws: HistoryError.self) { try HistoryLog.read(folder: folder) }
        #expect(error == .cannotOpen(folder.path, errno: ELOOP))
    }

    @Test func createsTheFolderAs0700AndTheFileAs0600NFRSEC005() async throws {
        let log = try HistoryLog(folder: folder)
        try await log.append(intent)
        #expect(try mode(of: folder) == 0o700)
        #expect(try mode(of: log.fileURL) == 0o600)
        #expect(log.fileURL == folder.appending(path: "history.jsonl"))
        #expect(folder == root.url.appending(path: "Library/Application Support/me.nutabi.shuck"))
    }

    @Test func fixesLoosePermissionsNFRSEC005() throws {
        try root.folder(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID), permissions: 0o755)
        let file = try root.file(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID) + "/" + HistoryLog.fileName)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        _ = try HistoryLog(folder: folder)
        #expect(try mode(of: folder) == 0o700)
        #expect(try mode(of: file) == 0o600)
    }

    @Test func refusesADataFolderThatIsASymlink() throws {
        let elsewhere = try root.folder("Elsewhere")
        try root.symlink(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID), to: elsewhere)

        let error = #expect(throws: HistoryError.self) { try HistoryLog(folder: folder) }
        #expect(error == .notAFolder(folder.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    @Test func refusesALogFileThatIsASymlink() throws {
        let target = try root.file("Documents/notes.txt", size: 5)
        try root.folder(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID))
        let link = try root.symlink(
            ShuckKit.dataFolder(bundleID: ShuckKit.bundleID) + "/" + HistoryLog.fileName, to: target)

        let error = #expect(throws: HistoryError.self) { try HistoryLog(folder: folder) }
        #expect(error == .cannotOpen(link.path, errno: ELOOP))
        #expect(try target.resourceValues(forKeys: [.fileSizeKey]).fileSize == 5)
    }

    /// The reader refuses what the writer refuses, so History never lists records from a file Shuck did not write
    /// (D-46).
    @Test func theReaderRefusesADataFolderThatIsASymlinkHIS001() async throws {
        let elsewhere = try root.folder("Elsewhere")
        let planted = try HistoryLog(folder: elsewhere)
        try await planted.append(intent)
        try root.symlink(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID), to: elsewhere)

        let error = #expect(throws: HistoryError.self) { try HistoryLog.read(folder: folder) }
        #expect(error == .notAFolder(folder.path))
    }

    @Test func theReaderRefusesALogFileThatIsASymlinkHIS001() async throws {
        let elsewhere = try root.folder("Elsewhere")
        let planted = try HistoryLog(folder: elsewhere)
        try await planted.append(intent)
        try root.folder(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID))
        let link = try root.symlink(
            ShuckKit.dataFolder(bundleID: ShuckKit.bundleID) + "/" + HistoryLog.fileName, to: planted.fileURL)

        let error = #expect(throws: HistoryError.self) { try HistoryLog.read(folder: folder) }
        #expect(error == .cannotOpen(link.path, errno: ELOOP))
    }

    /// A FIFO planted as the log would block a reader that opened it for reading; both sides refuse it as a file that
    /// is not a regular file, without hanging (D-46, HIS-001).
    @Test func aFIFOPlantedAsTheLogIsRefusedByTheWriterAndTheReaderHIS001() throws {
        try root.folder(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID))
        let planted = try root.fifo(ShuckKit.dataFolder(bundleID: ShuckKit.bundleID) + "/" + HistoryLog.fileName)

        let reading = #expect(throws: HistoryError.self) { try HistoryLog.read(folder: folder) }
        #expect(reading == .notARegularFile(planted.path))
        let writing = #expect(throws: HistoryError.self) { try HistoryLog(folder: folder) }
        #expect(writing == .notARegularFile(planted.path))
    }

    @Test func aSecondLockIsRefusedWhileTheFirstIsHeldSAF018() async throws {
        var first: HistoryLog? = try HistoryLog(folder: folder)
        let error = #expect(throws: HistoryError.self) { try HistoryLog(folder: folder) }
        #expect(error == .locked(folder.appending(path: HistoryLog.fileName).path))

        // Reading needs no lock.
        #expect(try HistoryLog.read(folder: folder).records.isEmpty)

        first = nil
        let second = try HistoryLog(folder: folder)
        try await second.append(intent)
        #expect(first == nil)
    }
}
