import Foundation
import os

/// Lists the personal files that Large Files and Old Files share (FCL-006, FCL-008).
///
/// The scope is the home folder minus what ``OwnershipMap`` leaves out (`Library` except device backups, hidden
/// top-level items), app bundles and the user's exclusions. Packages and device backups are single items (FCL-009),
/// and iCloud placeholders are skipped (FCL-010). Locations another sub-tool owns (FCL-011) and protected bundles
/// (section 8.4) are listed read-only. Symlinks are never followed.
///
/// Each top-level folder is walked in its own child task, off the main actor. Cancelling the task that reads the
/// stream stops the scan before the next entry (SAF-014).
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

    private static let logger = Logger(subsystem: ShuckKit.loggerSubsystem, category: "PersonalFiles")

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

    /// Walks each top-level item in its own child task. Returns how many entries the walks looked at.
    private func walkHome(_ emit: @escaping @Sendable (PersonalFilesEvent) -> Void) async -> Int {
        guard let children = contents(of: context.home, emit) else { return 0 }
        return await withTaskGroup(of: Int.self) { group in
            for child in children {
                group.addTask { walk(child, emit) }
            }
            return await group.reduce(0, +)
        }
    }

    /// Walks one top-level item depth first, sending files in batches. Returns how many entries it looked at. An item
    /// measured as a whole, such as a package, counts once, although measuring it reads everything inside.
    private func walk(_ root: URL, _ emit: @Sendable (PersonalFilesEvent) -> Void) -> Int {
        var batch: [PersonalFile] = []
        var entries = 0
        var pending: [(url: URL, parentInScope: Bool)] = [(root, true)]
        while let (url, parentInScope) = pending.popLast(), !Task.isCancelled {
            entries += 1
            // Foundation hands back many of its objects autoreleased. Freeing them after each entry keeps memory flat;
            // otherwise they lived until the walk ended, 17.1 GB at the baseline's peak (D-80).
            switch autoreleasepool(invoking: { classify(url, parentInScope: parentInScope) }) {
            case .skip:
                continue
            case .item(let file):
                batch.append(file)
                if batch.count >= batchSize {
                    emit(.files(batch))
                    batch = []
                }
            case .descend(let inScope):
                let children = autoreleasepool { contents(of: url, emit) ?? [] }
                pending.append(contentsOf: children.reversed().map { ($0, inScope) })
            }
        }
        if !batch.isEmpty { emit(.files(batch)) }
        return entries
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
        guard let values = readValues(url), !values.isSymbolicLink else { return .skip }
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
        let key = self.key(url)
        switch protectionOf(url, key: key) {
        case .shown: return measured(url, values, readOnly: .protected)
        case .hidden: return .skip
        case nil: break
        }
        if values.isPackage {
            // App bundles belong to Applications (FCL-008).
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame { return .skip }
            return measured(url, values, readOnly: nil)
        }
        if values.isDirectory {
            let isWhole = key.map { locationKeys.wholeFolders.contains(Self.parentKey($0)) } ?? false
            return isWhole ? measured(url, values, readOnly: nil) : .descend(inScope: true)
        }
        guard values.isRegularFile, !values.isPlaceholder else { return .skip }
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
        let lastOpened = lastOpened?.read(url, size: snapshot.allocatedSize, modified: values.modified)
        return PersonalFile(
            url: url, identity: values.identity, snapshot: snapshot, modified: values.modified, lastOpened: lastOpened,
            readOnly: readOnly)
    }

    enum Protection {
        /// Listed read-only: protected bundles, and the Music and TV libraries.
        case shown
        /// Left out: other protected locations, such as the user's exclusions and Shuck's own app (FCL-008).
        case hidden
    }

    /// How `url`, whose key is `key`, is protected, if it is.
    func protectionOf(_ url: URL, key: String?) -> Protection? {
        if PathGuardConfiguration.protectedNames.contains(url.lastPathComponent)
            || PathGuardConfiguration.protectedExtensions.contains(url.pathExtension.lowercased())
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
        return Self.fold(String(path.dropFirst(homePrefix.count)))
    }

    /// A location's key, or `nil` if it is not inside `home`. Both paths are standardized first, so `/private/var` and
    /// `/var` are the same folder.
    static func locationKey(_ location: URL, home: URL) -> String? {
        let homePath = fold(home.standardizedFileURL.path) + "/"
        let path = fold(location.standardizedFileURL.path)
        guard path.hasPrefix(homePath) else { return nil }
        return String(path.dropFirst(homePath.count))
    }

    /// The key of the folder that holds the item with `key`. The home folder's key is empty.
    static func parentKey(_ key: String) -> String {
        key.lastIndex(of: "/").map { String(key[..<$0]) } ?? ""
    }

    /// Full Unicode case folding, as the path guard compares names: `ß` matches `SS` as well as `A` matching `a`, like
    /// the startup volume. Swift's `==` already treats Unicode canonical forms (é and e + ´) as equal.
    static func fold(_ path: String) -> String {
        path.folding(options: .caseInsensitive, locale: nil)
    }

    /// The entries of `folder`, or `nil` if it cannot be read. A folder macOS will not let Shuck read is reported as
    /// not accessible (SAF-012).
    private func contents(of folder: URL, _ emit: (PersonalFilesEvent) -> Void) -> [URL]? {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(EntryValues.keys))
        } catch {
            let code = (error as NSError).code
            if code == NSFileReadNoPermissionError {
                Self.logger.info("Not accessible: \(folder.path, privacy: .private)")
                emit(.notAccessible(folder))
            } else {
                Self.logger.error(
                    "Cannot list \(folder.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
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
    /// An iCloud file whose content is not on this Mac (FCL-010).
    public var isPlaceholder: Bool
    /// Which file the entry is (FCL-007).
    public var identity: FileIdentity?

    public init(
        isDirectory: Bool = false, isPackage: Bool = false, isSymbolicLink: Bool = false, isRegularFile: Bool = false,
        allocatedSize: Int64 = 0, modified: Date? = nil, isPlaceholder: Bool = false, identity: FileIdentity? = nil
    ) {
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.isRegularFile = isRegularFile
        self.allocatedSize = allocatedSize
        self.modified = modified
        self.isPlaceholder = isPlaceholder
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
            identity: FileIdentity.read(url))
    }
}
