import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Large Files lists personal files at or above its minimum size, whatever their age (LRG-001).
struct LargeFilesTests {
    let root: FixtureRoot
    /// A minimum the file system's 4 KiB blocks can match exactly, so allocated sizes land on either side of it.
    let minimum: Int64 = 1 << 20

    init() throws {
        root = try FixtureRoot()
    }

    private func scan(_ subTool: LargeFiles) async throws -> (items: [String: ScanItem], notAccessible: [URL]) {
        var items: [String: ScanItem] = [:]
        var notAccessible: [URL] = []
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        for await event in subTool.scan(context) {
            switch event {
            case .item(let item):
                let url = try root.requireInside(#require(item.url))
                items[String(url.path.dropFirst(root.url.path.count + 1))] = item
            case .notAccessible(let url):
                notAccessible.append(url)
            case .unreadable(let url):
                Issue.record("Could not read \(url.path)")
            }
        }
        return (items, notAccessible)
    }

    @Test func listsFilesAtOrAboveTheMinimumSizeOfAnyAgeLRG001() async throws {
        let longAgo = Date.now.addingTimeInterval(-10 * 365 * 86_400)
        try root.file("Downloads/below.dmg", size: Int(minimum) - 4_096)
        try root.file("Downloads/at.dmg", size: Int(minimum))
        try root.file("Movies/above.mov", size: Int(minimum) + 1, modified: longAgo)

        let items = try await scan(LargeFiles(minimumSize: minimum)).items

        #expect(Set(items.keys) == ["Downloads/at.dmg", "Movies/above.mov"])
        #expect(items.values.allSatisfy { $0.allocatedSize >= minimum })
        #expect(items.values.allSatisfy { $0.tier == .yourData && $0.method == .trash && $0.source == .largeFiles })
    }

    @Test func readOnlyFilesAreNeverItemsFCL011() async throws {
        try root.file("go/pkg/mod/cache.zip", size: Int(minimum))
        try root.file("Pictures/Photos Library.photoslibrary/database", size: Int(minimum))
        try root.file("Movies/clip.mov", size: Int(minimum))

        let items = try await scan(LargeFiles(minimumSize: minimum)).items

        #expect(Set(items.keys) == ["Movies/clip.mov"])
    }

    @Test func listsReadOnlyFilesForDisplayButMakesNoItemFromThem() {
        let largeFiles = LargeFiles(minimumSize: minimum)
        let managed = PersonalFile(
            url: root.url.appending(path: "go/pkg/mod"), snapshot: ItemSnapshot(kind: .folder, allocatedSize: minimum),
            modified: nil, readOnly: .managedBy(.developerJunk))
        let small = PersonalFile(
            url: root.url.appending(path: "a.txt"), snapshot: ItemSnapshot(kind: .file, allocatedSize: minimum - 1),
            modified: nil)

        #expect(largeFiles.includes(managed))
        #expect(largeFiles.scanItem(for: managed) == nil)
        #expect(!largeFiles.includes(small))
        #expect(largeFiles.scanItem(for: small) == nil)
    }

    @Test func reportsFoldersItCannotReadSAF012() async throws {
        let locked = try root.folder("Documents/Locked", permissions: 0o000)

        let notAccessible = try await scan(LargeFiles(minimumSize: minimum)).notAccessible

        #expect(notAccessible.map(\.lastPathComponent) == [locked.lastPathComponent])
    }
}
