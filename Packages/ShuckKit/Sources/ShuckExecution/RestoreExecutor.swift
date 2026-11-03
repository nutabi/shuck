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
/// The move is Shuck's own, not Finder's "Put Back" (HIS-006). Steps 2 to 5 are ``RunLoop``'s, as for a plan: the run
/// stops if the log cannot be written, and cancelling stops it before the next item (SAF-014).
public struct RestoreExecutor: Sendable {
    let pathGuard: PathGuard
    let log: HistoryLog
    let trash: any Trash

    public init(pathGuard: PathGuard, log: HistoryLog, trash: any Trash) {
        self.pathGuard = pathGuard
        self.log = log
        self.trash = trash
    }

    /// Restores `requests` and returns one outcome per request, in order.
    public func run(_ requests: [RestoreRequest], run: UUID = UUID()) async -> RestoreReport {
        let loop = RunLoop(log: log, logger: Logger(tool: .history))
        let results = await loop.run(requests) { request in
            let item = request.item
            // Chosen before the intent record, which names it, and after earlier items took their " (restored)" names.
            let destination = destination(for: request)
            let logged = LoggedItem(
                run: run, tool: .history, operation: .restore, path: (destination ?? item.originalURL).path,
                tier: item.tier, bytes: item.bytes, trashedPath: item.trashedURL.path)
            return RunLoop.Step(logged: logged) { Acted(act(on: item, to: destination)) }
        }
        return RestoreReport(
            run: run, outcomes: zip(requests, results).map { RestoreOutcome(request: $0, result: $1) })
    }

    /// Where `request` should go, or `nil` when the original path is taken and the user chose to skip.
    private func destination(for request: RestoreRequest) -> URL? {
        let original = request.item.originalURL
        guard request.item.originalIsTaken else { return original }
        guard request.ifTaken == .keepBoth else { return nil }
        return (1...99).lazy.map { Self.keepBothURL(for: original, number: $0) }.first {
            !ResolvedPath.itemExists(at: $0)
        }
    }

    /// Re-validates `item` and moves it to `destination` (SAF-008).
    private func act(on item: TrashedItem, to destination: URL?) -> RestoreOutcome.Result {
        guard let destination else { return .skipped(.originalTaken) }
        let trashFolder: URL
        do {
            trashFolder = try trash.folder
        } catch {
            return .failed(error)
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
        guard source.deletingLastPathComponent().pathComponents == ResolvedPath.realPath(trashFolder)?.pathComponents
        else {
            return .skipped(.notInTrash)
        }
        let current: ItemSnapshot
        switch ItemSnapshot.check(source) {
        case .found(let snapshot): current = snapshot
        case .missing: return .skipped(.missing)
        case .notAccessible: return .skipped(.notAccessible)
        }
        // Another item can take a trashed item's name once it has left the Trash; only its identity tells them apart.
        if let identity = item.identity, FileIdentity.read(source).map({ identity.isSameTrashedFile(as: $0) }) != true {
            return .skipped(.otherItem)
        }
        if let bytes = item.bytes, !ItemSnapshot.sizeMatches(planned: bytes, current: current.allocatedSize) {
            return .skipped(.changed(current))
        }
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .failed(ActionError(error))
        }
        // RENAME_EXCL fails instead of replacing an item that appeared at the destination since it was checked.
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST { return .skipped(.originalTaken) }
            return .failed(ActionError(errno: code))
        }
        return .done(target)
    }

    /// `original` with " (restored)" added before its extension, numbered from the second try:
    /// `report (restored).pdf`, `report (restored 2).pdf`.
    static func keepBothURL(for original: URL, number: Int) -> URL {
        let name = original.deletingPathExtension().lastPathComponent
        let suffix = original.pathExtension.isEmpty ? "" : "." + original.pathExtension
        let label = number == 1 ? "restored" : "restored \(number)"
        return original.deletingLastPathComponent().appending(path: "\(name) (\(label))\(suffix)")
    }
}

/// The outcome of one restore request (SAF-011).
public struct RestoreOutcome: Equatable, Sendable {
    /// Done (moved back, to the URL it has), skipped or failed, as for a plan's items.
    public typealias Result = ActionResult<SkipReason>

    public enum SkipReason: RunSkipReason {
        /// Something occupies the original path, and the user chose to skip, or no free name was found (HIS-003).
        case originalTaken
        /// The item is no longer in the Trash: "Not restorable (Trash emptied)" (HIS-004).
        case missing
        /// Shuck may not read the item in the Trash, for example without Full Disk Access (SAF-008, SAF-012).
        case notAccessible
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

        /// The reason's stable code, which the history log records (D-88).
        public var code: SkipCode {
            switch self {
            case .originalTaken: .originalTaken
            case .missing: .missing
            case .notAccessible: .notAccessible
            case .changed: .changed
            case .rejected: .rejected
            case .notInTrash: .notInTrash
            case .otherItem: .otherItem
            case .cancelled: .cancelled
            case .historyUnavailable: .historyUnavailable
            }
        }

        /// The text the history log records: the code, and after a colon what re-validation found (D-88).
        public var logged: String {
            switch self {
            case .changed(let current): code.logged(current.logged)
            case .rejected(let error): code.logged(error.logged)
            default: code.logged()
            }
        }
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
