import Dispatch
import Foundation
import ShuckKit
import Synchronization

/// What a tool command did: how it ended, and the tail of what it printed (DEV-004, SAF-006).
package struct ToolRun: Equatable, Sendable {
    package enum Ending: Equatable, Sendable {
        /// The process ended by itself, with this exit status.
        case exited(Int32)
        /// The process was ended by a signal Shuck did not send.
        case signaled(Int32)
        /// The command's timeout passed, so Shuck stopped the process.
        case timedOut
        /// The run was stopped (SAF-014), so Shuck stopped the process.
        case stopped
        /// The run was stopped before the process started, so it never ran.
        case neverStarted
        /// The process could not be started.
        case launchFailed(ActionError)
    }

    package let ending: Ending
    /// The last bytes the process wrote to its standard output and error, as text, without surrounding white space.
    /// `nil` if it wrote nothing.
    package let output: String?
    /// Whether the process wrote more than ``output`` holds.
    package let outputWasCut: Bool
}

/// Runs one tool command as a subprocess (DEV-004, NFR-SEC-004): the command's absolute executable and argument array,
/// started directly with `Process`, never through a shell, with exactly the command's environment, no standard input,
/// and the root folder as its working folder. It is the only code in Shuck that starts a subprocess (D-82).
///
/// The process runs until it ends, its timeout passes or the calling task is cancelled. Then it gets SIGTERM, and
/// SIGKILL if it is still running after ``killGrace``. Only the process Shuck started is signalled, not any process it
/// started in turn. What it writes is kept to the last ``outputLimit`` bytes, so a chatty tool cannot fill the history
/// log or memory.
///
/// `executableRoots` is `nil` in the release build, where a tool is wherever it is installed. In a UI test's fixture
/// root it is that root, and a tool is found only inside it, so a test can never run a real tool (SAF-016, D-114).
public struct ToolRunner: Sendable {
    let executableRoots: [URL]?
    let outputLimit: Int
    let killGrace: Duration

    /// A runner that finds tools anywhere (`nil`), or only inside `executableRoots`, with symlinks resolved.
    public init(executableRoots: [URL]?) {
        self.init(executableRoots: executableRoots, outputLimit: 2048, killGrace: .seconds(5))
    }

    package init(executableRoots: [URL]?, outputLimit: Int, killGrace: Duration) {
        self.executableRoots = executableRoots
        self.outputLimit = outputLimit
        self.killGrace = killGrace
    }

    /// Why a command's executable cannot be run, as the history log records it.
    public enum Unavailable: String, Error, Equatable, Sendable {
        /// Nothing runnable is at the path: missing, a folder, or not executable.
        case notAnExecutable
        /// It is outside the roots tools may be found in.
        case outsideRoots
    }

    /// The executable `command` names, with symlinks resolved, if it can be run here (DEV-002).
    package func locate(_ command: ToolCommand) -> Result<URL, Unavailable> {
        guard let resolved = ResolvedPath.realPath(URL(filePath: command.executable)),
            (try? FileManager.default.attributesOfItem(atPath: resolved.path))?[.type] as? FileAttributeType
                == .typeRegular,
            FileManager.default.isExecutableFile(atPath: resolved.path)
        else { return .failure(.notAnExecutable) }
        if let executableRoots {
            let inside = executableRoots.contains { root in
                let root = ResolvedPath.realPath(root) ?? root
                return Array(resolved.pathComponents.prefix(root.pathComponents.count)) == root.pathComponents
                    && resolved.pathComponents.count > root.pathComponents.count
            }
            guard inside else { return .failure(.outsideRoots) }
        }
        return .success(resolved)
    }

    /// Runs `command` at `executable`, which ``locate(_:)`` returned, and waits for the end.
    package func run(_ command: ToolCommand, at executable: URL) async -> ToolRun {
        let execution = Execution(limit: outputLimit, grace: killGrace)
        let timer = Task {
            if (try? await Task.sleep(for: .seconds(command.timeout))) != nil { execution.stop(.timedOut) }
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await execution.run(command, at: executable)
        } onCancel: {
            execution.stop(.stopped)
        }
    }
}

/// One process, from its start to its end. The process and the output reader belong to it; `state` guards what the
/// cancellation and timeout handlers share with the run.
private final class Execution: @unchecked Sendable {
    private struct State {
        var process: Process?
        var stop: ToolRun.Ending?
        var finished = false
    }

    private let state = Mutex(State())
    private let limit: Int
    private let grace: Duration
    /// Output is read on this queue only, so its order is the order the process wrote it in.
    private let queue = DispatchQueue(label: "me.nutabi.shuck.tool-output")
    private let output = Mutex(Output())

    private struct Output {
        var bytes = Data()
        var cut = false
    }

    init(limit: Int, grace: Duration) {
        self.limit = limit
        self.grace = grace
    }

    /// Asks the process to end, for `reason`: SIGTERM now, SIGKILL after the grace period if it is still running. The
    /// first reason stands. Nothing happens once the process has ended.
    func stop(_ reason: ToolRun.Ending) {
        let process: Process? = state.withLock { state in
            guard !state.finished, state.stop == nil else { return nil }
            state.stop = reason
            return state.process
        }
        guard let process else { return }
        terminate(process)
    }

    private func terminate(_ process: Process) {
        process.terminate()
        let grace = grace
        Task {
            try? await Task.sleep(for: grace)
            // The state says whether the process ended meanwhile, so its number is never signalled once it has.
            state.withLock { state in
                if !state.finished, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    func run(_ command: ToolCommand, at executable: URL) async -> ToolRun {
        let process = Process()
        process.executableURL = executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = URL(filePath: "/")
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [self] in
            if readAvailable(descriptor) { source.cancel() }
        }
        source.resume()

        let ending: ToolRun.Ending = await withCheckedContinuation { continuation in
            process.terminationHandler = { [self] process in
                let requested = state.withLock { state in
                    state.finished = true
                    return state.stop
                }
                // Everything the process wrote is already in the pipe, so reading until it is empty gets all of it
                // even when a process it started still holds the pipe open.
                queue.async { [self] in
                    _ = readAvailable(descriptor)
                    source.cancel()
                    let ending: ToolRun.Ending =
                        requested
                        ?? (process.terminationReason == .uncaughtSignal
                            ? .signaled(process.terminationStatus) : .exited(process.terminationStatus))
                    continuation.resume(returning: ending)
                }
            }
            // The state is set before the process starts, so a stop requested meanwhile ends it as soon as it exists.
            let proceed = state.withLock { state in
                guard state.stop == nil else { return false }
                state.process = process
                return true
            }
            guard proceed else {
                state.withLock { $0.finished = true }
                source.cancel()
                continuation.resume(returning: .neverStarted)
                return
            }
            do {
                try process.run()
            } catch {
                state.withLock { $0.finished = true }
                source.cancel()
                continuation.resume(returning: .launchFailed(ActionError(error)))
                return
            }
            // A stop that came between setting the state and starting the process had no process to end yet.
            let early = state.withLock { $0.stop }
            if early != nil { terminate(process) }
        }

        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
        let captured = output.withLock { $0 }
        return ToolRun(ending: ending, output: Self.text(captured.bytes), outputWasCut: captured.cut)
    }

    /// Reads what is in the pipe now into ``output``, keeping the last `limit` bytes. Returns whether the pipe is at its
    /// end.
    private func readAvailable(_ descriptor: Int32) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                output.withLock { output in
                    output.bytes.append(contentsOf: buffer[..<count])
                    if output.bytes.count > limit {
                        output.bytes = Data(output.bytes.suffix(limit))
                        output.cut = true
                    }
                }
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                // 0 is the end; -1 with EAGAIN only means nothing more to read now.
                return count == 0
            }
        }
    }

    /// The bytes as text; a character cut in two at the start becomes a replacement character, which is dropped.
    private static func text(_ bytes: Data) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("\u{FFFD}")
        return text.isEmpty ? nil : String(text)
    }
}
