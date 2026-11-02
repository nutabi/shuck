import Foundation

/// A file or package the personal-files scan found (FCL-008, FCL-009). Large Files and Old Files both list it
/// (FCL-006).
public struct PersonalFile: Equatable, Sendable {
    public let url: URL
    /// Which file it is, so a file several paths lead to counts once in totals (FCL-007). `nil` if it was not read.
    public let identity: FileIdentity?
    /// A file, or a package with its total allocated size (FCL-009).
    public let snapshot: ItemSnapshot
    /// The content-modified date.
    public let modified: Date?
    /// When the item was last opened (OLD-002). `nil` if the scan did not look it up, because the item is smaller than
    /// the reader's minimum or no reader was given, or if the item has no date at all.
    public let lastOpened: LastOpened?
    /// Set when the item is listed but can never be selected (FCL-011, section 8.4).
    public let readOnly: ReadOnlyReason?

    public init(
        url: URL, identity: FileIdentity? = nil, snapshot: ItemSnapshot, modified: Date?, lastOpened: LastOpened? = nil,
        readOnly: ReadOnlyReason? = nil
    ) {
        self.url = url
        self.identity = identity
        self.snapshot = snapshot
        self.modified = modified
        self.lastOpened = lastOpened
        self.readOnly = readOnly
    }

    /// The item as `source` lists it: "Your data", moved to the Trash (LRG-004, OLD-004). `nil` if it is read-only.
    public func scanItem(source: ToolID, reason: LocalizedStringResource) -> ScanItem? {
        guard readOnly == nil else { return nil }
        return ScanItem(url: url, snapshot: snapshot, tier: .yourData, method: .trash, reason: reason, source: source)
    }
}

/// Why a personal file is shown but never acted on.
public enum ReadOnlyReason: Equatable, Sendable {
    /// Another File Cleanup sub-tool manages it, such as Developer Junk for the Go module cache (FCL-011).
    case managedBy(ToolID)
    /// A protected location the user may see, such as a Photos library (section 8.4).
    case protected
}

/// What the personal-files scan reports as it goes. Files come in batches, so a large home folder does not cost one
/// event per file.
public enum PersonalFilesEvent: Equatable, Sendable {
    case files([PersonalFile])
    /// A folder the scan could not read (SAF-012). The scan goes on.
    case notAccessible(URL)
}

/// The item state Large Files and Old Files share (FCL-006). One scan fills it; an item trashed through either
/// sub-tool is removed once, so it leaves both.
public struct PersonalFilesState: Sendable {
    public private(set) var items: [URL: PersonalFile] = [:]
    public private(set) var notAccessible: Set<URL> = []

    public init() {}

    public mutating func apply(_ event: PersonalFilesEvent) {
        switch event {
        case .files(let files):
            for file in files {
                items[file.url] = file
            }
        case .notAccessible(let url):
            notAccessible.insert(url)
        }
    }

    /// Removes items that are no longer where the scan found them, for example because a run trashed them.
    public mutating func remove(_ urls: some Sequence<URL>) {
        for url in urls {
            items[url] = nil
        }
    }
}
