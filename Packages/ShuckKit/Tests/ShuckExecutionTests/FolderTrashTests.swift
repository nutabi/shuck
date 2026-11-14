import Foundation
import ShuckExecution
import ShuckKitTestSupport
import Testing

/// The folder Trash that tests and the app's fixture-root mode use instead of the real Trash (D-47, D-63).
struct FolderTrashTests {
    let root: FixtureRoot

    init() throws {
        root = try FixtureRoot()
    }

    @Test func movesItemsIntoItsFolderAndCreatesIt() throws {
        let file = try root.file("Movies/clip.mov", size: 10)
        let folder = root.trashFolder
        #expect(!FileManager.default.fileExists(atPath: folder.path))

        let trashed = try FolderTrash(folder: folder).trashItem(at: file)

        #expect(trashed == folder.appending(path: "clip.mov"))
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(throws: (any Error).self) {
            try FolderTrash(folder: folder).trashItem(at: root.url.appending(path: "Movies/missing.mov"))
        }
    }

    @Test func addsANumberToANameThatIsTaken() throws {
        let trash = FolderTrash(folder: root.trashFolder)
        let first = try trash.trashItem(at: root.file("Movies/clip.mov", size: 10))
        let second = try trash.trashItem(at: root.file("Downloads/clip.mov", size: 10))
        let third = try trash.trashItem(at: root.file("Desktop/clip.mov", size: 10))
        let folder = try trash.trashItem(at: root.folder("Documents/Old"))
        let sameFolderName = try trash.trashItem(at: root.folder("Desktop/Old"))

        #expect([first, second, third].map(\.lastPathComponent) == ["clip.mov", "clip 2.mov", "clip 3.mov"])
        #expect([folder, sameFolderName].map(\.lastPathComponent) == ["Old", "Old 2"])
    }
}
