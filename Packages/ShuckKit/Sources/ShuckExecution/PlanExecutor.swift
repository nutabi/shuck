import Foundation
import ShuckKit
import os

/// Runs a plan: hands each item, in plan order, to the action for its method (SAF-004, SAF-008, SAF-011).
///
/// Every item goes through ``RunLoop``: an intent record, re-validation, the action and a result record. Re-validation
/// is the same for every method: the path guard again, then that the item still exists, Shuck may read it (SAF-012),
/// and it has the same type and about the same size as at scan time (SAF-008). An item whose scan read its file
/// identity must also still be that file, so a file put in its place since is skipped (D-103). An action may check
/// more, as the Trash reads the file identity it logs (D-84).
/// Rule-backed items must still match the reviewed rule and its detection, and a Delete item without a rule is skipped
/// (D-100, D-132). Every item's modification date must still be the one its scan read, the newest inside for an item
/// whose scope is its contents, so a file in use or a newly active cache is skipped even when size and kind match
/// (SAF-008, D-105, D-132).
/// Last, an item is skipped while one of its apps runs, as the app may have started after the scan (SAF-009, D-110).
///
/// A plan may mix methods, as a Developer Junk run mixes Delete and Tool items behind one confirmation (section 8.2).
/// An item whose method has no action yet is skipped as `unsupportedMethod` and logged like any other skip (D-89).
/// Each item's tier is checked against its method again before its action runs, so "Your data" never reaches Delete,
/// however its plan was built (SAF-004).
public struct PlanExecutor: Sendable {
    let pathGuard: PathGuard
    let log: any RecordLog
    let actions: [ActionMethod: any PlanAction]
    let runningApps: any RunningApps
    /// What runs Tool items; without it, they are skipped as `unsupportedMethod` (D-89).
    let toolAction: ToolAction?

    /// An executor that moves Trash items to `trash`: ``SystemTrash`` in the app, a fake in tests, which must never reach
    /// the user's own Trash. It deletes Delete items permanently (SAF-006) and runs Tool items with `toolRunner`
    /// (DEV-004); M3 adds Launchctl. `runningApps` and `toolRunner` have no default, so the app cannot leave out the
    /// check just before acting (SAF-009) or let a test run a real tool (D-114).
    public init(
        pathGuard: PathGuard, log: HistoryLog, trash: any Trash, runningApps: any RunningApps, toolRunner: ToolRunner
    ) {
        self.init(
            pathGuard: pathGuard, log: log, actions: [.trash: TrashAction(trash: trash), .delete: DeleteAction()],
            runningApps: runningApps, toolAction: ToolAction(runner: toolRunner))
    }

    /// An executor with `actions`, one per method it can act on. Tests pass actions of their own.
    package init(
        pathGuard: PathGuard, log: any RecordLog, actions: [ActionMethod: any PlanAction],
        runningApps: any RunningApps = StubRunningApps(), toolAction: ToolAction? = nil
    ) {
        self.pathGuard = pathGuard
        self.log = log
        self.actions = actions
        self.runningApps = runningApps
        self.toolAction = toolAction
    }

    /// Runs `plan` and returns one outcome per item, in plan order.
    public func run(_ plan: Plan) async -> RunReport {
        let loop = RunLoop(log: log, logger: Logger(tool: plan.tool))
        let results = await loop.run(plan.items) { item in
            let logged = LoggedItem(
                run: plan.run, tool: plan.tool, operation: HistoryRecord.Operation(item.method),
                path: item.target.description,
                tier: item.tier, bytes: item.allocatedSize)
            return RunLoop.Step(logged: logged) {
                await act(on: item, allowedRoots: plan.allowedRoots, requiresRule: plan.requiresRule)
            }
        }
        return RunReport(run: plan.run, outcomes: zip(plan.items, results).map { ItemOutcome(item: $0, result: $1) })
    }

    /// Re-validates the Tool `item`, which names no file, and runs its `command` (SAF-004, SAF-008, SAF-010).
    ///
    /// The item must still be the one its rule describes, and the tool must still be there (DEV-002); a command with
    /// no rule behind it is never run, so only a rule's documented command can reach a tool (D-114).
    private func actOnCommand(_ item: PlannedItem, _ command: ToolCommand) async -> Acted<ItemOutcome.SkipReason> {
        guard item.method == .tool, let toolAction else { return Acted(.skipped(.unsupportedMethod(item.method))) }
        guard let match = item.ruleMatch,
            match.rule.detection.isAvailable,
            match.rule.accepts(item.target, tier: item.tier, method: item.method, scope: item.scope)
        else { return Acted(.skipped(.ruleChanged)) }
        if Task.isCancelled { return Acted(.skipped(.cancelled)) }
        if runningApps.firstRunning(of: item.apps) != nil { return Acted(.skipped(.appRunning)) }
        return await toolAction.act(command: command)
    }

    /// Re-validates `item` and hands it to the action for its method (SAF-004, SAF-008).
    package func act(on item: PlannedItem, allowedRoots: [URL], requiresRule: Bool = false) async -> Acted<
        ItemOutcome.SkipReason
    > {
        // `Plan` refuses such an item too; checking again keeps SAF-004 in the executor, next to the actions.
        guard item.tier.allows(item.method) else { return Acted(.skipped(.notAllowed(item.method))) }
        if case .command(let command) = item.target { return await actOnCommand(item, command) }
        guard let action = actions[item.method] else { return Acted(.skipped(.unsupportedMethod(item.method))) }
        guard let url = item.url, let snapshot = item.snapshot else {
            return Acted(.skipped(.unsupportedMethod(item.method)))
        }
        let target: URL
        do {
            target = try pathGuard.validate(url, allowedRoots: allowedRoots)
        } catch .notReadable {
            // A folder Shuck may not read is reported as macOS's privacy protection hiding it (SAF-012).
            return Acted(.skipped(.notAccessible))
        } catch {
            return Acted(.skipped(.rejected(error)))
        }
        // Stop takes effect while a large folder is measured, not only before the next item (SAF-014).
        switch ItemSnapshot.check(target, while: { !Task.isCancelled }) {
        case .found(let current) where snapshot.matches(current):
            if let identity = item.identity, FileIdentity.read(target) != identity {
                return Acted(.skipped(.replaced))
            }
            if let match = item.ruleMatch {
                guard match.rule.detection.isAvailable,
                    match.rule.accepts(.path(target), tier: item.tier, method: item.method, scope: item.scope)
                else { return Acted(.skipped(.ruleChanged)) }
                if item.method == .delete {
                    guard let modified = match.modified else { return Acted(.skipped(.ruleChanged)) }
                    guard RuleMatch.modificationDate(at: target) == modified else {
                        return Acted(.skipped(.modifiedSinceScan))
                    }
                }
            } else if item.method == .delete || requiresRule {
                // `Plan` refuses such an item too; checking again keeps D-132 and D-163 next to the actions.
                return Acted(.skipped(.ruleChanged))
            }
            // An item whose date the scan could not read is skipped too: nothing shows it is unchanged (D-132).
            guard let modified = item.modified, ModificationDate.read(at: target, scope: item.scope) == modified else {
                return Acted(.skipped(.modifiedSinceScan))
            }
            // Asked last, just before acting, since measuring a large folder can take a while (SAF-009).
            if runningApps.firstRunning(of: item.apps) != nil { return Acted(.skipped(.appRunning)) }
            return await action.act(on: item, at: target)
        case .found(let current): return Acted(.skipped(.changed(current)))
        case .missing: return Acted(.skipped(.missing))
        case .notAccessible: return Acted(.skipped(.notAccessible))
        case .stopped: return Acted(.skipped(.cancelled))
        }
    }
}

/// What a run does to an item of one method, once the item has passed re-validation: ``TrashAction`` and
/// ``DeleteAction`` now, and M3 adds Launchctl (TD-04). Tool items name no file, so ``ToolAction`` is not one.
package protocol PlanAction: Sendable {
    /// Acts on `item`, at `target`, the path the guard returned for it, and says what it did.
    func act(on item: PlannedItem, at target: URL) async -> Acted<ItemOutcome.SkipReason>
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
        /// Another file of the same type and about the same size is at the item's path now, such as an installer
        /// downloaded again (SAF-008, D-103).
        case replaced
        /// The target or detection no longer matches the cleanup rule reviewed, or a Delete item has no rule (D-100,
        /// D-132).
        case ruleChanged
        /// The item's modification date differs from the one its scan read, or the scan could not read one (SAF-008,
        /// D-105, D-132).
        case modifiedSinceScan
        /// One of the item's apps was running just before acting (SAF-009, D-110).
        case appRunning
        /// The path guard rejects the item now (SAF-007, SAF-008).
        case rejected(PathGuardError)
        /// The run was cancelled before this item, or while it was re-validated (SAF-014).
        case cancelled
        /// The history log could not be written, so the run stopped (SAF-005).
        case historyUnavailable
        /// The executor has no action for the item's method yet (D-89).
        case unsupportedMethod(ActionMethod)
        /// The tool's executable is gone, or is not where tools may be found (DEV-002, D-114).
        case toolUnavailable(ToolRunner.Unavailable)
        /// The item's tier does not allow its method, as "Your data" is never deleted permanently (SAF-004). `Plan`
        /// refuses such an item, so only a plan built some other way could have one.
        case notAllowed(ActionMethod)

        /// The reason's stable code, which the history log records (D-88).
        public var code: SkipCode {
            switch self {
            case .missing: .missing
            case .notAccessible: .notAccessible
            case .changed: .changed
            case .replaced: .replaced
            case .ruleChanged: .ruleChanged
            case .modifiedSinceScan: .modifiedSinceScan
            case .appRunning: .appRunning
            case .rejected: .rejected
            case .cancelled: .cancelled
            case .historyUnavailable: .historyUnavailable
            case .unsupportedMethod: .unsupportedMethod
            case .notAllowed: .notAllowed
            case .toolUnavailable: .toolUnavailable
            }
        }

        /// The text the history log records: the code, and after a colon what re-validation found (D-88).
        public var logged: String {
            switch self {
            case .changed(let current): code.logged(current.logged)
            case .rejected(let error): code.logged(error.logged)
            case .unsupportedMethod(let method), .notAllowed(let method): code.logged(method.rawValue)
            case .toolUnavailable(let unavailable): code.logged(unavailable.rawValue)
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
