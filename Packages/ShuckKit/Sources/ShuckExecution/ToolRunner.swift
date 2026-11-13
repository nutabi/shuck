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
/// started directly with `posix_spawn`, never through a shell, with exactly the command's environment, no standard
/// input, and the root folder as its working folder. It is the only code in Shuck that starts a subprocess (D-82).
///
/// The process leads a process group of its own, and what the tool starts in turn joins that group. The process runs
/// until it ends, its timeout passes or the calling task is cancelled. Then the whole group gets SIGTERM, and SIGKILL
/// if any of it is still there after ``killGrace``, so a stopped tool leaves nothing it started running (SAF-014,
/// D-NEXT-pgroup). A process that makes a group of its own, as a daemon does, is out of reach. What the tool writes is
/// kept to the last ``outputLimit`` bytes, so a chatty tool cannot fill the history log or memory.
///
/// `executableRoots` is `nil` in the release build, where a tool is wherever it is installed. In a UI test's fixture
/// root it is that root, and a tool is found only inside it, so a test can never run a real tool (SAF-016, D-114).
public struct ToolRunner: Sendable {
    let executableRoots: [URL]?
    let outputLimit: Int
    let killGrace: Duration
    /// Runs between storing the process and starting it, so a test can stop a run in that window (R-05).
    let beforeLaunch: (@Sendable () -> Void)?
    /// Runs when the process has ended, before the run notes that it has, so a test can stop a run in that window
    /// (#179).
    let afterExit: (@Sendable () -> Void)?

    /// A runner that finds tools anywhere (`nil`), or only inside `executableRoots`, with symlinks resolved.
    public init(executableRoots: [URL]?) {
        self.init(executableRoots: executableRoots, outputLimit: 2048, killGrace: .seconds(5))
    }

    package init(
        executableRoots: [URL]?, outputLimit: Int, killGrace: Duration, beforeLaunch: (@Sendable () -> Void)? = nil,
        afterExit: (@Sendable () -> Void)? = nil
    ) {
        self.beforeLaunch = beforeLaunch
        self.afterExit = afterExit
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
        let execution = Execution(
            limit: outputLimit, grace: killGrace, beforeLaunch: beforeLaunch, afterExit: afterExit)
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

/// One process group, from its start to its end. The process, its group and the output reader belong to it; `state`
/// guards what the cancellation and timeout handlers share with the run.
private final class Execution: @unchecked Sendable {
    private struct State {
        /// The process, which leads its own group, so this is the group's ID too. `nil` until it has been started.
        var process: pid_t?
        /// Whether `process` is set, so the process exists and can be signalled (R-05).
        var launched = false
        var stop: ToolRun.Ending?
        /// Whether Shuck signalled the process while it was still running. Only then does ``stop`` say how it ended: a
        /// process that had already exited when the stop came ended by itself (#179).
        var signalled = false
        var finished = false
    }

    private let state = Mutex(State())
    private let limit: Int
    private let grace: Duration
    private let beforeLaunch: (@Sendable () -> Void)?
    private let afterExit: (@Sendable () -> Void)?
    /// Output is read on this queue only, so its order is the order the process wrote it in.
    private let queue = DispatchQueue(label: "me.nutabi.shuck.tool-output")
    private let output = Mutex(Output())

    private struct Output {
        var bytes = Data()
        var cut = false
    }

    init(limit: Int, grace: Duration, beforeLaunch: (@Sendable () -> Void)?, afterExit: (@Sendable () -> Void)?) {
        self.limit = limit
        self.grace = grace
        self.beforeLaunch = beforeLaunch
        self.afterExit = afterExit
    }

    /// Asks the process group to end, for `reason`: SIGTERM now, SIGKILL after the grace period if it is still running.
    /// The first reason stands. Nothing happens once the process has ended, and a process that has not started is not
    /// signalled: ``run(_:at:)`` ends it as soon as it has started. A process that has already exited is not signalled
    /// either, and `reason` then does not replace its own ending (#179).
    func stop(_ reason: ToolRun.Ending) {
        let process: pid_t? = state.withLock { state in
            guard !state.finished, state.stop == nil else { return nil }
            state.stop = reason
            return state.launched ? state.process : nil
        }
        guard let process else { return }
        terminate(process)
    }

    /// Sends SIGTERM to the group `process` leads if the process has not exited yet, and notes that it did. A process
    /// that has exited, even if it has not been reaped yet, is left alone, so its own exit status stands (#179).
    private func terminate(_ process: pid_t) {
        let sent = state.withLock { state in
            guard !state.finished, !Self.hasExited(process) else { return false }
            state.signalled = true
            kill(-process, SIGTERM)
            return true
        }
        guard sent else { return }
        let grace = grace
        Task {
            try? await Task.sleep(for: grace)
            // The state says whether the process ended meanwhile, so its number is never signalled once it has. Any
            // process of the group left after the leader has ended is killed by ``run(_:at:)`` itself.
            state.withLock { state in
                if !state.finished { kill(-process, SIGKILL) }
            }
        }
    }

    /// Whether the process `id` has exited, whether or not it has been reaped yet. `WNOWAIT` leaves it to the reaper,
    /// so its exit status is still there to read.
    private static func hasExited(_ id: pid_t) -> Bool {
        var info = siginfo_t()
        while true {
            let result = waitid(P_PID, id_t(id), &info, WEXITED | WNOHANG | WNOWAIT)
            if result == 0 { return info.si_pid != 0 }
            // Not ours to wait for any more (`ECHILD`): it has been reaped, so it has exited.
            if errno != EINTR { return true }
        }
    }

    /// Whether any process of the group `group` is left, zombies included.
    private static func groupExists(_ group: pid_t) -> Bool {
        kill(-group, 0) == 0 || errno != ESRCH
    }

    func run(_ command: ToolCommand, at executable: URL) async -> ToolRun {
        var pipeEnds: [Int32] = [0, 0]
        guard pipe(&pipeEnds) == 0 else {
            return ToolRun(ending: .launchFailed(ActionError(errno: errno)), output: nil, outputWasCut: false)
        }
        let (reading, writing) = (pipeEnds[0], pipeEnds[1])
        // Neither end may leak into a process started elsewhere meanwhile.
        for end in [reading, writing] { _ = fcntl(end, F_SETFD, FD_CLOEXEC) }
        _ = fcntl(reading, F_SETFL, fcntl(reading, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: reading, queue: queue)
        source.setEventHandler { [self] in
            if readAvailable(reading) { source.cancel() }
        }
        // The reading end closes only once the source is cancelled, so it is never closed under a running handler.
        source.setCancelHandler { close(reading) }
        source.resume()

        let ending: ToolRun.Ending = await withCheckedContinuation { continuation in
            // A stop requested before the process starts ends the run without starting it.
            let proceed = state.withLock { $0.stop == nil }
            guard proceed else {
                state.withLock { $0.finished = true }
                close(writing)
                source.cancel()
                continuation.resume(returning: .neverStarted)
                return
            }
            beforeLaunch?()
            let process: pid_t
            switch Self.spawn(command, at: executable, output: writing) {
            case .success(let id): process = id
            case .failure(let error):
                state.withLock { $0.finished = true }
                close(writing)
                source.cancel()
                continuation.resume(returning: .launchFailed(error))
                return
            }
            // Only the process holds the writing end now, so the pipe ends when it and its children close it.
            close(writing)
            // A stop that came before the process started signalled nothing, so it is ended now.
            let early = state.withLock { state in
                state.process = process
                state.launched = true
                return state.stop
            }
            if early != nil { terminate(process) }
            // A thread of its own waits for the end, as a wait on the pool's threads or the main actor could block
            // them for as long as the tool runs.
            Thread.detachNewThread { [self] in
                Self.waitForExit(process)
                afterExit?()
                // A stop that signalled nothing found the process already ended, so its own ending stands (#179).
                let requested = state.withLock { state in
                    state.finished = true
                    return state.signalled ? state.stop : nil
                }
                let status = Self.reap(process)
                // Everything the process wrote is already in the pipe, so reading until it is empty gets all of it
                // even when a process it started still holds the pipe open.
                queue.async { [self] in
                    _ = readAvailable(reading)
                    source.cancel()
                    continuation.resume(returning: requested ?? status)
                }
            }
        }

        // A tool that was stopped has its whole group signalled: wait for what the leader left to end, and kill it
        // once the grace period has passed (SAF-014, #127).
        if let process = state.withLock({ $0.signalled ? $0.process : nil }) {
            await Self.endGroup(process, grace: grace)
        }
        let captured = output.withLock { $0 }
        return ToolRun(ending: ending, output: Self.text(captured.bytes), outputWasCut: captured.cut)
    }

    /// Starts `command` at `executable` in a group of its own (`POSIX_SPAWN_SETPGROUP` with group 0, so the process
    /// leads a group named after it), so that a signal to the group reaches every process the tool starts, unless one
    /// leaves the group itself. The process gets exactly the command's environment, no standard input, `output` as
    /// its standard output and error, the root folder as its working folder and default signal handling, and no other
    /// open file (`POSIX_SPAWN_CLOEXEC_DEFAULT`). The arguments are an array, never a shell line (NFR-SEC-004).
    private static func spawn(
        _ command: ToolCommand, at executable: URL, output: Int32
    ) -> Result<pid_t, ActionError> {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return .failure(ActionError(errno: errno)) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return .failure(ActionError(errno: errno)) }
        defer { posix_spawnattr_destroy(&attributes) }

        var allSignals = sigset_t()
        var noSignals = sigset_t()
        sigfillset(&allSignals)
        sigemptyset(&noSignals)
        let flags =
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK
        let prepared =
            [
                posix_spawnattr_setflags(&attributes, Int16(flags)),
                posix_spawnattr_setpgroup(&attributes, 0),
                posix_spawnattr_setsigdefault(&attributes, &allSignals),
                posix_spawnattr_setsigmask(&attributes, &noSignals),
                posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0),
                posix_spawn_file_actions_adddup2(&actions, output, 1),
                posix_spawn_file_actions_adddup2(&actions, output, 2),
                posix_spawn_file_actions_addchdir(&actions, "/"),
            ].first { $0 != 0 }
        if let prepared { return .failure(ActionError(errno: prepared)) }

        let arguments = [executable.path] + command.arguments
        let environment = command.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var argv = arguments.map { strdup($0) } + [nil]
        var envp = environment.map { strdup($0) } + [nil]
        defer {
            for string in argv + envp { free(string) }
        }
        var process: pid_t = 0
        let result = posix_spawn(&process, executable.path, &actions, &attributes, &argv, &envp)
        return result == 0 ? .success(process) : .failure(ActionError(errno: result))
    }

    /// Blocks until the process `id` has exited, without reaping it.
    private static func waitForExit(_ id: pid_t) {
        var info = siginfo_t()
        while waitid(P_PID, id_t(id), &info, WEXITED | WNOWAIT) != 0 {
            // Anything but a signal interrupting the wait means there is nothing to wait for.
            if errno != EINTR { return }
        }
    }

    /// Reaps the process `id`, and says how it ended: its own exit status, or the signal that ended it.
    private static func reap(_ id: pid_t) -> ToolRun.Ending {
        var status: Int32 = 0
        while waitpid(id, &status, 0) < 0 {
            if errno != EINTR { return .exited(-1) }
        }
        // The status macros are not imported: the low 7 bits are the signal (0 for a normal exit), the next 8 the code.
        let signal = status & 0x7f
        return signal == 0 ? .exited((status >> 8) & 0xff) : .signaled(signal)
    }

    /// Waits for the group to be empty, at most `grace`, then sends SIGKILL to whatever is still in it. The leader has
    /// been reaped, so the group's ID cannot be taken by another process while it has members.
    private static func endGroup(_ group: pid_t, grace: Duration) async {
        let deadline = ContinuousClock.now + grace
        while groupExists(group), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if groupExists(group) { kill(-group, SIGKILL) }
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
