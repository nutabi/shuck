import Foundation

extension FixtureRoot {
    /// Creates a fake app bundle at `relativePath`, such as `"Applications/Notes.app"`, with a real
    /// `Contents/Info.plist` and an executable of `size` bytes, so Applications lists it as an app (APP-001).
    ///
    /// A `nil` value leaves its key out of `Info.plist`, as for a bundle that declares no bundle ID.
    @discardableResult
    public func app(
        _ relativePath: String, bundleID: String?, name: String? = nil, displayName: String? = nil,
        version: String? = nil, size: Int = 0
    ) throws(FixtureError) -> URL {
        let bundle = try folder(relativePath)
        let executable = bundle.deletingPathExtension().lastPathComponent
        let values: [String: String?] = [
            "CFBundlePackageType": "APPL", "CFBundleExecutable": executable, "CFBundleIdentifier": bundleID,
            "CFBundleName": name, "CFBundleDisplayName": displayName, "CFBundleShortVersionString": version,
        ]
        let info = values.compactMapValues { $0 }
        let data = try Self.fileSystem {
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        }
        try file("\(relativePath)/Contents/Info.plist", text: String(decoding: data, as: UTF8.self))
        try file("\(relativePath)/Contents/MacOS/\(executable)", size: size)
        return bundle
    }
}
