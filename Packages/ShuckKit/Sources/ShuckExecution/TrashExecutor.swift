import Foundation
import ShuckKit
import os

/// Moves the items of a plan to the Trash, one at a time (SAF-004, SAF-008, SAF-011).
///
/// For each item the executor:
/// 1. writes an intent record to the history log (SAF-005);
/// 2. re-validates the item: the path guard again, then that it still exists with the same type and about the same
///    size as at scan time (SAF-008);
/// 3. moves it to the Trash, or skips it with a reason;
/// 4. writes a result record with the outcome and, for a trashed item, where it went and its file identity (SAF-005).
///
/// Every item ends with an outcome (SAF-011). If the history log cannot be written, the run stops: nothing is acted
/// on without a log record. Cancelling the task stops the run before the next item (SAF-014).
public struct TrashExecutor: Sendable {
    let pathGuard: PathGuard
    let log: HistoryLog
    let trash: any Trash

    private static let logger = Logger(subsystem: ShuckKit.loggerSubsystem, category: "Execution")

    public init(pathGuard: PathGuard, log: HistoryLog, trash: any Trash = SystemTrash()) {
        self.pathGuard = pathGuard
        self.log = log
        self.trash = trash
    }

    /// Runs `plan` and returns one outcome per item, in plan order.
    public func run(_ plan: Plan) async -> RunReport {
        var outcomes: [ItemOutcome] = []
        var stopReason: ItemOutcome.SkipReason?
        for item in plan.items {
            if let reason = stopReason ?? (Task.isCancelled ? .cancelled : nil) {
                outcomes.append(ItemOutcome(item: item, result: .skipped(reason)))
                continue
            }
            guard item.method == .trash else {
                outcomes.append(ItemOutcome(item: item, result: .skipped(.unsupportedMethod(item.method))))
                continue
            }
            do {
                try await log.append(record(for: item, in: plan, result: nil))
            } catch {
                stopReason = .historyUnavailable
                outcomes.append(ItemOutcome(item: item, result: .skipped(.historyUnavailable)))
                continue
            }

            let (result, identity) = act(on: item, allowedRoots: plan.allowedRoots)
            outcomes.append(ItemOutcome(item: item, result: result))
            do {
                try await log.append(record(for: item, in: plan, result: result, identity: identity))
            } catch {
                stopReason = .historyUnavailable
            }
        }
        return RunReport(run: plan.run, outcomes: outcomes)
    }

    /// Re-validates `item` and moves it to the Trash (SAF-008). Also returns the file identity of what it moved, which
    /// a move into the Trash on the same volume keeps, so Restore can tell it from a later item with its name.
    private func act(on item: PlannedItem, allowedRoots: [URL]) -> (ItemOutcome.Result, FileIdentity?) {
        let target: URL
        do {
            target = try pathGuard.validate(item.url, allowedRoots: allowedRoots)
        } catch {
            return (.skipped(.rejected(error)), nil)
        }
        guard let current = ItemSnapshot.read(target) else { return (.skipped(.missing), nil) }
        guard item.snapshot.matches(current) else { return (.skipped(.changed(current)), nil) }
        guard let identity = FileIdentity.read(target) else { return (.skipped(.missing), nil) }
        do {
            return (.trashed(try trash.trashItem(at: target)), identity)
        } catch {
            Self.logger.error("Cannot move an item to the Trash: \(String(describing: error), privacy: .private)")
            return (.failed(String(describing: error)), nil)
        }
    }

    /// The intent record for `item`, or its result record when `result` is given.
    private func record(
        for item: PlannedItem, in plan: Plan, result: ItemOutcome.Result?, identity: FileIdentity? = nil
    ) -> HistoryRecord {
        let path = item.url.path
        let bytes = item.snapshot.allocatedSize
        guard let result else {
            return .intent(run: plan.run, tool: plan.tool, operation: .trash, path: path, tier: item.tier, bytes: bytes)
        }
        let status: HistoryRecord.Status
        var trashedPath: String?
        var detail: String?
        switch result {
        case .trashed(let url):
            status = .ok
            trashedPath = url.path
        case .skipped(let reason):
            status = .skipped
            detail = String(describing: reason)
        case .failed(let error):
            status = .failed
            detail = error
        }
        return .result(
            run: plan.run, tool: plan.tool, operation: .trash, path: path, tier: item.tier, status: status,
            trashedPath: trashedPath, identity: identity, bytes: bytes, detail: detail)
    }
}

/// The outcome of one planned item (SAF-011).
public struct ItemOutcome: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        /// Moved to the Trash; the URL is where it went.
        case trashed(URL)
        case skipped(SkipReason)
        /// The move failed; the text describes the error.
        case failed(String)
    }

    public enum SkipReason: Equatable, Sendable {
        /// The item no longer exists (SAF-008).
        case missing
        /// The item's type or size changed since the scan; the snapshot is what it looks like now (SAF-008).
        case changed(ItemSnapshot)
        /// The path guard rejects the item now (SAF-007, SAF-008).
        case rejected(PathGuardError)
        /// The run was cancelled before this item (SAF-014).
        case cancelled
        /// The history log could not be written, so the run stopped (SAF-005).
        case historyUnavailable
        /// This executor only moves items to the Trash.
        case unsupportedMethod(ActionMethod)
    }

    public let item: PlannedItem
    public let result: Result

    public init(item: PlannedItem, result: Result) {
        self.item = item
        self.result = result
    }
}

/// The outcomes of one run, in plan order.
public struct RunReport: Equatable, Sendable {
    public let run: UUID
    public let outcomes: [ItemOutcome]

    public init(run: UUID, outcomes: [ItemOutcome]) {
        self.run = run
        self.outcomes = outcomes
    }
}
