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
    /// Which apps run now: this Mac's, or in a UI test's fixture root, where Xcode itself runs the tests, only those the
    /// test names, if any (D-110, D-113).
    /// Scans disable a running app's items, and runs skip them (SAF-009).
    let runningApps: any RunningApps
    /// Where a tool command may be found: anywhere on this Mac, or only inside a UI test's fixture root, so a test never
    /// runs a real tool (DEV-004, SAF-016, D-114).
    let toolRunner: ToolRunner
    let largeFiles: LargeFiles
    let oldFiles: OldFiles
    /// Developer Junk with the user's project folders (SET-003). It is rebuilt when the list changes (D-154).
    let developerJunk: DeveloperJunk
    /// Caches & Logs with the way it names an entry's app: Launch Services, or in a UI test's fixture root also the
    /// apps the test says are installed (CAC-009, D-156).
    let cachesAndLogs: CachesAndLogs
    /// The folders the user excluded, which every scan hides and every plan and run refuses (SET-001, D-150).
    let excludedFolders: FolderList
    /// The developer project folders the user chose, which DEV-R06 scans for `node_modules` (SET-003, D-154).
    let projectFolders: FolderList
    /// What scans, plans and runs know about a list of project folders: the ownership map and Developer Junk. Like the
    /// guard's configuration it is rebuilt when the list changes (D-154).
    let makeProjectScope: @Sendable ([URL]) -> ProjectScope
    /// The path guard's configuration for a list of excluded folders. The configuration is rebuilt when the list
    /// changes; it never changes itself (D-150).
    let makeProtection: @Sendable ([URL]) -> PathGuardConfiguration
    /// This build's data folder inside the home folder, which holds its history log: the release build's or the debug
    /// build's, named after its bundle ID (D-70).
    let historyFolder: URL
    /// How long a personal-files scan waits before it starts, so a UI test can stop it (SAF-014). Only a debug build on
    /// a fixture root reads it; otherwise it is `nil`.
    let scanDelay: Duration?
    /// The names of the files and packages a UI test's personal-files scan treats as synced by iCloud, since a fixture
    /// file cannot be (D-137). Only a debug build on a fixture root reads them; otherwise there are none.
    let syncedNames: Set<String>

    /// The launch argument UI tests pass, followed by the fixture root's path. Release builds ignore it.
    static let fixtureRootArgument = "-ShuckFixtureRoot"
    /// The thresholds in `UserDefaults` (SET-002, SET-004): Large Files' minimum size in bytes, Old Files' period in
    /// months and its minimum size in bytes. Settings gets controls in M5; until then, a launch argument such as
    /// `-OldFilesPeriodMonths 3` overrides a value without storing it.
    static let largeFilesMinimumSizeKey = "LargeFilesMinimumSize"
    static let oldFilesPeriodKey = "OldFilesPeriodMonths"
    static let oldFilesMinimumSizeKey = "OldFilesMinimumSize"
    /// ``scanDelay`` in seconds, as a UI test passes it: `-ShuckScanDelaySeconds 2`.
    static let scanDelayKey = "ShuckScanDelaySeconds"
    /// The apps a UI test pretends are running, as bundle IDs separated by commas: `-ShuckRunningApps
    /// com.apple.dt.Xcode`. Only a fixture root reads it (D-113).
    static let runningAppsKey = "ShuckRunningApps"
    /// The apps a UI test pretends are installed, as bundle IDs separated by commas: `-ShuckInstalledApps
    /// com.example.Notes`. Caches & Logs then knows whose cache a folder of that name is. Only a fixture root reads
    /// it (D-156).
    static let installedAppsKey = "ShuckInstalledApps"
    /// ``syncedNames``, separated by commas: `-ShuckSyncedFiles Holiday.mov`. Only a fixture root reads it (D-137).
    static let syncedFilesKey = "ShuckSyncedFiles"
    /// The excluded folders in `UserDefaults` (SET-001, SET-004): an array of absolute paths.
    static let excludedFoldersKey = "ExcludedFolders"
    /// The folders a UI test excludes, as paths inside its fixture root separated by commas: `-ShuckExcludedFolders
    /// Documents/Private`. Only a fixture root reads it, and then it replaces the stored list (D-150).
    static let excludedFoldersArgumentKey = "ShuckExcludedFolders"

    /// The developer project folders in `UserDefaults` (SET-003, SET-004): an array of absolute paths. Without a stored
    /// list, the default folders that exist are used (D-154).
    static let projectFoldersKey = "ProjectFolders"
    /// The project folders a UI test uses, as paths inside its fixture root separated by commas: `-ShuckProjectFolders
    /// Developer`. Only a fixture root reads it, and then it replaces the stored list and the defaults (D-154).
    static let projectFoldersArgumentKey = "ShuckProjectFolders"

    /// The ownership map and Developer Junk for one list of project folders.
    nonisolated struct ProjectScope {
        let ownership: OwnershipMap
        let developerJunk: DeveloperJunk
    }

    /// The apps a UI test's fixture root is taken to have: the ones the test names, each named by its bundle ID, and
    /// whatever this Mac has, such as TextEdit. A fixture root cannot install an app (D-156).
    nonisolated struct FixtureAppNames: AppNames {
        let installed: Set<String>

        init(installed: Set<String>) {
            self.installed = Set(installed.map { $0.lowercased() })
        }

        func name(ofBundleID bundleID: String) -> String? {
            installed.contains(bundleID.lowercased()) ? bundleID : SystemAppNames().name(ofBundleID: bundleID)
        }
    }

    /// Reads the stored value for a key, if any.
    typealias Settings = (String) -> Any?

    static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// Why the app stops at launch instead of running on the wrong data.
    enum LaunchError: Error, CustomStringConvertible {
        /// A fixture-root argument the app refuses, so it never falls back to the real home folder.
        case rejectedFixtureRoot(String)
        /// Not this build's bundle ID, so the build would share another build's preferences and data folder, or use
        /// a data folder the path guard does not protect (D-70).
        case unexpectedBundleID(String?)

        var description: String {
            switch self {
            case .rejectedFixtureRoot(let path): "Not a fixture root the test harness made: \(path)"
            case .unexpectedBundleID(let bundleID): "Not this build's bundle ID: \(bundleID ?? "none")"
            }
        }
    }

    /// - Parameters:
    ///   - arguments: The process's launch arguments.
    ///   - settings: Reads the stored thresholds, such as ``largeFilesMinimumSizeKey``, and the excluded folders.
    ///   - saveExcludedFolders: Stores the excluded folders, as ``excludedFoldersKey`` does, after each change. By default
    ///     it stores nothing, as in tests; the app passes one that writes `UserDefaults`.
    ///   - saveProjectFolders: Stores the project folders, as ``projectFoldersKey`` does, after each change.
    ///   - isFolder: Whether a default project folder exists. Tests pass a stub, so none reads the real home folder.
    ///   - debugBuild: Whether the fixture-root argument counts, and which bundle ID the build must have.
    ///   - bundleID: The app's bundle ID, which names its data folder.
    ///   - home: The home folder the app scans without a fixture root: the user's own. It has no default, so a test
    ///     that leaves it out does not compile instead of using the real one; tests pass a made-up one (SAF-016).
    /// - Throws: ``LaunchError`` if a debug build gets a fixture-root argument it does not accept, or the bundle ID is
    ///   not the build's own.
    init(
        arguments: [String], settings: Settings, saveExcludedFolders: @escaping @Sendable ([String]) -> Void = { _ in },
        saveProjectFolders: @escaping @Sendable ([String]) -> Void = { _ in },
        isFolder: @escaping (URL) -> Bool = ProjectFolders.isExistingFolder, debugBuild: Bool = isDebugBuild,
        appBundle: URL = Bundle.main.bundleURL, bundleID: String? = Bundle.main.bundleIdentifier,
        home: URL
    ) throws(LaunchError) {
        guard let bundleID, bundleID == (debugBuild ? ShuckKit.debugBundleID : ShuckKit.bundleID) else {
            throw .unexpectedBundleID(bundleID)
        }
        let fixtureRoot = try Self.fixtureRoot(in: arguments, debugBuild: debugBuild)
        let scope: ProjectScope
        if let root = fixtureRoot {
            // The engine tests' configuration (D-41): only the temporary folder's /private prefix is left out.
            makeProtection = { exclusions in
                PathGuardConfiguration(
                    home: root, systemLocations: PathGuardConfiguration.systemLocations.filter { $0 != "/private" },
                    appBundle: appBundle, userExclusions: exclusions)
            }
            // A UI test's list replaces the stored one, so a fixture root never reads a path of the real home folder.
            let seeded = Self.fixtureFolders(Self.list(settings(Self.excludedFoldersArgumentKey)), in: root)
            excludedFolders = FolderList(stored: seeded, save: saveExcludedFolders)
            // The same for the project folders, and a fixture root never starts with the default ones.
            projectFolders = FolderList(
                stored: Self.fixtureFolders(Self.list(settings(Self.projectFoldersArgumentKey)), in: root),
                save: saveProjectFolders)
            makeProjectScope = { Self.projectScope($0, home: root, resolvingLinks: false) }
            toolRunner = ToolRunner(executableRoots: [root])
            runningApps = StubRunningApps(Self.list(settings(Self.runningAppsKey)))
            cachesAndLogs = CachesAndLogs(
                appNames: FixtureAppNames(installed: Self.list(settings(Self.installedAppsKey))))
            scope = Self.projectScope(projectFolders.folders, home: root, resolvingLinks: false)
            context = ScanContext(
                home: root, ownership: scope.ownership, protection: makeProtection(excludedFolders.folders),
                runningApps: runningApps, toolRoot: root)
            trash = FolderTrash(folder: root.appending(path: ".Trash"))
        } else {
            // The ownership map compares paths with symlinks resolved (D-53).
            let home = home.resolvingSymlinksInPath()
            makeProtection = { exclusions in
                .production(home: home, appBundle: appBundle, userExclusions: exclusions)
            }
            excludedFolders = FolderList(
                stored: (settings(Self.excludedFoldersKey) as? [Any])?.compactMap { $0 as? String } ?? [],
                save: saveExcludedFolders)
            // Without a stored list, the default folders that exist: the key's absence, not an empty list, says the user
            // never chose (SET-003).
            let storedProjects = (settings(Self.projectFoldersKey) as? [Any])?.compactMap { $0 as? String }
            projectFolders = FolderList(
                stored: storedProjects ?? ProjectFolders.defaults(home: home, isFolder: isFolder),
                save: saveProjectFolders)
            makeProjectScope = { Self.projectScope($0, home: home) }
            runningApps = SystemRunningApps()
            cachesAndLogs = CachesAndLogs()
            toolRunner = ToolRunner(executableRoots: nil)
            scope = Self.projectScope(projectFolders.folders, home: home)
            context = ScanContext(
                home: home, ownership: scope.ownership, protection: makeProtection(excludedFolders.folders),
                runningApps: runningApps, toolRoot: URL(filePath: "/", directoryHint: .isDirectory))
            trash = SystemTrash()
        }
        developerJunk = scope.developerJunk
        largeFiles = LargeFiles(
            minimumSize: Self.number(settings(Self.largeFilesMinimumSizeKey)) ?? LargeFiles.defaultMinimumSize)
        // A period of 0 months would list every file, however recently opened.
        let months = Self.number(settings(Self.oldFilesPeriodKey)).flatMap { $0 > 0 ? Int($0) : nil }
        // A UI test made every fixture file just now, so their added dates say nothing; their modified dates are the
        // test's (D-140).
        let addedDate: LastOpenedReader.AddedDate =
            fixtureRoot == nil ? LastOpenedReader.addedToFolderDate : { @Sendable _ in nil }
        oldFiles = OldFiles(
            periodMonths: months ?? OldFiles.defaultPeriodMonths,
            minimumSize: Self.number(settings(Self.oldFilesMinimumSizeKey)) ?? OldFiles.defaultMinimumSize,
            addedDate: addedDate)
        historyFolder = HistoryLog.folder(home: context.home, bundleID: bundleID)
        scanDelay = fixtureRoot == nil ? nil : Self.number(settings(Self.scanDelayKey)).map { .seconds($0) }
        syncedNames = fixtureRoot == nil ? [] : Self.list(settings(Self.syncedFilesKey))
    }

    /// The preferences domain to clear at launch, before anything reads it: the debug build's own when a UI test
    /// launches it on a fixture root, so every test starts from default preferences and never restores a window
    /// frame, sidebar width or threshold that an earlier run saved (D-70). `nil` otherwise, and always in a release
    /// build.
    static func preferencesToClear(arguments: [String], bundleID: String?, debugBuild: Bool = isDebugBuild) -> String? {
        guard debugBuild, bundleID == ShuckKit.debugBundleID,
            (try? fixtureRoot(in: arguments, debugBuild: debugBuild)) != nil
        else { return nil }
        return ShuckKit.debugBundleID
    }

    /// Starts a personal-files scan, after ``scanDelay`` if a UI test set one. Cancelling the consuming task stops it,
    /// during the delay too.
    func personalFilesScan(
        context: ScanContext, lastOpened: LastOpenedReader?
    ) -> AsyncStream<PersonalFilesEvent> {
        let scanner = PersonalFilesScanner(context: context, readValues: readValues, lastOpened: lastOpened)
        guard let scanDelay else { return scanner.scan() }
        return AsyncStream { continuation in
            let task = Task {
                if (try? await Task.sleep(for: scanDelay)) != nil {
                    for await event in scanner.scan() {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads an entry's resource values from disk, marking the ones in ``syncedNames`` as synced.
    var readValues: PersonalFilesScanner.ValueReader {
        let syncedNames = syncedNames
        guard !syncedNames.isEmpty else { return EntryValues.read }
        return { url in
            var values = EntryValues.read(url)
            if syncedNames.contains(url.lastPathComponent) { values?.isSynced = true }
            return values
        }
    }

    /// Runs a plan's items, off the main actor, and logs every step in the history log in
    /// ``historyFolder`` (SAF-005, SAF-011).
    /// - Throws: ``HistoryError`` if the log cannot be opened. Then nothing moves.
    @concurrent
    func run(_ plan: Plan) async throws(HistoryError) -> RunReport {
        let log = try HistoryLog(folder: historyFolder)
        // The guard is built when the run starts, from the list as it is then: it re-validates every item against
        // it, and a change made while the run goes on waits for the next one (D-150).
        let executor = PlanExecutor(
            pathGuard: PathGuard(configuration: makeProtection(excludedFolders.folders)), log: log, trash: trash,
            runningApps: runningApps, toolRunner: toolRunner)
        return await executor.run(plan)
    }

    /// The bytes free now on the volume of the scanned home folder, or `nil` if macOS doesn't say (SAF-013). A UI
    /// test's fixture root is on the startup volume too, so its runs measure the real free space; they only read it.
    func availableSpace() -> Int64? {
        FreeSpace.available(at: context.home)
    }

    /// The bytes in use on the volume of the scanned home folder, or `nil` if macOS doesn't say (SAF-015, D-144).
    func usedSpace() -> Int64? {
        FreeSpace.used(at: context.home)
    }

    /// Moves trashed items back, off the main actor, and logs every step in the history log in ``historyFolder``
    /// (HIS-003, SAF-005, SAF-011).
    /// - Throws: ``HistoryError`` if the log cannot be opened. Then nothing moves.
    @concurrent
    func restore(_ requests: [RestoreRequest]) async throws(HistoryError) -> RestoreReport {
        let log = try HistoryLog(folder: historyFolder)
        let executor = RestoreExecutor(
            pathGuard: PathGuard(configuration: makeProtection(excludedFolders.folders)), log: log, trash: trash)
        return await executor.run(requests)
    }

    /// Reads the history log in ``historyFolder``, off the main actor, and groups it into runs, newest first
    /// (HIS-002). A missing log has no runs.
    @concurrent
    func loadHistory() async throws(HistoryError) -> HistoryModel.History {
        let contents = try HistoryLog.read(folder: historyFolder)
        return HistoryModel.History(
            runs: contents.runs().reversed(), unreadableLineCount: contents.unreadableLines.count)
    }

    /// The fixture root after ``fixtureRootArgument`` in a debug build, or `nil` if there is none.
    ///
    /// Only a folder the test harness creates is accepted: `ShuckFixtures/<UUID>` in the temporary folder, which is
    /// `/private/var/folders/…` for a test process, or the sandboxed UI test runner's container
    /// (`~/Library/Containers/<name>.xctrunner/Data/tmp`). The folder must exist; its path is resolved with `realpath`,
    /// as the test harness resolves it. Anything else throws, so a debug build is never pointed at real data by
    /// mistake.
    static func fixtureRoot(in arguments: [String], debugBuild: Bool) throws(LaunchError) -> URL? {
        guard debugBuild, let index = arguments.firstIndex(of: fixtureRootArgument) else { return nil }
        guard index + 1 < arguments.count else { throw .rejectedFixtureRoot("") }
        let path = arguments[index + 1]
        // `resolvingSymlinksInPath()` would turn /private/var back into /var, which the check below rejects (TD-12).
        guard let resolved = realpath(path, nil) else { throw .rejectedFixtureRoot(path) }
        defer { free(resolved) }
        let root = URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
        guard isFixtureRootShape(root) else { throw .rejectedFixtureRoot(root.path) }
        return root
    }

    /// Whether a resolved path has the shape of a folder the test harness creates: `ShuckFixtures/<UUID>` in a test
    /// process's temporary folder or in the UI test runner's container.
    static func isFixtureRootShape(_ root: URL) -> Bool {
        let parts = root.pathComponents
        guard parts.count > 2, parts[parts.count - 2] == "ShuckFixtures",
            UUID(uuidString: parts[parts.count - 1]) != nil
        else { return false }
        let temporary = Array(parts.dropLast(2))
        let isProcessTemporary = temporary.starts(with: ["/", "private", "var", "folders"])
        // …/Library/Containers/<name>.xctrunner/Data/tmp
        let tail = Array(temporary.suffix(5))
        let isRunnerTemporary =
            tail.count == 5 && tail[0] == "Library" && tail[1] == "Containers" && tail[2].hasSuffix(".xctrunner")
            && tail[3] == "Data" && tail[4] == "tmp"
        return isProcessTemporary || isRunnerTemporary
    }

    /// The items of a comma-separated launch argument, such as bundle IDs, without blanks. Anything else gives none.
    static func list(_ setting: Any?) -> Set<String> {
        guard let text = setting as? String else { return [] }
        return Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// The paths of `names`, which are relative to the fixture root, as absolute paths inside it, sorted. A name that
    /// is absolute or leaves the root with `..` is dropped, so a UI test cannot exclude, or point the app at, anything
    /// outside the root. Excluded folders and project folders both come from it.
    static func fixtureFolders(_ names: Set<String>, in root: URL) -> [String] {
        names.sorted().compactMap { name in
            guard !name.hasPrefix("/"), !name.hasPrefix("~"), !name.split(separator: "/").contains("..") else {
                return nil
            }
            return FolderList.standardize(root.appending(path: name).path)
        }
    }

    /// The ownership map and Developer Junk for `folders`, which may be any paths: only those inside `home`, with links
    /// resolved, count (SET-003, D-152, D-154).
    static func projectScope(_ folders: [URL], home: URL, resolvingLinks: Bool = true) -> ProjectScope {
        let engine = ProjectFolders.engineFolders(folders, home: home, resolvingLinks: resolvingLinks)
        return ProjectScope(
            ownership: OwnershipMap(home: home, projectFolders: engine),
            developerJunk: DeveloperJunk(projectFolders: engine))
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
