import CoreServices
import Foundation

/// When a file was last in use, as Old Files judges it, and which date decided (OLD-002).
///
/// It is the latest of three dates: when the file was last opened, last modified and added to its folder. No single
/// date proves a file is unused, so the newest one counts (D-130).
public struct LastOpened: Equatable, Sendable {
    /// Which date was the latest. When two are equal, the earlier case wins.
    public enum Source: Equatable, Sendable, CaseIterable {
        /// Spotlight's `kMDItemLastUsedDate`, which Launch Services updates whenever the file is opened.
        case lastUsed
        /// The content-modified date. For a package or a folder listed as one item, the newest among the item and its
        /// direct children.
        case modified
        /// When the item was put in its folder (`addedToDirectoryDateKey`), as when it was downloaded or copied.
        case added
    }

    public let date: Date
    public let source: Source

    public init(date: Date, source: Source) {
        self.date = date
        self.source = source
    }
}

/// Looks up last-opened dates during the personal-files scan (OLD-002).
///
/// A Spotlight lookup costs about half a millisecond, so a home folder of a million files cannot afford one per file
/// (NFR-PERF-002). The reader looks up only items of at least `minimumSize`, which Old Files sets to its own minimum
/// (OLD-001).
public struct LastOpenedReader: Sendable {
    public typealias LastUsedDate = @Sendable (URL) -> Date?
    public typealias AddedDate = @Sendable (URL) -> Date?

    /// Smaller items get no last-opened date.
    public let minimumSize: Int64
    let lastUsedDate: LastUsedDate
    let addedDate: AddedDate

    /// - Parameters:
    ///   - lastUsedDate: Reads Spotlight's last-used date; tests stub it.
    ///   - addedDate: Reads when an item was added to its folder. Tests stub it, since every fixture file was added
    ///     just now.
    public init(
        minimumSize: Int64, lastUsedDate: @escaping LastUsedDate = Self.spotlightLastUsedDate,
        addedDate: @escaping AddedDate = Self.addedToFolderDate
    ) {
        self.minimumSize = minimumSize
        self.lastUsedDate = lastUsedDate
        self.addedDate = addedDate
    }

    /// The last-opened date of the item at `url`: the latest of its last-used, modified and added dates (D-130). `nil`
    /// if it is smaller than ``minimumSize`` or has none of them. For a folder, which includes a package, the modified
    /// date is the newest among `modified` and the folder's direct children, since changing a file inside a package
    /// rarely changes the package's own date.
    public func read(_ url: URL, size: Int64, modified: Date?, isFolder: Bool = false) -> LastOpened? {
        guard size >= minimumSize else { return nil }
        let modified = isFolder ? Self.newestChild(of: url, modified: modified) : modified
        let dates: [(Date?, LastOpened.Source)] = [
            (lastUsedDate(url), .lastUsed), (modified, .modified), (addedDate(url), .added),
        ]
        var latest: LastOpened?
        for case (let date?, let source) in dates where latest.map({ date > $0.date }) ?? true {
            latest = LastOpened(date: date, source: source)
        }
        return latest
    }

    /// The newest of `modified` and the modified dates of the direct children of `folder`. Only reads.
    static func newestChild(of folder: URL, modified: Date?) -> Date? {
        let children = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        return (children ?? []).reduce(modified) { newest, child in
            let date = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard let date else { return newest }
            return newest.map { max($0, date) } ?? date
        }
    }

    /// When the item at `url` was added to its folder, or `nil` if the file system does not say.
    public static func addedToFolderDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
    }

    /// Spotlight's `kMDItemLastUsedDate` for the item at `url`. `nil` if Spotlight has no record of it, for example
    /// because the file was never opened or its folder is not indexed.
    public static func spotlightLastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
