import Foundation

extension FixtureRoot {
    /// Creates a project folder in the fixture's Xcode DerivedData, such as `MyApp-abcdefghijklmnopqrstuvwxyzab`,
    /// with an `info.plist` that names `workspace` (nil leaves the plist out) and a build product.
    ///
    /// Every date inside is set to `modified`, and the folder's last, since creating a file changes its folder.
    @discardableResult
    public func derivedDataProject(
        _ name: String, workspace: URL?, modified: Date, size: Int = 4096
    ) throws(FixtureError) -> URL {
        let path = "Library/Developer/Xcode/DerivedData/\(name)"
        var inside = [try file("\(path)/Build/Products/Debug/App", size: size)]
        if let workspace {
            let plist = try file("\(path)/info.plist")
            let data = try? PropertyListSerialization.data(
                fromPropertyList: ["WorkspacePath": workspace.path], format: .xml, options: 0)
            guard let data, (try? data.write(to: plist)) != nil else { throw .fileSystem("Cannot write \(plist.path)") }
            inside.append(plist)
        }
        let folder = try url(path)
        // Deepest first: changing a date of an item does not change its folder's.
        let levels = ["Build/Products/Debug", "Build/Products", "Build"].map { folder.appending(path: $0) }
        for item in inside + levels + [folder] {
            do {
                try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: item.path)
            } catch {
                throw .fileSystem("Cannot set the date of \(item.path)")
            }
        }
        return folder
    }
}
