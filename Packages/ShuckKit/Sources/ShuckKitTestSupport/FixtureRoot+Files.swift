import Foundation

/// The file factory: creates files, folders and symlinks inside the fixture root (SAF-016).
///
/// Each method takes a path relative to the root, creates missing parent folders and returns the new item's URL. It
/// never overwrites: if anything already exists at the path, it throws ``FixtureError/alreadyExists(_:)``.
extension FixtureRoot {
    /// Creates a file of `size` bytes.
    ///
    /// The bytes are written for real, not left as a sparse hole, so the allocated size (SAF-013) is at least `size`.
    /// Dates and extended attributes are set after writing, so they are what the code under test sees.
    @discardableResult
    public func file(
        _ relativePath: String,
        size: Int = 0,
        modified: Date? = nil,
        created: Date? = nil,
        extendedAttributes: [String: Data] = [:]
    ) throws(FixtureError) -> URL {
        let target = try newItem(relativePath)
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw .fileSystem("Cannot create \(target.path)")
        }
        try Self.fileSystem {
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            let chunkSize = 1 << 20
            var remaining = size
            while remaining > 0 {
                let count = min(chunkSize, remaining)
                try handle.write(contentsOf: Data(repeating: 0x5A, count: count))
                remaining -= count
            }
        }
        for (name, value) in extendedAttributes.sorted(by: { $0.key < $1.key }) {
            let result = value.withUnsafeBytes { bytes in
                setxattr(target.path, name, bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
            }
            guard result == 0 else { throw .fileSystem("Cannot set \(name) on \(target.path): errno \(errno)") }
        }
        try setDates(of: target, modified: modified, created: created)
        return target
    }

    /// Creates a folder. A folder whose name has a package extension, such as `.app` or `.photoslibrary`, is a
    /// package (FCL-009).
    ///
    /// `permissions` sets its POSIX mode, for example `0o000` for a folder the scanner cannot read (SAF-012). The
    /// harness restores access before it removes the root.
    @discardableResult
    public func folder(
        _ relativePath: String,
        modified: Date? = nil,
        created: Date? = nil,
        permissions: Int? = nil
    ) throws(FixtureError) -> URL {
        let target = try newItem(relativePath)
        try Self.fileSystem { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
        try setDates(of: target, modified: modified, created: created)
        if let permissions {
            try Self.fileSystem {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
        }
        return target
    }

    /// Creates a symlink at `relativePath` that points to `destination`.
    ///
    /// The destination may lie outside the root or not exist at all, so path-guard tests can use it (SAF-007). The
    /// harness itself never follows such a link: creating a fixture through it throws.
    @discardableResult
    public func symlink(_ relativePath: String, to destination: URL) throws(FixtureError) -> URL {
        let target = try newItem(relativePath)
        try Self.fileSystem {
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: destination)
        }
        return target
    }

    /// Checks a path for a new item and creates its missing parent folders.
    ///
    /// `url(_:)` has already resolved every existing parent, so the folders created here are all inside the root.
    private func newItem(_ relativePath: String) throws(FixtureError) -> URL {
        let target = try url(relativePath)
        guard !Self.itemExists(at: target) else { throw .alreadyExists(relativePath) }
        let parent = target.deletingLastPathComponent()
        try Self.fileSystem { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
        return target
    }

    private func setDates(of target: URL, modified: Date?, created: Date?) throws(FixtureError) {
        var attributes: [FileAttributeKey: Any] = [:]
        attributes[.modificationDate] = modified
        attributes[.creationDate] = created
        guard !attributes.isEmpty else { return }
        try Self.fileSystem { try FileManager.default.setAttributes(attributes, ofItemAtPath: target.path) }
    }
}
