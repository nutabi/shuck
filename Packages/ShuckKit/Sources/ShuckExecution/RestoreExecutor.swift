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
    let loader: LaunchctlAction

    /// `toolRunner` runs `launchctl`, and only for a request whose `reenableAgentLabel` the user confirmed; it has no
    /// default so that no caller gets a runner it did not choose (D-82).
    public init(pathGuard: PathGuard, log: HistoryLog, trash: any Trash, toolRunner: ToolRunner) {
        self.pathGuard = pathGuard
        self.log = log
        self.trash = trash
        self.loader = LaunchctlAction(runner: toolRunner, operation: .bootstrap)
    }

    /// One step of a run: restoring the item of a request, or then loading its LaunchAgent again (APP-011).
    private enum Unit {
        case restore(Int)
        case reenable(Int)
    }

    /// Where a restored item went, for the re-enable that follows it.
    private struct Restored {
        let url: URL
        let atOriginalPath: Bool
    }

    /// Restores `requests` and returns one outcome per request, in order.
    ///
    /// A request with a `reenableAgentLabel` gets a second item after its restore, with its own intent and result
    /// records, logged by the job label as a Launchctl item (SAF-006, HIS-002). It acts only if that request's restore
    /// was done in this run, and its failure never undoes or fails the restore (D-NEXT-reenable).
    public func run(_ requests: [RestoreRequest], run: UUID = UUID()) async -> RestoreReport {
        let loop = RunLoop(log: log, logger: Logger(tool: .history))
        var units: [Unit] = []
        for (index, request) in requests.enumerated() {
            units.append(.restore(index))
            if request.reenableAgentLabel != nil { units.append(.reenable(index)) }
        }
        var restored: [Int: Restored] = [:]
        let results = await loop.run(units) { unit -> RunLoop.Step<RestoreOutcome.SkipReason> in
            switch unit {
            case .restore(let index):
                let item = requests[index].item
                // Chosen before the intent record, which names it, and after earlier items took their " (restored)"
                // names.
                let destination = destination(for: requests[index])
                let logged = LoggedItem(
                    run: run, tool: .history, operation: .restore, path: (destination ?? item.originalURL).path,
                    tier: item.tier, bytes: item.bytes, trashedPath: item.trashedURL.path)
                return RunLoop.Step(logged: logged) {
                    let result = act(on: item, to: destination)
                    if case .done(let url?) = result {
                        restored[index] = Restored(url: url, atOriginalPath: destination == item.originalURL)
                    }
                    return Acted(result)
                }
            case .reenable(let index):
                let request = requests[index]
                let label = request.reenableAgentLabel ?? ""
                let logged = LoggedItem(
                    run: run, tool: .history, operation: .launchctl, path: label, tier: request.item.tier, bytes: nil)
                return RunLoop.Step(logged: logged) {
                    await reenable(request, label: label, restored: restored[index])
                }
            }
        }
        var outcomes: [RestoreOutcome] = []
        for (unit, result) in zip(units, results) {
            switch unit {
            case .restore(let index): outcomes.append(RestoreOutcome(request: requests[index], result: result))
            case .reenable: outcomes[outcomes.count - 1].reenable = result
            }
        }
        return RestoreReport(run: run, outcomes: outcomes)
    }

    /// Loads the LaunchAgent `label` again, after its property list was restored (APP-011, HIS-005, SAF-008).
    ///
    /// It acts only if the property list is back at its original path, directly inside `~/Library/LaunchAgents`,
    /// and the `Label` read from the restored file is `label`, the job the uninstall unloaded; a "Keep Both" copy or
    /// a file that changed is never loaded. The path `launchctl` gets is the one the path guard returned.
    private func reenable(
        _ request: RestoreRequest, label: String, restored: Restored?
    ) async -> Acted<RestoreOutcome.SkipReason> {
        guard let restored else {
            return Acted(.skipped(.dependencyNotDone(request.item.originalURL.path)))
        }
        let agents = pathGuard.configuration.home.appending(path: "Library/LaunchAgents")
        guard restored.atOriginalPath, request.item.tier.allows(.launchctl),
            restored.url.deletingLastPathComponent().pathComponents == ResolvedPath.realPath(agents)?.pathComponents
        else { return Acted(.skipped(.notTheUnloadedAgent("not at its original path in LaunchAgents"))) }
        guard let current = LaunchAgentLabel.read(at: restored.url), current == label else {
            return Acted(.skipped(.notTheUnloadedAgent("label differs from the unloaded job")))
        }
        let acted = await loader.perform(label: label, plist: restored.url)
        switch acted.result {
        case .done: return Acted(.done(nil), detail: acted.detail)
        case .failed(let error): return Acted(.failed(error), detail: acted.detail)
        case .skipped(.toolUnavailable(let unavailable)): return Acted(.skipped(.toolUnavailable(unavailable)))
        case .skipped: return Acted(.skipped(.cancelled))
        }
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
    package func act(on item: TrashedItem, to destination: URL?) -> RestoreOutcome.Result {
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
        } catch .notReadable {
            return .skipped(.notAccessible)
        } catch {
            return .skipped(pathGuard.restoreReason(for: error))
        }
        // Items are only ever taken from directly inside the Trash, never from elsewhere in the home folder.
        guard source.deletingLastPathComponent().pathComponents == ResolvedPath.realPath(trashFolder)?.pathComponents
        else {
            return .skipped(.notInTrash)
        }
        let current: ItemSnapshot
        // Stop takes effect while a large folder is measured, not only before the next item (SAF-014).
        switch ItemSnapshot.check(source, while: { !Task.isCancelled }) {
        case .found(let snapshot): current = snapshot
        case .missing: return .skipped(.missing)
        case .notAccessible: return .skipped(.notAccessible)
        case .stopped: return .skipped(.cancelled)
        }
        // Another item can take a trashed item's name once it has left the Trash; only its identity tells them apart.
        if let identity = item.identity, FileIdentity.read(source).map({ identity.isSameTrashedFile(as: $0) }) != true {
            return .skipped(.otherItem)
        }
        if let bytes = item.bytes, !ItemSnapshot.sizeMatches(planned: bytes, current: current.allocatedSize) {
            return .skipped(.changed(current))
        }
        // The folders this restore creates, so a failed move can take them away again (#120).
        let folder = target.deletingLastPathComponent()
        var created: [URL] = []
        var missing = folder
        while !FileManager.default.fileExists(atPath: missing.path), missing.pathComponents.count > 1 {
            created.append(missing)
            missing = missing.deletingLastPathComponent()
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Self.removeEmptyFolders(created)
            return .failed(ActionError(error))
        }
        // RENAME_EXCL fails instead of replacing an item that appeared at the destination since it was checked.
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            Self.removeEmptyFolders(created)
            if code == EEXIST { return .skipped(.originalTaken) }
            return .failed(ActionError(errno: code))
        }
        return .done(target)
    }

    /// Removes the folders in `folders`, deepest first, with `rmdir`, which removes only an empty folder.
    private static func removeEmptyFolders(_ folders: [URL]) {
        for folder in folders { _ = rmdir(folder.path) }
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
        /// The path guard refuses the destination because it is in, holds or is a folder the user excluded in
        /// Settings (SET-001, D-149). The associated value is the excluded path.
        case userExclusion(String)
        /// The trashed path is not directly inside the Trash folder.
        case notInTrash
        /// Another item has the trashed item's name in the Trash: its file identity is not the logged one, so the trashed
        /// item has left the Trash (HIS-004).
        case otherItem
        /// The run was cancelled before this item, or while it was re-validated (SAF-014).
        case cancelled
        /// The history log could not be written, so the run stopped (SAF-005).
        case historyUnavailable
        /// A re-enable needs its property list restored in this run, and it was not; the associated value is the
        /// property list's path (APP-011, D-198).
        case dependencyNotDone(String)
        /// A re-enable would load something other than the original agent; the associated value says why
        /// (APP-011, HIS-005).
        case notTheUnloadedAgent(String)
        /// `launchctl` is not where tools may be found (DEV-002, D-114).
        case toolUnavailable(ToolRunner.Unavailable)

        /// The reason's stable code, which the history log records (D-88).
        public var code: SkipCode {
            switch self {
            case .dependencyNotDone: .dependencyNotDone
            case .notTheUnloadedAgent: .notTheUnloadedAgent
            case .toolUnavailable: .toolUnavailable
            case .originalTaken: .originalTaken
            case .missing: .missing
            case .notAccessible: .notAccessible
            case .changed: .changed
            case .rejected: .rejected
            case .userExclusion: .userExclusion
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
            case .userExclusion(let path): code.logged(path)
            case .dependencyNotDone(let path): code.logged(path)
            case .notTheUnloadedAgent(let why): code.logged(why)
            case .toolUnavailable(let unavailable): code.logged(unavailable.rawValue)
            default: code.logged()
            }
        }
    }

    public let request: RestoreRequest
    public let result: Result
    /// What happened to loading the LaunchAgent again, for a request with a `reenableAgentLabel`; `nil` otherwise.
    /// Its own outcome: a skipped or failed re-enable leaves the restore as it was (APP-011).
    public internal(set) var reenable: Result?

    public init(request: RestoreRequest, result: Result, reenable: Result? = nil) {
        self.request = request
        self.result = result
        self.reenable = reenable
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
