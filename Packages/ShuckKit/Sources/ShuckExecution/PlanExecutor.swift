import Foundation
import ShuckKit
import os

/// Runs a plan: hands each item, in plan order, to the action for its method (SAF-004, SAF-008, SAF-011).
///
/// Every item goes through ``RunLoop``: an intent record, re-validation, the action and a result record. Re-validation
/// is the same for every method: the path guard again, then that the item still exists, Shuck may read it (SAF-012),
/// and it has the same type and about the same size as at scan time (SAF-008). An action may check more, as the Trash
/// reads the file identity it logs (D-84).
///
/// A plan may mix methods, as a Developer Junk run mixes Delete and Tool items behind one confirmation (section 8.2).
/// An item whose method has no action yet is skipped as `unsupportedMethod` and logged like any other skip (D-89).
/// Each item's tier is checked against its method again before its action runs, so "Your data" never reaches Delete,
/// however its plan was built (SAF-004).
public struct PlanExecutor: Sendable {
    let pathGuard: PathGuard
    let log: any RecordLog
    let actions: [ActionMethod: any PlanAction]

    /// An executor that moves Trash items to `trash`: ``SystemTrash`` in the app, a fake in tests, which must never reach
    /// the user's own Trash. M2 adds Delete and Tool, and M3 Launchctl.
    public init(pathGuard: PathGuard, log: HistoryLog, trash: any Trash) {
        self.init(pathGuard: pathGuard, log: log, actions: [.trash: TrashAction(trash: trash)])
    }

    /// An executor with `actions`, one per method it can act on. Tests pass actions of their own.
    package init(pathGuard: PathGuard, log: any RecordLog, actions: [ActionMethod: any PlanAction]) {
        self.pathGuard = pathGuard
        self.log = log
        self.actions = actions
    }

    /// Runs `plan` and returns one outcome per item, in plan order.
    public func run(_ plan: Plan) async -> RunReport {
        let loop = RunLoop(log: log, logger: Logger(tool: plan.tool))
        let results = await loop.run(plan.items) { item in
            let logged = LoggedItem(
                run: plan.run, tool: plan.tool, operation: HistoryRecord.Operation(item.method), path: item.url.path,
                tier: item.tier, bytes: item.snapshot.allocatedSize)
            return RunLoop.Step(logged: logged) { act(on: item, allowedRoots: plan.allowedRoots) }
        }
        return RunReport(run: plan.run, outcomes: zip(plan.items, results).map { ItemOutcome(item: $0, result: $1) })
    }

    /// Re-validates `item` and hands it to the action for its method (SAF-004, SAF-008).
    package func act(on item: PlannedItem, allowedRoots: [URL]) -> Acted<ItemOutcome.SkipReason> {
        // `Plan` refuses such an item too; checking again keeps SAF-004 in the executor, next to the actions.
        guard item.tier.allows(item.method) else { return Acted(.skipped(.notAllowed(item.method))) }
        guard let action = actions[item.method] else { return Acted(.skipped(.unsupportedMethod(item.method))) }
        let target: URL
        do {
            target = try pathGuard.validate(item.url, allowedRoots: allowedRoots)
        } catch {
            return Acted(.skipped(.rejected(error)))
        }
        switch ItemSnapshot.check(target) {
        case .found(let current) where item.snapshot.matches(current): return action.act(on: item, at: target)
        case .found(let current): return Acted(.skipped(.changed(current)))
        case .missing: return Acted(.skipped(.missing))
        case .notAccessible: return Acted(.skipped(.notAccessible))
        }
    }
}

/// What a run does to an item of one method, once the item has passed re-validation: ``TrashAction`` now; M2 adds
/// Delete and Tool, and M3 Launchctl (TD-04).
package protocol PlanAction: Sendable {
    /// Acts on `item`, at `target`, the path the guard returned for it, and says what it did.
    func act(on item: PlannedItem, at target: URL) -> Acted<ItemOutcome.SkipReason>
}

/// The outcome of one planned item (SAF-011).
public struct ItemOutcome: Equatable, Sendable {
    /// Done, skipped or failed, whatever the item's method. A trashed item's result has where it went.
    public typealias Result = ActionResult<SkipReason>

    public enum SkipReason: RunSkipReason {
        /// The item no longer exists (SAF-008).
        case missing
        /// Shuck may not read the item, for example without Full Disk Access (SAF-008, SAF-012).
        case notAccessible
        /// The item's type or size changed since the scan; the snapshot is what it looks like now (SAF-008).
        case changed(ItemSnapshot)
        /// The path guard rejects the item now (SAF-007, SAF-008).
        case rejected(PathGuardError)
        /// The run was cancelled before this item (SAF-014).
        case cancelled
        /// The history log could not be written, so the run stopped (SAF-005).
        case historyUnavailable
        /// The executor has no action for the item's method yet (D-89).
        case unsupportedMethod(ActionMethod)
        /// The item's tier does not allow its method, as "Your data" is never deleted permanently (SAF-004). `Plan`
        /// refuses such an item, so only a plan built some other way could have one.
        case notAllowed(ActionMethod)

        /// The reason's stable code, which the history log records (D-88).
        public var code: SkipCode {
            switch self {
            case .missing: .missing
            case .notAccessible: .notAccessible
            case .changed: .changed
            case .rejected: .rejected
            case .cancelled: .cancelled
            case .historyUnavailable: .historyUnavailable
            case .unsupportedMethod: .unsupportedMethod
            case .notAllowed: .notAllowed
            }
        }

        /// The text the history log records: the code, and after a colon what re-validation found (D-88).
        public var logged: String {
            switch self {
            case .changed(let current): code.logged(current.logged)
            case .rejected(let error): code.logged(error.logged)
            case .unsupportedMethod(let method), .notAllowed(let method): code.logged(method.rawValue)
            default: code.logged()
            }
        }
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
