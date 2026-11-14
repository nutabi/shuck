import Foundation
import ShuckKit
import os

/// Reads an app's package receipt by asking `pkgutil --file-info-plist <app>` which packages installed it (APP-008,
/// D-200). It is a read-only query: it changes nothing, so it is logged for diagnostics, not in the history log.
///
/// Only the app's own path is passed, as one argument of a fixed command, so no other `pkgutil` verb can be reached
/// from the engine. The output is read whole: a runner that cut it would hand the parser a tail, so a cut result is
/// ``PackageReceiptError/unreadableOutput``. The file list of a package is never asked for, as it can run to
/// megabytes.
public struct PkgutilReceiptReader: PackageReceiptReader {
    private static let outputLimit = 64 * 1024
    private static let timeout: TimeInterval = 10

    let runner: ToolRunner
    /// The folder `usr/sbin/pkgutil` is under: `/` in the app, the fixture root in a fixture-root run.
    let toolRoot: URL
    private let logger = Logger(tool: .applications)

    /// A reader that finds `pkgutil` anywhere (`nil`, as in the release build), or only inside `executableRoots`, as
    /// in a fixture-root run (SAF-016).
    public init(executableRoots: [URL]?) {
        runner = ToolRunner(
            executableRoots: executableRoots, outputLimit: Self.outputLimit, killGrace: .seconds(2))
        toolRoot = executableRoots?.first ?? URL(filePath: "/")
    }

    public func receipts(forAppAt app: URL) async throws(PackageReceiptError) -> [PackageReceipt] {
        let command: ToolCommand
        do {
            // An absolute path never starts with `-`, so `pkgutil` cannot read it as an option.
            guard app.isFileURL, app.path.hasPrefix("/") else { throw PackageReceiptError.toolUnavailable }
            command = try ToolCommand(
                executable: toolRoot.appending(path: "usr/sbin/pkgutil").path,
                arguments: ["--file-info-plist", app.path], environment: ["PATH": "/usr/bin:/bin"],
                timeout: Self.timeout)
        } catch {
            throw .toolUnavailable
        }
        guard case .success(let executable) = runner.locate(command) else {
            logger.error("pkgutil is not available")
            throw .toolUnavailable
        }
        let ran = await runner.run(command, at: executable)
        switch ran.ending {
        case .exited(0): break
        case .exited(let status):
            logger.error("pkgutil ended with status \(status)")
            throw .failed(status)
        case .timedOut:
            logger.error("pkgutil timed out")
            throw .timedOut
        case .stopped, .neverStarted: throw .stopped
        case .signaled(let signal):
            logger.error("pkgutil was ended by signal \(signal)")
            throw .failed(-signal)
        case .launchFailed:
            logger.error("pkgutil could not be started")
            throw .toolUnavailable
        }
        guard !ran.outputWasCut, let output = ran.output else { throw .unreadableOutput }
        return try PackageReceipt.parse(fileInfo: Data(output.utf8))
    }
}
