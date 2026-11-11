import Foundation
import Synchronization

/// The folders the user excluded in Settings (SET-001): absolute paths in the order they were added, kept in
/// `UserDefaults` (SET-004).
///
/// Anything may read it from any thread: a run builds its path guard off the main actor, and what it reads is the list
/// as it stands when the run starts (D-150). Only the main actor changes it, through ``ExclusionsModel``.
nonisolated final class ExcludedFolders: Sendable {
    private let paths: Mutex<[String]>
    private let save: @Sendable ([String]) -> Void

    /// - Parameters:
    ///   - stored: The paths stored by an earlier launch. Anything that is not an absolute path is dropped, and so is
    ///     a repeat.
    ///   - save: Stores the paths after each change.
    init(stored: [String], save: @escaping @Sendable ([String]) -> Void) {
        paths = Mutex(Self.unique(stored))
        self.save = save
    }

    /// The excluded folders, as they were added. A folder that no longer exists stays in the list (D-150).
    var folders: [URL] {
        paths.withLock { $0 }.map { URL(filePath: $0) }
    }

    /// Adds the folders that are not excluded yet and returns the list now.
    @discardableResult
    func add(_ added: [URL]) -> [URL] {
        change { Self.unique($0 + added.map(\.path)) }
    }

    /// Removes the folders from the list and returns the list now.
    @discardableResult
    func remove(_ removed: [URL]) -> [URL] {
        let gone = Set(removed.compactMap { Self.standardize($0.path) })
        return change { $0.filter { !gone.contains($0) } }
    }

    private func change(_ transform: ([String]) -> [String]) -> [URL] {
        let updated = paths.withLock { paths in
            paths = transform(paths)
            return paths
        }
        save(updated)
        return updated.map { URL(filePath: $0) }
    }

    /// `path` with `~` expanded, and `.`, `..`, repeated and trailing slashes removed, or `nil` if it is not absolute.
    /// Symlinks stay as they are: the list shows what the user chose, and the guard resolves them when it compares
    /// (D-150).
    static func standardize(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        var parts: [Substring] = []
        for part in expanded.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// The standardized paths without repeats, in their first order.
    private static func unique(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.compactMap(standardize).filter { seen.insert($0).inserted }
    }
}
