import Foundation
import os

/// Shuck's history log: an append-only JSON Lines file in Shuck's data folder (PRD section 8.5, HIS-001).
///
/// The folder is kept at mode 0700 and the file at 0600 (NFR-SEC-005); wrong modes are fixed when the log opens
/// (D-45). Each record is written with one `write` call and flushed to disk before ``append(_:)`` returns, so a crash
/// can lose at most the record being written. A line cut short by a crash is skipped by the reader and reported in
/// ``Contents/unreadableLines``, and the writer starts the next record on a new line.
public actor HistoryLog {
    public static let fileName = "history.jsonl"

    /// The log file.
    public nonisolated let fileURL: URL
    private let handle: FileHandle

    private static let logger = Logger(subsystem: ShuckKit.loggerSubsystem, category: "History")

    /// The data folder inside `home` of the build with `bundleID`, where that build keeps its log (D-70).
    public static func folder(home: URL, bundleID: String) -> URL {
        home.appending(path: ShuckKit.dataFolder(bundleID: bundleID))
    }

    /// Opens the log in `folder` for appending, creating the folder and the file if needed.
    public init(folder: URL) throws(HistoryError) {
        try Self.prepare(folder: folder)
        let fileURL = folder.appending(path: Self.fileName)
        let (handle, info) = try Self.openFile(fileURL, flags: O_RDWR | O_APPEND | O_CREAT)
        let descriptor = handle.fileDescriptor
        if info.st_mode & 0o777 != 0o600 {
            Self.logger.notice("Fixing the history log's permissions")
            guard fchmod(descriptor, 0o600) == 0 else { throw .cannotOpen(fileURL.path, errno: errno) }
        }
        // A crash can leave the last record without its line break; start the next record on a new line.
        var lastByte: UInt8 = 0
        if info.st_size > 0, pread(descriptor, &lastByte, 1, info.st_size - 1) == 1, lastByte != UInt8(ascii: "\n") {
            do {
                try handle.write(contentsOf: Data("\n".utf8))
            } catch {
                throw .cannotWrite(fileURL.path, String(describing: error))
            }
        }
        self.fileURL = fileURL
        self.handle = handle
    }

    /// Appends `record` and flushes it to disk (HIS-001).
    public func append(_ record: HistoryRecord) throws(HistoryError) {
        do {
            try handle.write(contentsOf: record.jsonLine() + Data("\n".utf8))
            try handle.synchronize()
        } catch {
            // Private: a Foundation error's description can include the file's path (NFR-SEC-006).
            Self.logger.error("Cannot write to the history log: \(String(describing: error), privacy: .private)")
            throw .cannotWrite(fileURL.path, String(describing: error))
        }
    }

    // MARK: - Reading

    /// The records of a log, in the order they were written.
    public struct Contents: Equatable, Sendable {
        public let records: [HistoryRecord]
        /// 1-based numbers of lines that could not be read, for example a record cut short by a crash.
        public let unreadableLines: [Int]
    }

    /// Reads the log in `folder`. A missing log reads as empty.
    ///
    /// Like the writer, the reader refuses a data folder or a log that is a symlink, so History never lists records
    /// from a file Shuck did not write (D-46).
    public static func read(folder: URL) throws(HistoryError) -> Contents {
        let empty = Contents(records: [], unreadableLines: [])
        guard try existingFolder(folder) != nil else { return empty }
        let fileURL = folder.appending(path: fileName)
        let handle: FileHandle
        do {
            // O_NONBLOCK: a FIFO planted there would block the open until something writes to it. This way the file
            // check refuses it.
            (handle, _) = try openFile(fileURL, flags: O_RDONLY | O_NONBLOCK)
        } catch .cannotOpen(_, errno: ENOENT) {
            return empty
        }
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            throw .cannotRead(fileURL.path, String(describing: error))
        }
        var records: [HistoryRecord] = []
        var unreadable: [Int] = []
        for (index, line) in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).enumerated()
        where !line.isEmpty {
            if let record = HistoryRecord.decode(line: Data(line)) {
                records.append(record)
            } else {
                unreadable.append(index + 1)
            }
        }
        if !unreadable.isEmpty {
            logger.error("The history log has \(unreadable.count, privacy: .public) unreadable lines")
        }
        return Contents(records: records, unreadableLines: unreadable)
    }

    // MARK: - The data folder and the log file

    /// Opens the log file with `flags`, never through a symlink planted where the log should be (O_NOFOLLOW, D-46),
    /// and checks that it is a regular file.
    private static func openFile(_ fileURL: URL, flags: Int32) throws(HistoryError) -> (FileHandle, stat) {
        let descriptor = open(fileURL.path, flags | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .cannotOpen(fileURL.path, errno: errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw .notARegularFile(fileURL.path)
        }
        return (handle, info)
    }

    /// The data folder's attributes, or `nil` if nothing is there. Anything but a folder is refused: attributesOfItem
    /// does not follow a symlink, so a symlink fails the type check (D-46).
    private static func existingFolder(_ folder: URL) throws(HistoryError) -> [FileAttributeKey: Any]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: folder.path) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw .notAFolder(folder.path) }
        return attributes
    }

    /// Creates the data folder with mode 0700, or checks an existing one and fixes its mode (NFR-SEC-005, D-45).
    private static func prepare(folder: URL) throws(HistoryError) {
        let manager = FileManager.default
        do {
            if let attributes = try existingFolder(folder) {
                if attributes[.posixPermissions] as? Int != 0o700 {
                    logger.notice("Fixing the data folder's permissions")
                    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
                }
            } else {
                // Parents such as Application Support keep their default modes; only Shuck's own folder is 0700.
                try manager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.createDirectory(
                    at: folder, withIntermediateDirectories: false,
                    attributes: [
                        .posixPermissions: 0o700
                    ])
            }
        } catch let error as HistoryError {
            throw error
        } catch {
            throw .cannotPrepareFolder(folder.path, String(describing: error))
        }
    }
}

/// Why the history log could not be opened, written or read. The executor runs nothing while the log is unusable,
/// since every operation must be logged first (SAF-005, SAF-006).
public enum HistoryError: Error, Equatable {
    /// Something other than a folder, such as a symlink or a file, is where the data folder should be.
    case notAFolder(String)
    /// Something other than a regular file, such as a folder, is where the log file should be. A symlink there fails
    /// to open instead, with `ELOOP`.
    case notARegularFile(String)
    /// The data folder could not be created or its permissions fixed.
    case cannotPrepareFolder(String, String)
    case cannotOpen(String, errno: Int32)
    case cannotWrite(String, String)
    case cannotRead(String, String)
}
