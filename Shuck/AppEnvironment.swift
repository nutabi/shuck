import Foundation
import ShuckExecution
import ShuckKit

/// Where the app scans and acts, and with which settings: the real home folder and Trash, or a UI test's fixture root
/// (NFR-QA-002).
nonisolated struct AppEnvironment {
    let context: ScanContext
    /// Where "Move to Trash" puts items: the user's Trash, or `.Trash` inside a UI test's fixture root, so tests never
    /// touch the real one (D-47, D-63).
    let trash: any Trash
    let largeFiles: LargeFiles
    let oldFiles: OldFiles

    /// The launch argument UI tests pass, followed by the fixture root's path. Release builds ignore it.
    static let fixtureRootArgument = "-ShuckFixtureRoot"
    /// The thresholds in `UserDefaults` (SET-002, SET-004): Large Files' minimum size in bytes, Old Files' period in
    /// months and its minimum size in bytes. Settings gets controls in M5; until then, a launch argument such as
    /// `-OldFilesPeriodMonths 3` overrides a value without storing it.
    static let largeFilesMinimumSizeKey = "LargeFilesMinimumSize"
    static let oldFilesPeriodKey = "OldFilesPeriodMonths"
    static let oldFilesMinimumSizeKey = "OldFilesMinimumSize"

    /// Reads the stored value for a key, if any.
    typealias Settings = (String) -> Any?

    static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// A fixture-root argument the app refuses. The app stops instead of falling back to the real home folder.
    struct RejectedFixtureRoot: Error, CustomStringConvertible {
        let path: String
        var description: String { "Not a fixture root the test harness made: \(path)" }
    }

    /// - Parameters:
    ///   - arguments: The process's launch arguments.
    ///   - settings: Reads the stored thresholds, such as ``largeFilesMinimumSizeKey``.
    ///   - debugBuild: Whether the fixture-root argument counts.
    /// - Throws: ``RejectedFixtureRoot`` if a debug build gets a fixture-root argument it does not accept.
    init(
        arguments: [String], settings: Settings, debugBuild: Bool = isDebugBuild,
        appBundle: URL = Bundle.main.bundleURL
    ) throws(RejectedFixtureRoot) {
        if let root = try Self.fixtureRoot(in: arguments, debugBuild: debugBuild) {
            // The engine tests' configuration (D-41): only the temporary folder's /private prefix is left out.
            let protection = PathGuardConfiguration(
                home: root, systemLocations: PathGuardConfiguration.systemLocations.filter { $0 != "/private" },
                appBundle: appBundle, userExclusions: [])
            context = ScanContext(home: root, protection: protection)
            trash = FolderTrash(folder: root.appending(path: ".Trash"))
        } else {
            // The ownership map compares paths with symlinks resolved (D-53).
            let home = URL.homeDirectory.resolvingSymlinksInPath()
            context = ScanContext(
                home: home, protection: .production(home: home, appBundle: appBundle, userExclusions: []))
            trash = SystemTrash()
        }
        largeFiles = LargeFiles(
            minimumSize: Self.number(settings(Self.largeFilesMinimumSizeKey)) ?? LargeFiles.defaultMinimumSize)
        // A period of 0 months would list every file, however recently opened.
        let months = Self.number(settings(Self.oldFilesPeriodKey)).flatMap { $0 > 0 ? Int($0) : nil }
        oldFiles = OldFiles(
            periodMonths: months ?? OldFiles.defaultPeriodMonths,
            minimumSize: Self.number(settings(Self.oldFilesMinimumSizeKey)) ?? OldFiles.defaultMinimumSize)
    }

    /// Moves a plan's items to the Trash, off the main actor, and logs every step in the history log inside the home
    /// folder (SAF-005, SAF-011).
    /// - Throws: ``HistoryError`` if the log cannot be opened. Then nothing moves.
    @concurrent
    func run(_ plan: Plan) async throws(HistoryError) -> RunReport {
        let log = try HistoryLog(folder: HistoryLog.folder(home: context.home))
        let executor = TrashExecutor(pathGuard: PathGuard(configuration: context.protection), log: log, trash: trash)
        return await executor.run(plan)
    }

    /// Reads the history log inside the home folder, off the main actor, and groups it into runs, newest first
    /// (HIS-002). A missing log has no runs.
    @concurrent
    func loadHistory() async throws(HistoryError) -> HistoryModel.History {
        let contents = try HistoryLog.read(folder: HistoryLog.folder(home: context.home))
        return HistoryModel.History(
            runs: contents.runs().reversed(), unreadableLineCount: contents.unreadableLines.count)
    }

    /// The fixture root after ``fixtureRootArgument`` in a debug build, or `nil` if there is none.
    ///
    /// Only a folder the test harness creates is accepted: `ShuckFixtures/<UUID>` in the temporary folder, which is
    /// `/private/var/folders/…` for a test process, or the sandboxed UI test runner's container
    /// (`~/Library/Containers/<name>.xctrunner/Data/tmp`). Anything else throws, so a debug build is never pointed at
    /// real data by mistake.
    static func fixtureRoot(in arguments: [String], debugBuild: Bool) throws(RejectedFixtureRoot) -> URL? {
        guard debugBuild, let index = arguments.firstIndex(of: fixtureRootArgument) else { return nil }
        guard index + 1 < arguments.count else { throw RejectedFixtureRoot(path: "") }
        let root = URL(filePath: arguments[index + 1], directoryHint: .isDirectory).resolvingSymlinksInPath()
        let parts = root.pathComponents
        guard parts.count > 2, parts[parts.count - 2] == "ShuckFixtures",
            UUID(uuidString: parts[parts.count - 1]) != nil
        else { throw RejectedFixtureRoot(path: root.path) }
        let temporary = Array(parts.dropLast(2))
        let isProcessTemporary = temporary.starts(with: ["/", "private", "var", "folders"])
        // …/Library/Containers/<name>.xctrunner/Data/tmp
        let tail = Array(temporary.suffix(5))
        let isRunnerTemporary =
            tail.count == 5 && tail[0] == "Library" && tail[1] == "Containers" && tail[2].hasSuffix(".xctrunner")
            && tail[3] == "Data" && tail[4] == "tmp"
        guard isProcessTemporary || isRunnerTemporary else { throw RejectedFixtureRoot(path: root.path) }
        return root
    }

    /// A stored number that is not negative, or `nil` if there is none or it is not one. The caller then uses the
    /// default.
    static func number(_ setting: Any?) -> Int64? {
        let value: Int64? =
            switch setting {
            case let number as NSNumber: number.int64Value
            // A launch argument such as `-LargeFilesMinimumSize 1048576` arrives as a string.
            case let text as String: Int64(text)
            default: nil
            }
        guard let value, value >= 0 else { return nil }
        return value
    }
}
