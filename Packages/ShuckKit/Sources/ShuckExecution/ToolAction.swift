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

    /// Runs `command` for an item that re-validation has passed. If the item has a `folder` it is sized from, Shuck
    /// measures the folder just before the command and again after it ends with exit 0, and reports the difference,
    /// at least 0, as what was removed (DEV-003, D-184). No output of the tool is read to get it (R-07). When either
    /// measurement fails or the run is stopped, there is no measurement and the scan's estimate stands.
    package func act(command: ToolCommand, measuring folder: URL? = nil) async -> Acted<ItemOutcome.SkipReason> {
        let executable: URL
        switch runner.locate(command) {
        case .success(let url): executable = url
        case .failure(let unavailable): return Acted(.skipped(.toolUnavailable(unavailable)))
        }
        let before = folder.flatMap(Self.measure)
        let run = await runner.run(command, at: executable)
        let acted = Self.acted(run, command: command)
        guard let before, case .exited(0) = run.ending, let after = folder.flatMap(Self.measure) else { return acted }
        return Acted(acted.result, detail: acted.detail, bytes: max(0, before - after))
    }

    /// The allocated size of `folder`, or `nil` if it cannot be measured now or the run is stopped meanwhile.
    private static func measure(_ folder: URL) -> Int64? {
        ItemSnapshot.read(folder, while: { !Task.isCancelled })?.allocatedSize
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
                domain: "ShuckToolTimeout", code: seconds,
                message: "no end within \(seconds) seconds; stopped")
        case .stopped:
            failure = ActionError(
                domain: "ShuckToolStopped", code: Int(SIGTERM), message: "stopped by the user")
        }
        return Acted(.failed(failure), detail: failure.logged + (output ?? ""))
    }
}
