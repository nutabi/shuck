import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Totals that combine sub-tools count each file once, matched by file identity (FCL-007).
struct ReclaimableTotalTests {
    private func file(
        _ path: String, size: Int64, identity: FileIdentity? = nil, readOnly: ReadOnlyReason? = nil
    ) -> PersonalFile {
        PersonalFile(
            url: URL(filePath: "/StubHome/\(path)"), identity: identity,
            snapshot: ItemSnapshot(kind: .file, allocatedSize: size), modified: nil, readOnly: readOnly)
    }

    @Test func aFileBothLargeAndOldCountsOnceFCL007() {
        let bigAndOld = file("Movies/old.mov", size: 5_000, identity: FileIdentity(volume: 1, file: 10))
        let bigAndNew = file("Movies/new.mov", size: 2_000, identity: FileIdentity(volume: 1, file: 11))
        let largeFiles = [bigAndOld, bigAndNew]
        let oldFiles = [bigAndOld]

        var total = ReclaimableTotal(largeFiles)
        total.add(contentsOf: oldFiles)

        #expect(total.bytes == 7_000)
        #expect(total.count == 2)
    }

    @Test func twoPathsToOneFileCountOnceFCL007() {
        let identity = FileIdentity(volume: 1, file: 10)

        let total = ReclaimableTotal([
            file("Movies/a.mov", size: 5_000, identity: identity),
            file("Backup/a.mov", size: 5_000, identity: identity),
        ])

        #expect(total.bytes == 5_000)
        #expect(total.count == 1)
    }

    @Test func theSameFileNumberOnAnotherVolumeIsAnotherFile() {
        let total = ReclaimableTotal([
            file("a.mov", size: 5_000, identity: FileIdentity(volume: 1, file: 10)),
            file("b.mov", size: 2_000, identity: FileIdentity(volume: 2, file: 10)),
        ])

        #expect(total.bytes == 7_000)
    }

    @Test func aFileWithoutIdentityIsMatchedByItsPath() {
        let total = ReclaimableTotal([
            file("Movies/a.mov", size: 5_000), file("Movies/a.mov", size: 5_000), file("Movies/b.mov", size: 2_000),
        ])

        #expect(total.bytes == 7_000)
        #expect(total.count == 2)
    }

    @Test func readOnlyFilesAreLeftOutFCL011() {
        let total = ReclaimableTotal([
            file("go/pkg/mod", size: 9_000, readOnly: .managedBy(.developerJunk)),
            file("Music/Music", size: 8_000, readOnly: .protected), file("a.mov", size: 1_000),
        ])

        #expect(total.bytes == 1_000)
        #expect(total.count == 1)
    }

    @Test func hardLinksShareAnIdentityAndCopiesDoNot() throws {
        let root = try FixtureRoot()
        let original = try root.file("Movies/a.mov", size: 10)
        let link = try root.hardLink("Backup/a.mov", to: "Movies/a.mov")
        let other = try root.file("Movies/b.mov", size: 10)

        let identity = try #require(FileIdentity.read(original))
        #expect(FileIdentity.read(link) == identity)
        #expect(FileIdentity.read(other) != identity)
        #expect(FileIdentity.read(root.url.appending(path: "missing")) == nil)
    }
}
