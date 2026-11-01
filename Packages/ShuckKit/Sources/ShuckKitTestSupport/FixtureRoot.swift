import Foundation

/// A fresh temporary folder that stands in for the home folder in a test (SAF-016, D-41).
///
/// Every path the harness hands out or creates is checked to be inside the root after resolving symlinks. A path
/// outside it throws ``FixtureError/outsideFixtureRoot(_:)``, which fails the test. The folder and everything in it is
/// removed when the `FixtureRoot` is released, so keep it in a property of the test suite or a local constant.
///
/// The root lives in the temporary folder, so ``url`` starts with `/private/var/folders/`: `/var` is a symlink to
/// `/private/var`, and the harness always reports the resolved path.
public final class FixtureRoot: Sendable {
    /// The resolved location of the root folder.
    public let url: URL

    /// The folder all fixture roots are created in.
    private static let containerName = "ShuckFixtures"

    public init() throws(FixtureError) {
        let container = FileManager.default.temporaryDirectory.appending(path: Self.containerName)
        let root = container.appending(path: UUID().uuidString)
        try Self.fileSystem { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        guard let resolved = Self.realPath(root) else {
            throw .fileSystem("Cannot resolve the fixture root \(root.path)")
        }
        url = resolved
    }

    deinit {
        // Remove only a folder this harness created: a UUID-named folder in the fixtures container.
        guard url.deletingLastPathComponent().lastPathComponent == Self.containerName,
            UUID(uuidString: url.lastPathComponent) != nil
        else { return }
        Self.makeRemovable(url)
        try? FileManager.default.removeItem(at: url)
    }

    /// The location of `relativePath` inside the root, for example `"Downloads/movie.mov"`.
    ///
    /// The path must be relative, must not use `..` and must not lead outside the root through a symlink.
    public func url(_ relativePath: String) throws(FixtureError) -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.hasPrefix("~"),
            !components.contains("..")
        else { throw .invalidPath(relativePath) }
        return try requireInside(url.appending(path: relativePath))
    }

    /// Whether `candidate`, with its symlinks resolved, is the root or lies inside it.
    public func contains(_ candidate: URL) -> Bool {
        guard let resolved = Self.resolve(candidate) else { return false }
        let rootComponents = url.pathComponents
        return Array(resolved.pathComponents.prefix(rootComponents.count)) == rootComponents
    }

    /// Returns `candidate` if it is inside the root, and throws otherwise. Use it to check paths a test receives from
    /// the code under test.
    @discardableResult
    public func requireInside(_ candidate: URL) throws(FixtureError) -> URL {
        guard contains(candidate) else { throw .outsideFixtureRoot(candidate.path) }
        return candidate
    }

    // MARK: - Helpers shared with the file factory

    /// Runs a Foundation call and turns its error into ``FixtureError/fileSystem(_:)``.
    static func fileSystem<T>(_ body: () throws -> T) throws(FixtureError) -> T {
        do {
            return try body()
        } catch {
            throw .fileSystem(String(describing: error))
        }
    }

    /// Whether anything, including a symlink, exists at `url`. Does not follow a final symlink.
    static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// `candidate` with every symlink resolved. Components that don't exist yet are kept as they are. Returns `nil`
    /// when an existing component cannot be resolved, for example a symlink whose destination is missing.
    private static func resolve(_ candidate: URL) -> URL? {
        var existing = candidate.standardizedFileURL
        var missing: [String] = []
        while true {
            if let resolved = realPath(existing) {
                return missing.reduce(resolved) { $0.appending(path: $1) }
            }
            if itemExists(at: existing) || existing.path == "/" { return nil }
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
    }

    /// The path with all symlinks resolved, or `nil` if it doesn't exist. Unlike `URL.resolvingSymlinksInPath()`,
    /// this keeps the `/private` prefix of the temporary folder, as the path guard sees it.
    private static func realPath(_ url: URL) -> URL? {
        guard let pointer = realpath(url.path, nil) else { return nil }
        defer { free(pointer) }
        return URL(filePath: String(cString: pointer))
    }

    /// Gives the owner full access to every folder under `folder`, so fixtures made unreadable can be removed.
    /// Never follows symlinks, so nothing outside the root is changed.
    private static func makeRemovable(_ folder: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let children =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)))
        for child in children ?? [] {
            let values = try? child.resourceValues(forKeys: keys)
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                makeRemovable(child)
            }
        }
    }
}

/// Why the fixture-root harness refused a path or failed to create a fixture.
public enum FixtureError: Error, Equatable {
    /// The relative path is empty, absolute, starts with `~` or uses `..`.
    case invalidPath(String)
    /// The path resolves to a location outside the fixture root (SAF-016).
    case outsideFixtureRoot(String)
    /// Something already exists at the path; fixtures are never overwritten.
    case alreadyExists(String)
    /// A file-system call failed.
    case fileSystem(String)
}
