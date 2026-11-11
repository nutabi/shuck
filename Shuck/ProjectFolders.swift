import Foundation

/// What the app knows about the developer project folders (SET-003): which ones a Mac starts with, which ones may be
/// added, and how the stored list becomes the folders the engine takes (D-154).
nonisolated enum ProjectFolders {
    /// Folders inside the home folder that developers commonly keep their projects in. Whichever of them exist are the
    /// list until the user changes it (SET-003).
    static let defaultNames = ["Developer", "Projects", "Code", "src", "repos"]

    /// Whether a folder is there, following a link, as a user would see it in Finder.
    static func isExistingFolder(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue
    }

    /// The paths of the default folders that exist in `home`, in the order of ``defaultNames``.
    static func defaults(home: URL, isFolder: (URL) -> Bool = isExistingFolder) -> [String] {
        defaultNames.map { home.appending(path: $0, directoryHint: .isDirectory) }.filter(isFolder).map(\.path)
    }

    /// Whether `folder` lies inside the home folder, with links resolved, so a link that leads out of it does not count.
    /// The home folder itself does not: the allowed roots stay inside it (SET-003, D-154).
    static func isInsideHome(_ folder: URL, home: URL) -> Bool {
        isStrictlyInside(folder.resolvingSymlinksInPath(), home.resolvingSymlinksInPath())
    }

    /// The folders as the engine takes them: links resolved as the home folder's are, only those inside it, without
    /// repeats (D-152). A UI test's fixture root is resolved already, and its folders are never links, so it asks for
    /// `resolvingLinks: false`: `resolvingSymlinksInPath()` would turn its `/private/var` into `/var`.
    static func engineFolders(_ folders: [URL], home: URL, resolvingLinks: Bool = true) -> [URL] {
        let resolve = { (url: URL) in resolvingLinks ? url.resolvingSymlinksInPath() : url }
        let home = resolve(home)
        var seen: Set<String> = []
        return folders.map(resolve).filter {
            isStrictlyInside($0, home) && seen.insert($0.path.lowercased()).inserted
        }
    }

    private static func isStrictlyInside(_ url: URL, _ folder: URL) -> Bool {
        let (path, base) = (url.pathComponents, folder.pathComponents)
        return path.count > base.count && zip(base, path).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
    }
}
