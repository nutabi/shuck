import Foundation

extension FixtureRoot {
    /// Creates one version folder in the fixture's Xcode device support, such as
    /// `iOS DeviceSupport/17.2 (21C62) arm64e`, with a symbols file inside.
    @discardableResult
    public func deviceSupport(_ platform: String, _ version: String, size: Int = 4096) throws(FixtureError) -> URL {
        let path = "Library/Developer/Xcode/\(platform) DeviceSupport/\(version)"
        try file("\(path)/Symbols/usr/lib/libSystem.dylib", size: size)
        return try url(path)
    }
}
