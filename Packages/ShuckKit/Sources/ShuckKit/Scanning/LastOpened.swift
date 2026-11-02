import CoreServices
import Foundation

/// When a file was last opened, and where that date comes from (OLD-002).
public struct LastOpened: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// Spotlight's `kMDItemLastUsedDate`, which Launch Services updates whenever the file is opened.
        case lastUsed
        /// Spotlight has no last-used date, so this is the content-modified date. The UI says so.
        case modified
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

    /// Smaller items get no last-opened date.
    public let minimumSize: Int64
    let lastUsedDate: LastUsedDate

    /// - Parameter lastUsedDate: Reads Spotlight's last-used date; tests stub it.
    public init(minimumSize: Int64, lastUsedDate: @escaping LastUsedDate = Self.spotlightLastUsedDate) {
        self.minimumSize = minimumSize
        self.lastUsedDate = lastUsedDate
    }

    /// The last-opened date of the item at `url`, or `nil` if it is smaller than ``minimumSize`` or has no date at all.
    public func read(_ url: URL, size: Int64, modified: Date?) -> LastOpened? {
        guard size >= minimumSize else { return nil }
        if let date = lastUsedDate(url) { return LastOpened(date: date, source: .lastUsed) }
        return modified.map { LastOpened(date: $0, source: .modified) }
    }

    /// Spotlight's `kMDItemLastUsedDate` for the item at `url`. `nil` if Spotlight has no record of it, for example
    /// because the file was never opened or its folder is not indexed.
    public static func spotlightLastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
