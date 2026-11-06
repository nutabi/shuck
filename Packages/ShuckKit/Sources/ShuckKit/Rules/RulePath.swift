import Darwin
import Foundation

/// A rule's target pattern below one allowed root (DEV-001). Each slash-separated component uses fnmatch, as the
/// ownership map does. A pattern matches exactly that depth; `*` never crosses a folder boundary.
///
/// Matching is an extra rule check, never a replacement for the path guard (SAF-007).
public struct RulePath: Equatable, Sendable {
    public let root: URL
    public let pattern: String

    public init(root: URL, pattern: String) throws(RuleError) {
        let components = pattern.split(separator: "/", omittingEmptySubsequences: false)
        guard root.isFileURL, root.path.hasPrefix("/"), !root.pathComponents.contains(".."),
            !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\0") })
        else { throw .invalidPath }
        self.root = root
        self.pattern = pattern
    }

    /// Both paths are resolved with the path guard's resolver, preserving `/private` (D-43).
    public func matches(_ url: URL) -> Bool {
        guard let parent = ResolvedPath(root)?.url, let target = ResolvedPath(url)?.url,
            target.isStrictlyInside(parent)
        else { return false }
        let relative = target.pathComponents.dropFirst(parent.pathComponents.count)
        let components = pattern.split(separator: "/").map(String.init)
        return relative.count == components.count
            && zip(components, relative).allSatisfy { fnmatch($0, $1, FNM_CASEFOLD | FNM_PATHNAME) == 0 }
    }
}
