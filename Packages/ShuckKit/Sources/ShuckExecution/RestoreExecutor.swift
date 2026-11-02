import Foundation
import ShuckKit
import os

/// Moves trashed items back to their original paths, one at a time (HIS-003, HIS-004).
///
/// For each item the executor:
/// 1. picks the destination: the original path, or with "keep both" a free " (restored)" name next to it;
/// 2. writes an intent record to the history log, naming the destination and the trashed path (SAF-005);
/// 3. re-validates: the path guard for both paths, the item is directly inside the Trash folder, still exists, has the
///    file identity that was logged, if one was, and is about the size that was logged (SAF-008);
/// 4. moves it back, creating missing parent folders, and never replaces anything already at the destination;
/// 5. writes a result record with the outcome.
///
/// The move is Shuck's own, not Finder's "Put Back" (HIS-006). Like ``TrashExecutor``, the run stops if the log cannot
/// be written, and cancelling stops it before the next item (SAF-014).
public struct RestoreExecutor: Sendable {
    let pathGuard: PathGuard
    let log: HistoryLog
    let trash: any Trash

    private static let logger = Logger(subsystem: ShuckKit.loggerSubsystem, category: "Restore")

    public init(pathGuard: PathGuard, log: HistoryLog, trash: any Trash = SystemTrash()) {
        self.pathGuard = pathGuard
        self.log = log
        self.trash = trash
    }

    /// Restores `requests` and returns one outcome per request, in order.
    public func run(_ requests: [RestoreRequest], run: UUID = UUID()) async -> RestoreReport {
        var outcomes: [RestoreOutcome] = []
        var stopReason: RestoreOutcome.SkipReason?
        for request in requests {
            if let reason = stopReason ?? (Task.isCancelled ? .cancelled : nil) {
                outcomes.append(RestoreOutcome(request: request, result: .skipped(reason)))
                continue
            }
            let destination = destination(for: request)
            do {
                try await log.append(record(for: request, to: destination, run: run, result: nil))
            } catch {
                stopReason = .historyUnavailable
                outcomes.append(RestoreOutcome(request: request, result: .skipped(.historyUnavailable)))
                continue
            }

            let result = act(on: request.item, to: destination)
            outcomes.append(RestoreOutcome(request: request, result: result))
            do {
                try await log.append(record(for: request, to: destination, run: run, result: result))
            } catch {
                stopReason = .historyUnavailable
            }
        }
        return RestoreReport(run: run, outcomes: outcomes)
    }

    /// Where `request` should go, or `nil` when the original path is taken and the user chose to skip.
    private func destination(for request: RestoreRequest) -> URL? {
        let original = request.item.originalURL
        guard request.item.originalIsTaken else { return original }
        guard request.ifTaken == .keepBoth else { return nil }
        return (1...99).lazy.map { Self.keepBothURL(for: original, number: $0) }.first { !Self.itemExists(at: $0) }
    }

    /// Re-validates `item` and moves it to `destination` (SAF-008).
    private func act(on item: TrashedItem, to destination: URL?) -> RestoreOutcome.Result {
        guard let destination else { return .skipped(.originalTaken) }
        let trashFolder: URL
        do {
            trashFolder = try trash.folder
        } catch {
            return .failed(String(describing: error))
        }
        let source: URL
        let target: URL
        do {
            // Both paths must be inside the home folder and outside protected locations. The source is checked
            // against the home folder rather than the Trash, so a trashed symlink to a file in the home folder passes.
            source = try pathGuard.validate(item.trashedURL, allowedRoots: [pathGuard.configuration.home])
            target = try pathGuard.validate(destination, allowedRoots: [pathGuard.configuration.home])
        } catch {
            return .skipped(.rejected(error))
        }
        // Items are only ever taken from directly inside the Trash, never from elsewhere in the home folder.
        guard source.deletingLastPathComponent().pathComponents == Self.realPath(trashFolder)?.pathComponents else {
            return .skipped(.notInTrash)
        }
        guard let current = ItemSnapshot.read(source) else { return .skipped(.missing) }
        // Another item can take a trashed item's name once it has left the Trash; only its identity tells them apart.
        if let identity = item.identity, FileIdentity.read(source) != identity { return .skipped(.otherItem) }
        if let bytes = item.bytes, !ItemSnapshot.sizeMatches(planned: bytes, current: current.allocatedSize) {
            return .skipped(.changed(current))
        }
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Cannot recreate a parent folder: \(String(describing: error), privacy: .private)")
            return .failed(String(describing: error))
        }
        // RENAME_EXCL fails instead of replacing an item that appeared at the destination since it was checked.
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST { return .skipped(.originalTaken) }
            Self.logger.error("Cannot restore an item: \(String(cString: strerror(code)), privacy: .public)")
            return .failed(String(cString: strerror(code)))
        }
        return .restored(target)
    }

    /// The intent record for `request`, or its result record when `result` is given. The record's path is where the
    /// item goes, and its trashed path is where it comes from (D-52).
    private func record(for request: RestoreRequest, to destination: URL?, run: UUID, result: RestoreOutcome.Result?)
        -> HistoryRecord
    {
        let item = request.item
        let path = (destination ?? item.originalURL).path
        let trashedPath = item.trashedURL.path
        guard let result else {
            return .intent(
                run: run, tool: .history, operation: .restore, path: path, tier: item.tier, trashedPath: trashedPath,
                bytes: item.bytes)
        }
        let status: HistoryRecord.Status
        var detail: String?
        switch result {
        case .restored:
            status = .ok
        case .skipped(let reason):
            status = .skipped
            detail = String(describing: reason)
        case .failed(let error):
            status = .failed
            detail = error
        }
        return .result(
            run: run, tool: .history, operation: .restore, path: path, tier: item.tier, status: status,
            trashedPath: trashedPath, bytes: item.bytes, detail: detail)
    }

    /// `original` with " (restored)" added before its extension, numbered from the second try:
    /// `report (restored).pdf`, `report (restored 2).pdf`.
    static func keepBothURL(for original: URL, number: Int) -> URL {
        let name = original.deletingPathExtension().lastPathComponent
        let suffix = original.pathExtension.isEmpty ? "" : "." + original.pathExtension
        let label = number == 1 ? "restored" : "restored \(number)"
        return original.deletingLastPathComponent().appending(path: "\(name) (\(label))\(suffix)")
    }

    /// Whether anything, including a symlink, exists at `url`. Does not follow a final symlink.
    private static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// `url` with all symlinks resolved as the path guard resolves them, or `nil` if it doesn't exist.
    private static func realPath(_ url: URL) -> URL? {
        guard let pointer = realpath(url.path, nil) else { return nil }
        defer { free(pointer) }
        return URL(filePath: String(cString: pointer))
    }
}

/// The outcome of one restore request (SAF-011).
public struct RestoreOutcome: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        /// Moved back; the URL is where it went.
        case restored(URL)
        case skipped(SkipReason)
        /// The move failed; the text describes the error.
        case failed(String)
    }

    public enum SkipReason: Equatable, Sendable {
        /// Something occupies the original path, and the user chose to skip, or no free name was found (HIS-003).
        case originalTaken
        /// The item is no longer in the Trash: "Not restorable (Trash emptied)" (HIS-004).
        case missing
        /// The item's size changed since it was trashed; the snapshot is what it looks like now (SAF-008).
        case changed(ItemSnapshot)
        /// The path guard rejects the trashed path or the destination (SAF-007, SAF-008).
        case rejected(PathGuardError)
        /// The trashed path is not directly inside the Trash folder.
        case notInTrash
        /// Another item has the trashed item's name in the Trash: its file identity is not the logged one, so the trashed
        /// item has left the Trash (HIS-004).
        case otherItem
        /// The run was cancelled before this item (SAF-014).
        case cancelled
        /// The history log could not be written, so the run stopped (SAF-005).
        case historyUnavailable
    }

    public let request: RestoreRequest
    public let result: Result

    public init(request: RestoreRequest, result: Result) {
        self.request = request
        self.result = result
    }
}

/// The outcomes of one restore run, in request order.
public struct RestoreReport: Equatable, Sendable {
    public let run: UUID
    public let outcomes: [RestoreOutcome]

    public init(run: UUID, outcomes: [RestoreOutcome]) {
        self.run = run
        self.outcomes = outcomes
    }
}
