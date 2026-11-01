import Darwin
import Foundation

/// Which File Cleanup sub-tool owns each location in the home folder (FCL-005).
///
/// Every location belongs to exactly one sub-tool, except that Large Files and Old Files share the personal files
/// (FCL-006). The map is a list of patterns, and the most specific pattern that matches a path decides its owners. So
/// when Developer Junk claims `Library/Caches/Homebrew` and Caches & Logs claims `Library/Caches/*`, Homebrew's
/// cache belongs to Developer Junk only. A pattern with no owners marks locations no sub-tool scans, such as
/// `Library`. A scan skips any item whose owners do not include it.
///
/// Ownership covers File Cleanup only; Applications and Startup Items may act on the same locations (D-25).
public struct OwnershipMap: Sendable {
    /// One location and the sub-tools that own it.
    public struct Entry: Equatable, Sendable {
        /// A path relative to the home folder. Each component is matched as an `fnmatch(3)` pattern, ignoring case
        /// like the startup volume does, so `.*` matches any hidden name. The empty pattern is the home folder.
        public let pattern: String
        /// Empty when no File Cleanup sub-tool scans the location.
        public let owners: Set<ToolID>

        public init(_ pattern: String, owners: Set<ToolID>) {
            self.pattern = pattern
            self.owners = owners
        }

        var components: [String] { pattern.split(separator: "/").map(String.init) }

        /// More components wins; with as many, more components without wildcards wins.
        var specificity: (components: Int, literals: Int) {
            (components.count, components.filter { !Self.isWildcard($0) }.count)
        }

        static func isWildcard(_ component: String) -> Bool {
            component.contains { "*?[".contains($0) }
        }

        func matches(_ path: [String]) -> Bool {
            let components = components
            guard path.count >= components.count else { return false }
            return zip(components, path).allSatisfy { fnmatch($0, $1, FNM_CASEFOLD) == 0 }
        }
    }

    /// The owners of the personal files: Large Files and Old Files share one scan (FCL-006).
    public static let personalFiles: Set<ToolID> = [.largeFiles, .oldFiles]

    /// The map the app uses. Developer Junk and Caches & Logs add their locations with their rules in M2.
    public static let standardEntries: [Entry] = [
        // Personal files: the home folder (FCL-008)...
        Entry("", owners: personalFiles),
        // ...except Library, which apps manage, and hidden top-level folders, which hold tool data...
        Entry("Library", owners: []),
        Entry(".*", owners: []),
        // ...but including the user data allowlisted inside Library: iPhone and iPad backups.
        Entry("Library/Application Support/MobileSync/Backup", owners: personalFiles),
        // Tool-owned stores inside the personal files, shown there read-only (FCL-011, D-55): the Go module cache,
        // which `go clean -modcache` cleans (DEV-R14).
        Entry("go/pkg/mod", owners: [.developerJunk]),
    ]

    /// The home folder the patterns are relative to.
    public let home: URL
    public let entries: [Entry]

    public init(home: URL, entries: [Entry] = Self.standardEntries) {
        self.home = home
        self.entries = entries
    }

    /// The sub-tools that own `url`, or none if it is outside the home folder or no sub-tool scans it.
    ///
    /// `url` must be absolute, with symlinks resolved the same way as ``home``.
    public func owners(of url: URL) -> Set<ToolID> {
        guard let path = pathInHome(url) else { return [] }
        var best: Entry?
        for entry in entries where entry.matches(path) {
            if let current = best, entry.specificity <= current.specificity { continue }
            best = entry
        }
        return best?.owners ?? []
    }

    /// Whether a more specific entry gives `owner` a location inside `url`, so a scan must look inside a folder whose
    /// own owners leave it out, such as `Library` for the device backups.
    public func hasLocations(below url: URL, ownedBy owner: ToolID) -> Bool {
        guard let path = pathInHome(url) else { return false }
        return entries.contains { entry in
            let components = entry.components
            return entry.owners.contains(owner) && components.count > path.count
                && zip(components, path).allSatisfy { fnmatch($0, $1, FNM_CASEFOLD) == 0 }
        }
    }

    /// `url`'s components below the home folder, or `nil` if it is not inside it.
    private func pathInHome(_ url: URL) -> [String]? {
        let homeComponents = home.pathComponents
        let components = url.pathComponents
        guard components.count >= homeComponents.count, !components.contains(where: { $0 == "." || $0 == ".." })
        else { return nil }
        let inHome = zip(homeComponents, components).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
        return inHome ? Array(components.dropFirst(homeComponents.count)) : nil
    }
}
