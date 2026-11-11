import Foundation
import Synchronization
import os

/// Lists the personal files that Large Files and Old Files share (FCL-006, FCL-008).
///
/// The scope is the home folder minus what ``OwnershipMap`` leaves out (`Library` except device backups, hidden
/// top-level items), app bundles and the user's exclusions. Packages and device backups are single items (FCL-009),
/// and iCloud placeholders are skipped, whether files, packages or folders (FCL-010). A downloaded file that iCloud keeps
/// is listed and marked synced (D-129). Locations another sub-tool owns (FCL-011), protected bundles and the
/// protected locations inside the home folder (section 8.4) are listed read-only. Symlinks are never followed. Git's
/// own files and other volumes mounted inside the home folder are out of scope (FCL-008, D-131, D-135).
///
/// Several folders are read at once, each by a task of the scan, off the main actor (D-81). Cancelling the task that
/// reads the stream stops the scan before the next entry (SAF-014).
public struct PersonalFilesScanner: Sendable {
    public typealias ValueReader = @Sendable (URL) -> EntryValues?
    /// Receives how many entries a finished scan looked at and how long it took.
    public typealias Report = @Sendable (_ entries: Int, _ duration: Duration) -> Void

    let context: ScanContext
    let batchSize: Int
    let readValues: ValueReader
    let lastOpened: LastOpenedReader?
    let report: Report
    /// The home folder's path and a slash. Every entry the walk finds starts with it.
    let homePrefix: String
    let locationKeys: LocationKeys
    /// The home folder's volume. An entry on any other volume is out of scope (FCL-008, D-135).
    let homeVolume: Int32?

    /// The scan is shared by File Cleanup's personal-files sub-tools, so it logs under File Cleanup (NFR-OBS-001).
    private static let logger = Logger(tool: .fileCleanup)

    /// - Parameters:
    ///   - batchSize: How many files each ``PersonalFilesEvent/files(_:)`` event carries at most.
    ///   - readValues: Reads an entry's resource values; tests stub it (FCL-010).
    ///   - lastOpened: Looks up last-opened dates for large enough items (OLD-002). Without it, no item gets one.
    ///   - report: Receives the entry count and duration of a scan that was not cancelled. By default they are logged
    ///     for the performance baseline (NFR-PERF-002); tests check them.
    public init(
        context: ScanContext, batchSize: Int = 256,
        readValues: @escaping ValueReader = EntryValues.read, lastOpened: LastOpenedReader? = nil,
        report: @escaping Report = PersonalFilesScanner.logFinished
    ) {
        self.context = context
        self.batchSize = max(1, batchSize)
        self.readValues = readValues
        self.lastOpened = lastOpened
        self.report = report
        homePrefix = context.home.path + "/"
        locationKeys = LocationKeys(home: context.home, protectedLocations: context.protection.protectedLocations)
        homeVolume = FileIdentity.read(context.home)?.volume
    }

    public func scan() -> AsyncStream<PersonalFilesEvent> {
        AsyncStream { continuation in
            let task = Task {
                let start = ContinuousClock.now
                let entries = await walkHome { continuation.yield($0) }
                if !Task.isCancelled { report(entries, start.duration(to: .now)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Logs a finished scan's entry count and duration, the figures the performance baseline records (NFR-PERF-002).
    public static func logFinished(entries: Int, duration: Duration) {
        logger.notice("Scanned \(entries, privacy: .public) entries in \(duration, privacy: .public)")
    }

    /// How many tasks may read folders besides the one that started the scan: one per processor core, less two, so at
    /// most one folder per core less one is read at once and Swift's shared threads keep one for the app (D-81).
    static let workers = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)

    /// Walks the home folder, reading several folders at once (D-81). Returns how many entries the walk looked at.
    private func walkHome(_ emit: @escaping @Sendable (PersonalFilesEvent) -> Void) async -> Int {
        let walk = Walk(slots: Self.workers, batchSize: batchSize, emit: emit)
        let entries = await withTaskGroup(of: Int.self) { tasks in
            let read = readFolder(context.home, inScope: true, walk, starting: &tasks)
            return await tasks.reduce(read, +)
        }
        walk.flush()
        return entries
    }

    /// Starts a task, in a slot taken for it, that reads `folder` and the folders below it.
    private func startTask(_ folder: URL, inScope: Bool, _ walk: Walk, in tasks: inout TaskGroup<Int>) {
        tasks.addTask {
            await withTaskGroup(of: Int.self) { subtasks in
                let read = readFolder(folder, inScope: inScope, walk, starting: &subtasks)
                // Its own folders are read, so the slot can go to a new task while this one waits for those it started.
                walk.slots.give()
                return await subtasks.reduce(read, +)
            }
        }
    }

    /// Classifies the entries of `folder`, sending files in batches, and reads the folders among them: each in a task of
    /// its own while a slot is free, and otherwise at once, depth first. Returns how many entries it looked at, without
    /// those of the tasks it started. An item measured as a whole, such as a package, counts once, although measuring
    /// it reads everything inside.
    private func readFolder(_ folder: URL, inScope: Bool, _ walk: Walk, starting tasks: inout TaskGroup<Int>) -> Int {
        let children = autoreleasepool { contents(of: folder, walk.emit) ?? [] }
        var files: [PersonalFile] = []
        var entries = 0
        for child in children {
            guard !Task.isCancelled else { break }
            entries += 1
            // Foundation hands back many of its objects autoreleased. Freeing them after each entry keeps memory flat;
            // otherwise they lived until the walk ended, 17.1 GB at the baseline's peak (D-80).
            switch autoreleasepool(invoking: { classify(child, parentInScope: inScope) }) {
            case .skip:
                continue
            case .item(let file):
                files.append(file)
                if files.count >= batchSize {
                    walk.send(files)
                    files = []
                }
            case .descend(let childInScope):
                if walk.slots.take() {
                    startTask(child, inScope: childInScope, walk, in: &tasks)
                } else {
                    entries += readFolder(child, inScope: childInScope, walk, starting: &tasks)
                }
            }
        }
        walk.send(files)
        return entries
    }

    /// What the tasks of one scan share: the free slots for new tasks, and one batch of files that they all fill, so
    /// the app gets as few events as from one task (D-81).
    private final class Walk: Sendable {
        let slots: Slots
        let batchSize: Int
        let emit: @Sendable (PersonalFilesEvent) -> Void
        private let pending = Mutex<[PersonalFile]>([])

        init(slots: Int, batchSize: Int, emit: @escaping @Sendable (PersonalFilesEvent) -> Void) {
            self.slots = Slots(slots)
            self.batchSize = batchSize
            self.emit = emit
        }

        /// Adds `files` to the batch, and sends each full batch.
        func send(_ files: [PersonalFile]) {
            guard !files.isEmpty else { return }
            let full = pending.withLock { batch in
                batch.append(contentsOf: files)
                var full: [[PersonalFile]] = []
                while batch.count >= batchSize {
                    full.append(Array(batch.prefix(batchSize)))
                    batch.removeFirst(batchSize)
                }
                return full
            }
            for files in full { emit(.files(files)) }
        }

        /// Sends the files left in the batch.
        func flush() {
            let rest = pending.withLock { batch in
                defer { batch = [] }
                return batch
            }
            if !rest.isEmpty { emit(.files(rest)) }
        }
    }

    /// Counts the slots free for new tasks.
    private final class Slots: Sendable {
        private let free: Mutex<Int>

        init(_ count: Int) {
            free = Mutex(count)
        }

        /// Takes a slot for a new task, if one is free.
        func take() -> Bool {
            free.withLock { count in
                guard count > 0 else { return false }
                count -= 1
                return true
            }
        }

        /// Gives back a slot.
        func give() {
            free.withLock { $0 += 1 }
        }
    }

    /// Folders whose subfolders are each one item, relative to the home folder: an iPhone or iPad backup is one folder
    /// of thousands of hashed files.
    static let wholeFolderLocations = ["Library/Application Support/MobileSync/Backup"]

    enum Decision: Equatable {
        case skip
        case item(PersonalFile)
        /// A folder to look inside. `inScope` is whether the folder itself is a personal-files location.
        case descend(inScope: Bool)
    }

    /// Decides what to do with one entry. `parentInScope` is whether its folder is a personal-files location.
    func classify(_ url: URL, parentInScope: Bool) -> Decision {
        // A placeholder's content is not on this Mac (FCL-010). It is skipped before anything measures or lists it,
        // since reading inside an evicted package or folder can make macOS download it.
        guard let values = readValues(url), !values.isSymbolicLink, !values.isPlaceholder else { return .skip }
        // Both checks come before anything measures, lists or enters the entry.
        // Git's own files are not personal files: trashing an old packfile corrupts the repository (FCL-008, D-131).
        if PathGuard.fold(url.lastPathComponent) == ".git" { return .skip }
        // Another volume mounted inside the home folder is out of scope. An entry whose volume is unknown is skipped
        // too, since nothing shows it is on the home folder's (FCL-008, D-135).
        guard let volume = values.identity?.volume, volume == homeVolume else { return .skip }
        let key = self.key(url)
        let protection = protectionOf(url, key: key)
        // Exclusions apply to tool-owned locations too: do not even measure a hidden store (SET-001).
        if case .hidden = protection { return .skip }
        let owners = context.ownership.owners(of: url)
        guard owners.isSuperset(of: OwnershipMap.personalFiles) else {
            // Another sub-tool's location inside the personal files is shown read-only, pointing at it (FCL-011).
            if parentInScope, let manager = owners.min(by: { $0.rawValue < $1.rawValue }) {
                return measured(url, values, readOnly: .managedBy(manager))
            }
            // Out of scope, unless a personal-files location lies further down, like device backups in Library.
            let lookInside =
                values.isDirectory && !values.isPackage
                && context.ownership.hasLocations(below: url, ownedBy: .largeFiles)
            return lookInside ? .descend(inScope: false) : .skip
        }
        if case .shown = protection { return measured(url, values, readOnly: .protected) }
        if values.isPackage {
            // App bundles belong to Applications (FCL-008).
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame { return .skip }
            return measured(url, values, readOnly: nil)
        }
        if values.isDirectory {
            let isWhole = key.map { locationKeys.wholeFolders.contains(Self.parentKey($0)) } ?? false
            return isWhole ? measured(url, values, readOnly: nil) : .descend(inScope: true)
        }
        guard values.isRegularFile else { return .skip }
        let snapshot = ItemSnapshot(kind: .file, allocatedSize: values.allocatedSize)
        return .item(file(url, snapshot, values, readOnly: nil))
    }

    /// A file, or a folder measured as one item with its total size (FCL-009). Skipped if the scan is cancelled.
    private func measured(_ url: URL, _ values: EntryValues, readOnly: ReadOnlyReason?) -> Decision {
        let snapshot =
            values.isDirectory
            ? ItemSnapshot.read(url) { !Task.isCancelled }
            : ItemSnapshot(kind: .file, allocatedSize: values.allocatedSize)
        guard let snapshot else { return .skip }
        return .item(file(url, snapshot, values, readOnly: readOnly))
    }

    private func file(_ url: URL, _ snapshot: ItemSnapshot, _ values: EntryValues, readOnly: ReadOnlyReason?)
        -> PersonalFile
    {
        let lastOpened = lastOpened?.read(
            url, size: snapshot.allocatedSize, modified: values.modified, isFolder: snapshot.kind == .folder)
        return PersonalFile(
            url: url, identity: values.identity, snapshot: snapshot, modified: values.modified, lastOpened: lastOpened,
            readOnly: readOnly, isSynced: values.isSynced)
    }

    enum Protection {
        /// Listed read-only: protected bundles and folder names, and every protected location inside the home folder
        /// (``PathGuardConfiguration/homeLocations``), such as the Music and TV libraries.
        case shown
        /// Left out: other protected locations, such as the user's exclusions and Shuck's own app (FCL-008).
        case hidden
    }

    /// ``PathGuardConfiguration/protectedNames`` with case folded.
    private static let protectedNames = Set(PathGuardConfiguration.protectedNames.map(PathGuard.fold))

    /// How `url`, whose key is `key`, is protected, if it is.
    func protectionOf(_ url: URL, key: String?) -> Protection? {
        // Names and extensions are compared with case folded, as the path guard compares them (D-79).
        let name = PathGuard.fold(url.lastPathComponent)
        if Self.protectedNames.contains(name)
            || PathGuardConfiguration.protectedExtensions.contains((name as NSString).pathExtension)
        {
            return .shown
        }
        guard let key else { return nil }
        if locationKeys.shown.contains(key) { return .shown }
        if locationKeys.hidden.contains(key) { return .hidden }
        return nil
    }

    /// The locations the walk treats specially, as keys (``PersonalFilesScanner/key(_:)``), worked out once per scan.
    /// Comparing standardized paths for every entry and location took most of a scan's time (D-78).
    struct LocationKeys: Sendable {
        /// Listed read-only (``Protection/shown``).
        let shown: Set<String>
        /// Left out (``Protection/hidden``).
        let hidden: Set<String>
        /// ``PersonalFilesScanner/wholeFolderLocations``.
        let wholeFolders: Set<String>

        init(home: URL, protectedLocations: [URL]) {
            func keys(_ locations: [URL]) -> Set<String> {
                Set(locations.compactMap { PersonalFilesScanner.locationKey($0, home: home) })
            }
            shown = keys(PathGuardConfiguration.homeLocations.map { home.appending(path: $0) })
            hidden = keys(protectedLocations)
            wholeFolders = keys(PersonalFilesScanner.wholeFolderLocations.map { home.appending(path: $0) })
        }
    }

    /// `url`'s key: its path inside the home folder with case folded, or `nil` if it is not inside. An entry the walk
    /// finds starts with the home folder's own path, so its key takes no file-system call.
    func key(_ url: URL) -> String? {
        let path = url.path
        guard path.hasPrefix(homePrefix) else { return Self.locationKey(url, home: context.home) }
        return PathGuard.fold(String(path.dropFirst(homePrefix.count)))
    }

    /// A location's key, or `nil` if it is not inside `home`. Both paths are standardized first, so `/private/var` and
    /// `/var` are the same folder.
    static func locationKey(_ location: URL, home: URL) -> String? {
        let homePath = PathGuard.fold(home.standardizedFileURL.path) + "/"
        let path = PathGuard.fold(location.standardizedFileURL.path)
        guard path.hasPrefix(homePath) else { return nil }
        return String(path.dropFirst(homePath.count))
    }

    /// The key of the folder that holds the item with `key`. The home folder's key is empty.
    static func parentKey(_ key: String) -> String {
        key.lastIndex(of: "/").map { String(key[..<$0]) } ?? ""
    }

    /// The entries of `folder`, or `nil` if it cannot be read. A folder macOS will not let Shuck read is reported as
    /// not accessible (SAF-012), and one that fails for any other reason as unreadable, so no folder leaves the results
    /// unnoticed (SAF-011).
    private func contents(of folder: URL, _ emit: (PersonalFilesEvent) -> Void) -> [URL]? {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(EntryValues.keys))
        } catch {
            let error = error as NSError
            if error.code == NSFileReadNoPermissionError {
                Self.logger.info("Not accessible: \(folder.path, privacy: .private)")
                emit(.notAccessible(folder))
            } else {
                // Cocoa's description names the folder, so only the domain and code are public (NFR-SEC-006).
                Self.logger.error(
                    """
                    Cannot list \(folder.path, privacy: .private): \(error.domain, privacy: .public) \
                    \(error.code, privacy: .public), \(error.localizedDescription, privacy: .private)
                    """)
                emit(.unreadable(folder))
            }
            return nil
        }
    }
}

/// The resource values the personal-files scanner reads for each entry.
public struct EntryValues: Equatable, Sendable {
    public var isDirectory: Bool
    /// A folder macOS presents as one file (FCL-009).
    public var isPackage: Bool
    public var isSymbolicLink: Bool
    public var isRegularFile: Bool
    /// Allocated size in bytes (SAF-013). Zero for folders.
    public var allocatedSize: Int64
    public var modified: Date?
    /// An iCloud file, package or folder whose content is not on this Mac (FCL-010).
    public var isPlaceholder: Bool
    /// An item iCloud keeps on the user's other devices too, such as a file in Documents under iCloud's Desktop &
    /// Documents (D-129).
    public var isSynced: Bool
    /// Which file the entry is (FCL-007).
    public var identity: FileIdentity?

    public init(
        isDirectory: Bool = false, isPackage: Bool = false, isSymbolicLink: Bool = false, isRegularFile: Bool = false,
        allocatedSize: Int64 = 0, modified: Date? = nil, isPlaceholder: Bool = false, isSynced: Bool = false,
        identity: FileIdentity? = nil
    ) {
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.isRegularFile = isRegularFile
        self.allocatedSize = allocatedSize
        self.modified = modified
        self.isPlaceholder = isPlaceholder
        self.isSynced = isSynced
        self.identity = identity
    }

    static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey, .totalFileAllocatedSizeKey,
        .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Reads the values from the file system. Returns `nil` if nothing is at `url`.
    public static func read(_ url: URL) -> EntryValues? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return EntryValues(
            isDirectory: values.isDirectory == true, isPackage: values.isPackage == true,
            isSymbolicLink: values.isSymbolicLink == true, isRegularFile: values.isRegularFile == true,
            allocatedSize: Int64(values.totalFileAllocatedSize ?? 0), modified: values.contentModificationDate,
            isPlaceholder: values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded,
            isSynced: values.isUbiquitousItem == true, identity: FileIdentity.read(url))
    }
}
