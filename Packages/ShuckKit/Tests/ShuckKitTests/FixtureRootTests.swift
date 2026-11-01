import Foundation
import ShuckKitTestSupport
import Testing

/// The fixture-root harness and file factory that every file test builds on (SAF-016).
struct FixtureRootTests {
    let root: FixtureRoot

    init() throws {
        root = try FixtureRoot()
    }

    // MARK: - The root

    @Test func rootIsAnEmptyFolderInTheTemporaryFolderSAF016() throws {
        let temporary = try #require(
            try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        )
        #expect(root.url.path.hasPrefix(temporary + "/"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.path).isEmpty)
    }

    @Test func eachRootIsSeparateSAF016() throws {
        let other = try FixtureRoot()
        #expect(other.url != root.url)
        #expect(!root.contains(other.url))
    }

    @Test func rootIsRemovedWhenReleasedSAF016() throws {
        let url: URL
        do {
            let released = try FixtureRoot()
            url = released.url
            try released.file("Documents/report.pdf", size: 10)
            try released.folder("Locked", permissions: 0o000)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Paths inside and outside the root

    @Test(arguments: ["", "/etc/hosts", "~/Documents", "../escape", "Documents/../../escape"])
    func rejectsPathsThatAreNotPlainRelativePathsSAF016(path: String) {
        let error = #expect(throws: FixtureError.self) { try root.url(path) }
        #expect(error == .invalidPath(path))
    }

    @Test func acceptsPathsInsideTheRootSAF016() throws {
        let url = try root.url("Downloads/installer.dmg")
        #expect(url.path == root.url.path + "/Downloads/installer.dmg")
        #expect(root.contains(root.url))
        #expect(root.contains(url))
    }

    @Test func rejectsPathsOutsideTheRootSAF016() {
        let outside = [
            URL(filePath: "/usr/bin"),
            root.url.deletingLastPathComponent(),
            URL(filePath: root.url.path + "-sibling"),
        ]
        for url in outside {
            #expect(!root.contains(url))
            let error = #expect(throws: FixtureError.self) { try root.requireInside(url) }
            #expect(error == .outsideFixtureRoot(url.path))
        }
    }

    @Test func rejectsFixturesThroughASymlinkThatLeavesTheRootSAF016() throws {
        let other = try FixtureRoot()
        let link = try root.symlink("Escape", to: other.url)

        let error = #expect(throws: FixtureError.self) { try root.file("Escape/stolen.txt") }
        #expect(error == .outsideFixtureRoot(link.appending(path: "stolen.txt").path))
        #expect(!root.contains(link))
        #expect(try FileManager.default.contentsOfDirectory(atPath: other.url.path).isEmpty)
    }

    @Test func rejectsFixturesThroughADanglingSymlinkSAF016() throws {
        let other = try FixtureRoot()
        let link = try root.symlink("Dangling", to: other.url.appending(path: "missing"))

        #expect(!root.contains(link))
        let error = #expect(throws: FixtureError.self) { try root.file("Dangling/created.txt") }
        #expect(error == .outsideFixtureRoot(link.appending(path: "created.txt").path))
        #expect(!FileManager.default.fileExists(atPath: other.url.appending(path: "missing").path))
    }

    // MARK: - The file factory

    @Test func fileHasItsSizeWrittenToDisk() throws {
        let url = try root.file("Movies/clip.mov", size: 100_000)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        #expect(values.fileSize == 100_000)
        #expect(try #require(values.totalFileAllocatedSize) >= 100_000)
    }

    @Test func fileHasItsDatesAndExtendedAttributes() throws {
        let modified = Date(timeIntervalSince1970: 1_600_000_000)
        let created = Date(timeIntervalSince1970: 1_500_000_000)
        let value = Data("https://example.com/installer.dmg".utf8)
        let url = try root.file(
            "Downloads/installer.dmg",
            modified: modified,
            created: created,
            extendedAttributes: ["me.nutabi.shuck.test": value]
        )

        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        #expect(values.contentModificationDate == modified)
        #expect(values.creationDate == created)

        var buffer = [UInt8](repeating: 0, count: 64)
        let length = getxattr(url.path, "me.nutabi.shuck.test", &buffer, buffer.count, 0, XATTR_NOFOLLOW)
        #expect(length == value.count)
        #expect(Data(buffer.prefix(max(length, 0))) == value)
    }

    @Test func factoryCreatesMissingParentFolders() throws {
        let url = try root.file("Documents/Taxes/2025/return.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func factoryNeverOverwrites() throws {
        try root.file("notes.txt", size: 5)
        let error = #expect(throws: FixtureError.self) { try root.folder("notes.txt") }
        #expect(error == .alreadyExists("notes.txt"))
        let size = try root.url("notes.txt").resourceValues(forKeys: [.fileSizeKey]).fileSize
        #expect(size == 5)
    }

    @Test func folderCanBeMadeUnreadable() throws {
        let url = try root.folder("Locked", permissions: 0o000)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0)
        #expect(throws: (any Error).self) { try FileManager.default.contentsOfDirectory(atPath: url.path) }
    }

    @Test func symlinkPointsAtItsDestinationWithoutFollowingIt() throws {
        let url = try root.symlink("System link", to: URL(filePath: "/usr"))
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        #expect(values.isSymbolicLink == true)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: url.path) == "/usr")
    }
}
