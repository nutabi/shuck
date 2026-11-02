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

    let context: ScanContext
    let batchSize: Int
    let readValues: ValueReader

    private static let logger = Logger(subsystem: ShuckKit.loggerSubsystem, category: "PersonalFiles")

    /// - Parameters:
    ///   - batchSize: How many files each ``PersonalFilesEvent/files(_:)`` event carries at most.
    ///   - readValues: Reads an entry's resource values; tests stub it (FCL-010).
    public init(
        context: ScanContext, batchSize: Int = 256,
        readValues: @escaping ValueReader = EntryValues.read
    ) {
        self.context = context
        self.batchSize = max(1, batchSize)
        self.readValues = readValues
    }

    public func scan() -> AsyncStream<PersonalFilesEvent> {
        AsyncStream { continuation in
            let task = Task {
                await walkHome { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func walkHome(_ emit: @escaping @Sendable (PersonalFilesEvent) -> Void) async {
        guard let children = contents(of: context.home, emit) else { return }
        await withTaskGroup(of: Void.self) { group in
            for child in children {
                group.addTask { walk(child, emit) }
            }
        }
    }

    /// Walks one top-level item depth first, sending files in batches.
    private func walk(_ root: URL, _ emit: @Sendable (PersonalFilesEvent) -> Void) {
        var batch: [PersonalFile] = []
        var pending: [(url: URL, parentInScope: Bool)] = [(root, true)]
        while let (url, parentInScope) = pending.popLast(), !Task.isCancelled {
            switch classify(url, parentInScope: parentInScope) {
            case .skip:
                continue
            case .item(let file):
                batch.append(file)
                if batch.count >= batchSize {
                    emit(.files(batch))
                    batch = []
                }
            case .descend(let inScope):
                let children = contents(of: url, emit) ?? []
                pending.append(contentsOf: children.reversed().map { ($0, inScope) })
            }
        }
        if !batch.isEmpty { emit(.files(batch)) }
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
        switch protectionOf(url) {
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
            let isWhole = Self.wholeFolderLocations.contains {
                Self.samePath(context.home.appending(path: $0), url.deletingLastPathComponent())
            }
            return isWhole ? measured(url, values, readOnly: nil) : .descend(inScope: true)
        }
        guard values.isRegularFile, !values.isPlaceholder else { return .skip }
        let snapshot = ItemSnapshot(kind: .file, allocatedSize: values.allocatedSize)
        return .item(PersonalFile(url: url, snapshot: snapshot, modified: values.modified))
    }

    /// A file, or a folder measured as one item with its total size (FCL-009). Skipped if the scan is cancelled.
    private func measured(_ url: URL, _ values: EntryValues, readOnly: ReadOnlyReason?) -> Decision {
        let snapshot =
            values.isDirectory
            ? ItemSnapshot.read(url) { !Task.isCancelled }
            : ItemSnapshot(kind: .file, allocatedSize: values.allocatedSize)
        guard let snapshot else { return .skip }
        return .item(PersonalFile(url: url, snapshot: snapshot, modified: values.modified, readOnly: readOnly))
    }

    enum Protection {
        /// Listed read-only: protected bundles, and the Music and TV libraries.
        case shown
        /// Left out: other protected locations, such as the user's exclusions and Shuck's own app (FCL-008).
        case hidden
    }

    func protectionOf(_ url: URL) -> Protection? {
        if PathGuardConfiguration.protectedNames.contains(url.lastPathComponent)
            || PathGuardConfiguration.protectedExtensions.contains(url.pathExtension.lowercased())
        {
            return .shown
        }
        let shown = PathGuardConfiguration.homeLocations.map { context.home.appending(path: $0) }
        if shown.contains(where: { Self.samePath($0, url) }) { return .shown }
        if context.protection.protectedLocations.contains(where: { Self.samePath($0, url) }) { return .hidden }
        return nil
    }

    /// Compares paths ignoring case, like the startup volume.
    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path.caseInsensitiveCompare(rhs.standardizedFileURL.path) == .orderedSame
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

    public init(
        isDirectory: Bool = false, isPackage: Bool = false, isSymbolicLink: Bool = false, isRegularFile: Bool = false,
        allocatedSize: Int64 = 0, modified: Date? = nil, isPlaceholder: Bool = false
    ) {
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.isRegularFile = isRegularFile
        self.allocatedSize = allocatedSize
        self.modified = modified
        self.isPlaceholder = isPlaceholder
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
            isPlaceholder: values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded)
    }
}
