import Foundation

/// When a folder was last in use, for the staleness of a project or a cache (DEV-005, CAC-005). Only reads.
enum FolderActivity {
    /// The newest modification date of the folder, what is directly inside it and what is inside those, such as
    /// `Build/Products`. A folder's own date changes only when something is added to or removed from it, and a rebuild
    /// or an app writing its cache mostly changes files deeper down, so the folder alone would make a folder in daily
    /// use look stale (D-112, D-121).
    static func newest(in folder: URL, modified: Date) -> Date {
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
}
