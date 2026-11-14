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

    @Test func acceptsAPlainRelativePathInsideTheRootSAF016() throws {
        let url = try root.url("Downloads/installer.dmg")
        #expect(url.path == root.url.path + "/Downloads/installer.dmg")
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
}
