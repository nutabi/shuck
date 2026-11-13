import Foundation
import ShuckKit

/// What `launchctl` is asked to do to one job. `bootout` and `bootstrap` exist now; STA-005's Disable (bootout, then
/// disable) and Enable (enable, then bootstrap) add `disable` and `enable` in M4, each with its arguments in this one
/// place. The words live here because only `ShuckExecution` may name them (SAF-017).
package enum LaunchctlOperation: Equatable, Sendable {
    /// Unloads the job from the user's GUI domain, which stops it if it runs (D-26).
    case bootout
    /// Loads the job from its property list into the user's GUI domain, which undoes a `bootout`. It does not run
    /// `enable`: `launchctl` says a disabled service cannot be loaded until it is enabled, so a job the user disabled
    /// stays disabled and fails to load, as it should (APP-011, D-199).
    case bootstrap

    /// The words of the subcommand and its target. `domain` is `gui/<uid>`; `label` names the job and `plist` is its
    /// property list.
    func arguments(domain: String, label: String, plist: URL) -> [String] {
        switch self {
        case .bootout: ["bootout", "\(domain)/\(label)"]
        case .bootstrap: ["bootstrap", domain, plist.path]
        }
    }

    /// The word the result record starts its detail with.
    var name: String {
        switch self {
        case .bootout: "bootout"
        case .bootstrap: "bootstrap"
        }
    }
}

/// The job label a LaunchAgent's property list names, and where Shuck reads it (APP-011, HIS-002).
enum LaunchAgentLabel {
    /// Property lists larger than this are not read; a LaunchAgent's is a few hundred bytes.
    private static let sizeLimit = 1 << 20

    /// The `Label` of the property list at `url`, or `nil` if it is not a readable property list with a usable one.
    /// A label that is empty, or has a `/` or a control character, is not usable: it would not name one job in a
    /// service target.
    static func read(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            (attributes[.size] as? Int ?? .max) <= sizeLimit,
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let label = plist["Label"] as? String,
            !label.isEmpty, !label.contains("/"),
            !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return label
    }
}

/// Unloads a LaunchAgent, or with ``LaunchctlOperation/bootstrap`` loads it: the action for Launchctl items and for
/// Restore's re-enable (APP-011, HIS-005, STA-005, SAF-006, D-26).
///
/// The item targets the agent's property list, so the path guard, the allowed roots and the snapshot and date checks
/// apply to it as to any file. The job label is read from that property list just before acting, after re-validation,
/// and is never taken from the scan. The domain is the user's own, `gui/<uid>`, so no administrator rights are used
/// (NFR-SEC-001).
///
/// The action asks `launchctl print` whether the job is loaded and decides from its exit status only, never from
/// its output (R-07): 0 is loaded, ``notLoadedStatus`` is not loaded, anything else is a failure, as the answer is
/// unknown. A job that is not loaded needs no `bootout`, so the item is done with nothing unloaded, and the plist's
/// own Trash item moves it directly (APP-011). A loaded job gets `bootout`, and any status but 0 fails the item
/// (SAF-011). `bootstrap` is the reverse: a job that is loaded already is done, and one that is not gets `bootstrap`.
/// Both run through ``ToolRunner``, the only code that starts a subprocess (D-82), so a runner confined to
/// a fixture root can never reach the real `launchctl` (SAF-016).
package struct LaunchctlAction: PlanAction {
    /// The exit status of `launchctl print` for a job launchd does not know. Agent choice (D-197), from
    /// how `launchctl print gui/<uid>/<missing>` behaves; the owner checks it on a real Mac. It is the only place
    /// that maps a status to "not loaded".
    package static let notLoadedStatus: Int32 = 113

    let runner: ToolRunner
    let operation: LaunchctlOperation
    /// The folder `bin/launchctl` is under: `/` in the app, the fixture root in a fixture-root run.
    let toolRoot: URL
    let uid: uid_t

    /// An action that runs `launchctl` found under `runner`'s one root, as the app's fixture-root mode confines
    /// tools, or under `/` when the runner finds tools anywhere. `uid` is the user's, `getuid()`, in the app.
    package init(runner: ToolRunner, operation: LaunchctlOperation = .bootout, uid: uid_t = getuid()) {
        self.runner = runner
        self.operation = operation
        self.toolRoot = runner.executableRoots?.first ?? URL(filePath: "/")
        self.uid = uid
    }

    /// The text the history log records as the item's path: the job label read from its property list, as HIS-002
    /// says, or the property list's path when it has none, so the intent is still recorded. Read before the intent
    /// record is written, so it is only the log's name for the item; ``act(on:at:)`` reads the label again, after
    /// re-validation, and uses that one (D-197).
    static func loggedPath(for item: PlannedItem) -> String {
        item.url.flatMap { LaunchAgentLabel.read(at: $0) } ?? item.target.description
    }

    package func act(on item: PlannedItem, at target: URL) async -> Acted<ItemOutcome.SkipReason> {
        guard let label = LaunchAgentLabel.read(at: target) else {
            return Acted(
                .failed(
                    ActionError(domain: "ShuckLaunchctl", code: 1, message: "the property list has no usable Label")))
        }
        return await perform(label: label, plist: target)
    }

    /// Does ``operation`` to the job `label`, whose property list is `plist`, if its loaded state calls for it: a
    /// loaded job is booted out, and a job that is not loaded is bootstrapped; in the other state the item is done
    /// with nothing to do. The caller has validated `plist` and read `label` from it.
    package func perform(label: String, plist: URL) async -> Acted<ItemOutcome.SkipReason> {
        let domain = "gui/\(uid)"
        let serviceTarget = "\(domain)/\(label)"
        let loaded: Bool
        switch await run(["print", serviceTarget]) {
        case .ended(let acted): return acted
        case .ran(let ran, let command):
            switch ran.ending {
            case .exited(0): loaded = true
            case .exited(Self.notLoadedStatus): loaded = false
            // Whether the job is loaded is unknown, so nothing is changed and the item fails (SAF-011).
            default: return Self.failed(ran, command: command, step: "print", target: serviceTarget)
            }
        }
        guard loaded == (operation == .bootout) else {
            return Acted(.done(nil), detail: "\(loaded ? "already loaded" : "not loaded"): \(serviceTarget)")
        }
        switch await run(operation.arguments(domain: domain, label: label, plist: plist)) {
        case .ended(let acted): return acted
        case .ran(let ran, let command):
            if case .exited(0) = ran.ending {
                return Acted(.done(nil), detail: "\(operation.name) \(serviceTarget): exit 0")
            }
            return Self.failed(ran, command: command, step: operation.name, target: serviceTarget)
        }
    }

    /// Runs `launchctl` with `arguments`, or says why it cannot: not found, or the run was stopped.
    /// What one `launchctl` call came to: it ran and ended, or it could not run and the item ends there.
    private enum Call {
        case ran(ToolRun, ToolCommand)
        case ended(Acted<ItemOutcome.SkipReason>)
    }

    private func run(_ arguments: [String]) async -> Call {
        let command: ToolCommand
        do {
            command = try ToolCommand(
                executable: toolRoot.appending(path: "bin/launchctl").path, arguments: arguments,
                environment: ["PATH": "/usr/bin:/bin"], timeout: 30)
        } catch {
            return .ended(Acted(.failed(ActionError(domain: "ShuckLaunchctl", code: 2, message: "\(error)"))))
        }
        switch runner.locate(command) {
        case .failure(let unavailable): return .ended(Acted(.skipped(.toolUnavailable(unavailable))))
        case .success(let executable):
            let ran = await runner.run(command, at: executable)
            if case .neverStarted = ran.ending { return .ended(Acted(.skipped(.cancelled))) }
            return .ran(ran, command)
        }
    }

    /// The failed outcome of `ran`, with its exit status or signal in the error, and which step it was (SAF-011).
    private static func failed(
        _ ran: ToolRun, command: ToolCommand, step: String, target: String
    ) -> Acted<ItemOutcome.SkipReason> {
        let acted = ToolAction.acted(ran, command: command)
        guard case .failed(let error) = acted.result else { return acted }
        return Acted(.failed(error), detail: "\(step) \(target): " + error.logged)
    }
}
