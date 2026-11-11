import Foundation

extension FixtureRoot {
    /// Creates an Xcode archive in the fixture's Archives folder, such as `Archives/2026-11-11/App.xcarchive`, with the
    /// `Info.plist` and a build product Xcode writes into one. `day` is the date folder Xcode makes for it.
    @discardableResult
    public func xcarchive(day: String, name: String, size: Int = 4096) throws(FixtureError) -> URL {
        let path = "Library/Developer/Xcode/Archives/\(day)/\(name).xcarchive"
        try file("\(path)/Info.plist", size: 64)
        try file("\(path)/Products/Applications/\(name).app/\(name)", size: size)
        return try url(path)
    }
}
