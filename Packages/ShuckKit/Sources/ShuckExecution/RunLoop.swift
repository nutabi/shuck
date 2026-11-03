import Foundation
import ShuckKit
import os

/// What happened to one item of a run, whatever its method (SAF-011).
public enum ActionResult<SkipReason: RunSkipReason>: Equatable, Sendable {
    /// The action was done. The URL is where the item went: into the Trash, or back out of it for a restore. A method
    /// that doesn't move the item, such as Delete or Tool, has none.
    case done(URL?)
    /// The item was left as it was.
    case skipped(SkipReason)
    /// The action was tried and failed.
    case failed(ActionError)
}

/// Why an item was skipped. The run loop skips items with the first two reasons on its own.
public protocol RunSkipReason: Equatable, Sendable {
    /// The run was cancelled before this item (SAF-014).
    static var cancelled: Self { get }
    /// The history log could not be written, so the run stopped (SAF-005).
    static var historyUnavailable: Self { get }
    /// The text the history log records: the reason's code, and after a colon what re-validation found (D-88).
    var logged: String { get }
}

/// What an action did to an item, and what the result record adds to the intent record: where a trashed item went
/// and its file identity (D-84).
package struct Acted<SkipReason: RunSkipReason>: Sendable {
    package let result: ActionResult<SkipReason>
    let trashedPath: String?
    let identity: FileIdentity?

    package init(_ result: ActionResult<SkipReason>, trashedPath: String? = nil, identity: FileIdentity? = nil) {
        self.result = result
        self.trashedPath = trashedPath
        self.identity = identity
    }
}

/// Where a run writes its records: the history log. Tests pass one that fails, to check that the run stops (SAF-005).
package protocol RecordLog: Sendable {
    func append(_ record: HistoryRecord) async throws(HistoryError)
}

extension HistoryLog: RecordLog {}

/// What the history log records about an item in both its intent and its result record (section 8.5).
struct LoggedItem {
    let run: UUID
    let tool: ToolID
    let operation: HistoryRecord.Operation
    /// The item's path; for a restore, where it goes (D-52).
    let path: String
    let tier: Tier
    let bytes: Int64?
    /// For a restore, where the item comes from (D-52).
    var trashedPath: String? = nil

    var intent: HistoryRecord {
        .intent(
            run: run, tool: tool, operation: operation, path: path, tier: tier, trashedPath: trashedPath, bytes: bytes)
    }

    func result<SkipReason>(_ acted: Acted<SkipReason>) -> HistoryRecord {
        let (status, detail): (HistoryRecord.Status, String?) =
            switch acted.result {
            case .done: (.ok, nil)
            case .skipped(let reason): (.skipped, reason.logged)
            case .failed(let error): (.failed, error.logged)
            }
        return .result(
            run: run, tool: tool, operation: operation, path: path, tier: tier, status: status,
            trashedPath: acted.trashedPath ?? trashedPath, identity: acted.identity, bytes: bytes, detail: detail)
    }
}

/// The loop every run goes through, whatever its items and their methods (TD-04). ``PlanExecutor`` and
/// ``RestoreExecutor`` each hand it their items and an action for each.
///
/// For each item, in order, the loop:
/// 1. skips the item without a log record if an earlier record could not be written (SAF-005) or the run was
///    cancelled (SAF-014): nothing was done to it;
/// 2. writes the intent record (SAF-005); if that fails, skips the item and stops the run;
/// 3. runs the item's action, which re-validates it (SAF-008) and acts, or says why not;
/// 4. writes the result record with the outcome (SAF-005, SAF-011); if that fails, stops the run.
///
/// So every item ends with an outcome (SAF-011), and nothing is acted on without an intent record.
struct RunLoop {
    let log: any RecordLog
    /// Logs failed actions, under the category of the tool the run is for (NFR-OBS-001).
    let logger: Logger

    /// One item's turn in the loop: what the log records about it, and its action.
    struct Step<SkipReason: RunSkipReason> {
        let logged: LoggedItem
        let act: () -> Acted<SkipReason>
    }

    /// Runs `items` in order and returns one result per item. `prepare` is called for each item just before its intent
    /// record, so a step can depend on what earlier items did, as a restore's " (restored)" name does.
    func run<Item, SkipReason>(_ items: [Item], prepare: (Item) -> Step<SkipReason>) async
        -> [ActionResult<SkipReason>]
    {
        var results: [ActionResult<SkipReason>] = []
        var stopReason: SkipReason?
        for item in items {
            if let reason = stopReason ?? (Task.isCancelled ? .cancelled : nil) {
                results.append(.skipped(reason))
                continue
            }
            let step = prepare(item)
            do {
                try await log.append(step.logged.intent)
            } catch {
                stopReason = .historyUnavailable
                results.append(.skipped(.historyUnavailable))
                continue
            }

            let acted = step.act()
            if case .failed(let error) = acted.result {
                logger.error(
                    """
                    Cannot \(step.logged.operation.rawValue, privacy: .public) an item: \
                    \(error.domain, privacy: .public) \(error.code, privacy: .public), \
                    \(error.message, privacy: .private)
                    """)
            }
            results.append(acted.result)
            do {
                try await log.append(step.logged.result(acted))
            } catch {
                stopReason = .historyUnavailable
            }
        }
        return results
    }
}
