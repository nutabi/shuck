import Foundation

/// Decides whether Shuck may act on a path (SAF-007). Every target passes it when planned and again just before the
/// executor acts (SAF-008).
///
/// The checks, in order:
/// - (a) the path is not empty, `/` or the home folder;
/// - (b) it is absolute and has no `..` component;
/// - (e) after resolving symlinks, it is on the startup volume;
/// - (d) it is not inside a protected location, and does not contain one;
/// - (c) it is strictly inside one of the allowed roots for its tool or sub-tool.
///
/// Symlinks in the parent folders are resolved. A target that is itself a symlink is checked twice, as the link and as
/// its destination, and both must pass; the executor then acts on the link itself, never its destination (D-43).
public struct PathGuard: Sendable {
    public let configuration: PathGuardConfiguration

    public init(configuration: PathGuardConfiguration) {
        self.configuration = configuration
    }

    /// Validates a file URL. Returns the target with its parent folders resolved.
    @discardableResult
    public func validate(_ target: URL, allowedRoots: [URL]) throws(PathGuardError) -> URL {
        guard target.isFileURL else { throw .notAbsolute(target.absoluteString) }
        return try validate(path: target.path, allowedRoots: allowedRoots)
    }

    /// Validates a path string. Use this overload for paths built from strings: `URL(filePath: "")` silently becomes
    /// the current folder, so an empty variable would go unnoticed (the Steam bug pattern).
    @discardableResult
    public func validate(path: String, allowedRoots: [URL]) throws(PathGuardError) -> URL {
        guard !path.isEmpty else { throw .emptyPath }
        guard path.hasPrefix("/") else { throw .notAbsolute(path) }
        let components = path.split(separator: "/").filter { $0 != "." }
        guard !components.contains("..") else { throw .parentReference(path) }
        guard !components.isEmpty else { throw .rootFolder }

        let lexical = URL(filePath: "/" + components.joined(separator: "/"))
        guard let parent = ResolvedPath(lexical.deletingLastPathComponent()) else { throw .unresolvable(path) }
        let target = parent.url.appending(path: lexical.lastPathComponent)
        try check(target, existingAncestor: parent.existingAncestor, allowedRoots: allowedRoots)

        if ResolvedPath.isSymbolicLink(target) {
            guard let destination = ResolvedPath(target), ResolvedPath.itemExists(at: destination.url) else {
                throw .unresolvable(path)
            }
            try check(destination.url, existingAncestor: destination.existingAncestor, allowedRoots: allowedRoots)
        }
        return target
    }

    /// Runs checks (a) and (c) to (e) on a resolved path.
    private func check(_ target: URL, existingAncestor: URL, allowedRoots: [URL]) throws(PathGuardError) {
        if target.pathComponents == ["/"] { throw .rootFolder }
        let volume = try? existingAncestor.resourceValues(forKeys: [.volumeIsRootFileSystemKey])
        guard volume?.volumeIsRootFileSystem == true else { throw .otherVolume(target.path) }
        if target.pathComponents == configuration.home.pathComponents { throw .homeFolder }

        for location in configuration.protectedLocations
        where target.isSameOrInside(location) || location.isStrictlyInside(target) {
            throw .protectedLocation(target.path, protected: location.path)
        }
        for component in target.pathComponents
        where PathGuardConfiguration.protectedNames.contains(component)
            || PathGuardConfiguration.protectedExtensions.contains((component as NSString).pathExtension.lowercased())
        {
            throw .protectedLocation(target.path, protected: component)
        }

        let roots = allowedRoots.map { ResolvedPath($0)?.url ?? $0 }
        guard roots.contains(where: { target.isStrictlyInside($0) }) else { throw .outsideAllowedRoots(target.path) }
    }
}

/// Why the path guard rejected a target (SAF-007). Each case names the rule it breaks.
public enum PathGuardError: Error, Equatable {
    /// (a) The path is empty.
    case emptyPath
    /// (a) The path is the root folder `/`.
    case rootFolder
    /// (a) The path is the home folder itself.
    case homeFolder
    /// (b) The path is not absolute.
    case notAbsolute(String)
    /// (b) The path contains a `..` component.
    case parentReference(String)
    /// (c) A symlink or folder in the path cannot be resolved, for example a symlink whose destination is missing.
    case unresolvable(String)
    /// (c) After resolving symlinks, the path is not strictly inside an allowed root.
    case outsideAllowedRoots(String)
    /// (d) The path is, is inside, or contains a protected location (section 8.4).
    case protectedLocation(String, protected: String)
    /// (e) The path is not on the startup volume.
    case otherVolume(String)
}
