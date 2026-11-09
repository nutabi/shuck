import Foundation
import ShuckKit

/// Runs a tool item's command: the action for Tool items, the only way to clean data a tool owns (SAF-010, DEV-004).
///
/// The item's command was reviewed in the plan and is run exactly as reviewed. It does not touch the path guard, as it
/// names no file to act on; ``ToolRunner`` finds its executable and starts it without a shell. The result record keeps
/// the exit status and the end of the tool's output, whether the tool succeeded or not (SAF-006, DEV-004). Tool runs
/// are not restorable.
package struct ToolAction: Sendable {
    let runner: ToolRunner

    package init(runner: ToolRunner) {
        self.runner = runner
    }

    /// Runs `command` for an item that re-validation has passed.
    package func act(command: ToolCommand) async -> Acted<ItemOutcome.SkipReason> {
        let executable: URL
        switch runner.locate(command) {
        case .success(let url): executable = url
        case .failure(let unavailable): return Acted(.skipped(.toolUnavailable(unavailable)))
        }
        let run = await runner.run(command, at: executable)
        return Self.acted(run, command: command)
    }

    /// The outcome of `run`, and what its result record says: the end, and after "; output: " the tool's last output.
    static func acted(_ run: ToolRun, command: ToolCommand) -> Acted<ItemOutcome.SkipReason> {
        let output = run.output.map { "; output: " + (run.outputWasCut ? "…" : "") + $0 }
        let failure: ActionError
        switch run.ending {
        case .exited(0):
            return Acted(.done(nil), detail: "exit 0" + (output ?? ""))
        case .neverStarted:
            return Acted(.skipped(.cancelled))
        case .launchFailed(let error):
            return Acted(.failed(error))
        case .exited(let status):
            failure = ActionError(domain: "ShuckToolExit", code: Int(status), message: "exit status \(status)")
        case .signaled(let signal):
            failure = ActionError(domain: "ShuckToolSignal", code: Int(signal), message: "ended by signal \(signal)")
        case .timedOut:
            let seconds = Int(command.timeout.rounded(.up))
            failure = ActionError(
                domain: "ShuckToolTimeout", code: seconds, message: "no end within \(seconds) seconds; stopped")
        case .stopped:
            failure = ActionError(domain: "ShuckToolStopped", code: Int(SIGTERM), message: "stopped by the user")
        }
        return Acted(.failed(failure), detail: failure.logged + (output ?? ""))
    }
}
