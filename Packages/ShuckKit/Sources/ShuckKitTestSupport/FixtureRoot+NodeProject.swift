import Foundation

extension FixtureRoot {
    /// Creates a Node.js project: a `package.json` with `manifest`, a lockfile if `lockfile` names one, a source file, and
    /// a `node_modules` with one package of `size` bytes. `edited` is the date of the project's own files; `node_modules`
    /// is always just made, so a test can tell the project's date from its folder's. Returns the project's folder.
    @discardableResult
    public func nodeProject(
        _ path: String, lockfile: String? = "package-lock.json", manifest: String = "{\"name\": \"app\"}",
        edited: Date = .now, size: Int = 4096
    ) throws(FixtureError) -> URL {
        try file("\(path)/package.json", text: manifest, modified: edited)
        if let lockfile { try file("\(path)/\(lockfile)", size: 16, modified: edited) }
        try file("\(path)/src/index.js", size: 64, modified: edited)
        try file("\(path)/node_modules/dep/index.js", size: size)
        return try url(path)
    }
}
