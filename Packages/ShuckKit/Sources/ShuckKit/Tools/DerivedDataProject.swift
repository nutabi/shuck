import Darwin
import Foundation

/// What Developer Junk reads about one folder in Xcode's DerivedData: which project it belongs to and when it was last
/// used (DEV-005, DEV-008). Only reads; it never changes the folder.
public enum DerivedDataProject {
    /// The project or workspace Xcode recorded in the folder's `info.plist`, or `nil` if the folder has none or it
    /// cannot be read, as for `ModuleCache.noindex`.
    static func workspace(in folder: URL) -> URL? {
        guard let data = try? Data(contentsOf: folder.appending(path: "info.plist")),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let path = plist["WorkspacePath"] as? String, path.hasPrefix("/"), !path.contains("\0")
        else { return nil }
        return URL(filePath: path)
    }

    /// Whether `workspace` is certainly gone: the system says nothing is at its path. A path it cannot check, such as
    /// one in a folder macOS keeps private, or on a disk that is not connected right now, is not gone (D-112).
    static func isMissing(_ workspace: URL) -> Bool {
        let parts = workspace.pathComponents
        // "/", "Volumes", disk: an unmounted disk's projects are not deleted, only away.
        if parts.count > 2, parts[1] == "Volumes", !exists(URL(filePath: "/Volumes/" + parts[2])) { return false }
        var info = stat()
        guard lstat(workspace.path, &info) != 0 else { return false }
        return errno == ENOENT || errno == ENOTDIR
    }

    /// The newest modification date of the folder, what is directly inside it and what is inside those, such as
    /// `Build/Products`. A folder's own date changes only when something is added to or removed from it, and a rebuild
    /// mostly changes files deeper down, so the folder alone would make a project in daily use look stale (D-112).
    static func lastActivity(in folder: URL, modified: Date) -> Date {
        var newest = modified
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        for child in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [] {
            let values = try? child.resourceValues(forKeys: Set(keys))
            newest = max(newest, values?.contentModificationDate ?? .distantPast)
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            for grandchild in (try? manager.contentsOfDirectory(at: child, includingPropertiesForKeys: keys)) ?? [] {
                let date = try? grandchild.resourceValues(forKeys: [.contentModificationDateKey])
                newest = max(newest, date?.contentModificationDate ?? .distantPast)
            }
        }
        return newest
    }

    /// The project's name for a DerivedData folder: `MyApp` for `MyApp-bnqjlxyvrdczkkgqvbpnzmtqgwwj`. Xcode appends a
    /// hash of the project's path. A name with no hash, such as `ModuleCache.noindex`, is returned as it is.
    public static func name(ofFolder name: String) -> String {
        guard let dash = name.lastIndex(of: "-") else { return name }
        let hash = name[name.index(after: dash)...]
        let project = name[..<dash]
        return hash.count == 28 && hash.allSatisfy({ $0.isASCII && $0.isLetter }) && !project.isEmpty
            ? String(project) : name
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
