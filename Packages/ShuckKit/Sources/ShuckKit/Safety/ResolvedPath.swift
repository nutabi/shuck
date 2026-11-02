import Foundation

/// An absolute path with every symlink in it resolved, as the path guard compares paths (SAF-007).
///
/// Components that don't exist yet are kept as they are, so a path to be created (for example a restore destination)
/// can be checked too. `URL.resolvingSymlinksInPath()` and `URL.standardizedFileURL` are not used: both strip
/// `/private` from paths such as `/private/var/folders/…`, which would hide them from the protected-locations check
/// (D-41, D-43).
///
/// It has `package` access so that ShuckExecution and the scanner resolve paths and check that items exist with the
/// path guard's own helpers (TD-24). The fixture-root harness keeps a copy of its own, as an independent check.
package struct ResolvedPath {
    /// The resolved path.
    let url: URL
    /// The deepest part of ``url`` that exists on disk.
    let existingAncestor: URL

    /// Resolves `url`. Returns `nil` when an existing component cannot be resolved, for example a symlink whose
    /// destination is missing or a folder Shuck may not read.
    init?(_ url: URL) {
        var existing = url
        var missing: [String] = []
        while true {
            if let resolved = Self.realPath(existing) {
                self.url = missing.reduce(resolved) { $0.appending(path: $1) }
                existingAncestor = resolved
                return
            }
            if Self.itemExists(at: existing) || existing.path == "/" { return nil }
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
    }

    /// Whether anything, including a symlink, exists at `url`. Does not follow a final symlink.
    package static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Whether `url` is a symlink. Does not follow it.
    static func isSymbolicLink(_ url: URL) -> Bool {
        let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
        return type == .typeSymbolicLink
    }

    /// `url` with all symlinks resolved, or `nil` if it doesn't exist.
    package static func realPath(_ url: URL) -> URL? {
        guard let pointer = realpath(url.path, nil) else { return nil }
        defer { free(pointer) }
        return URL(filePath: String(cString: pointer))
    }
}

extension URL {
    /// Whether this path is `other` or inside it, comparing whole path components. Both must be resolved paths.
    func isSameOrInside(_ other: URL) -> Bool {
        let parent = other.pathComponents
        return Array(pathComponents.prefix(parent.count)) == parent
    }

    /// Whether this path is strictly inside `other`, comparing whole path components.
    func isStrictlyInside(_ other: URL) -> Bool {
        isSameOrInside(other) && pathComponents.count > other.pathComponents.count
    }
}
