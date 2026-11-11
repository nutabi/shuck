import Foundation

/// When a folder was last in use, for the staleness of a project or a cache (DEV-005, CAC-005). Only reads.
enum FolderActivity {
    /// The newest modification date of the folder, what is directly inside it and what is inside those, such as
    /// `Build/Products`. A folder's own date changes only when something is added to or removed from it, and a rebuild
    /// or an app writing its cache mostly changes files deeper down, so the folder alone would make a folder in daily
    /// use look stale (D-112, D-121). Dates are read with `lstat`, as re-validation reads them (D-132), and symlinks are
    /// never followed.
    static func newest(in folder: URL, modified: Date) -> Date {
        var newest = modified
        for child in entries(of: folder) {
            guard let info = ModificationDate.status(of: child) else { continue }
            newest = max(newest, ModificationDate.date(info))
            guard info.st_mode & S_IFMT == S_IFDIR else { continue }
            for grandchild in entries(of: child) {
                newest = max(newest, ModificationDate.read(at: grandchild) ?? .distantPast)
            }
        }
        return newest
    }

    private static func entries(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }
}
