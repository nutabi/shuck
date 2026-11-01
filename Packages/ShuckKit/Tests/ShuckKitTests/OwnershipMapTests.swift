import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The ownership map: every location in File Cleanup has exactly one owner (FCL-005).
struct OwnershipMapTests {
    let root: FixtureRoot
    let map: OwnershipMap

    init() throws {
        root = try FixtureRoot()
        map = OwnershipMap(home: root.url)
    }

    private func owners(_ path: String) -> Set<ToolID> {
        map.owners(of: root.url.appending(path: path))
    }

    // MARK: - Tool-owned stores and nested locations (FCL-011)

    @Test func theGoModuleCacheBelongsToDeveloperJunkFCL011() {
        #expect(owners("go/pkg/mod/github.com/x/y.go") == [.developerJunk])
        #expect(owners("go/bin/tool") == OwnershipMap.personalFiles)
    }

    @Test func aFolderLeftOutCanHoldOwnedLocationsFurtherDown() {
        #expect(map.hasLocations(below: root.url.appending(path: "Library"), ownedBy: .largeFiles))
        #expect(map.hasLocations(below: root.url.appending(path: "Library/Application Support"), ownedBy: .oldFiles))
        #expect(!map.hasLocations(below: root.url.appending(path: "Library/Caches"), ownedBy: .largeFiles))
        #expect(!map.hasLocations(below: root.url.appending(path: ".cache"), ownedBy: .largeFiles))
        #expect(!map.hasLocations(below: URL(filePath: "/usr"), ownedBy: .largeFiles))
    }

    // MARK: - No overlaps (FCL-005)

    @Test func theStandardMapHasNoOverlapsExceptPersonalFilesFCL005() {
        #expect(Self.overlaps(in: OwnershipMap.standardEntries).isEmpty)
    }

    @Test func onlyThePersonalFilesPairSharesALocationFCL005() {
        for entry in OwnershipMap.standardEntries {
            #expect(entry.owners.count <= 1 || entry.owners == OwnershipMap.personalFiles, "\(entry.pattern)")
        }
        #expect(OwnershipMap.personalFiles == [.largeFiles, .oldFiles])
    }

    @Test func theOverlapCheckFindsTwoOwnersForOneLocationFCL005() {
        let duplicate: [OwnershipMap.Entry] = [
            .init("Library/Caches/*", owners: [.cachesAndLogs]), .init("library/caches/*", owners: [.developerJunk]),
        ]
        let ambiguous: [OwnershipMap.Entry] = [
            .init("Library/Caches/*", owners: [.cachesAndLogs]), .init("Library/*/Homebrew", owners: [.developerJunk]),
        ]
        let nested: [OwnershipMap.Entry] = [
            .init("Library/Caches/*", owners: [.cachesAndLogs]),
            .init("Library/Caches/Homebrew", owners: [.developerJunk]),
        ]
        #expect(Self.overlaps(in: duplicate).count == 1)
        #expect(Self.overlaps(in: ambiguous).count == 1)
        #expect(Self.overlaps(in: nested).isEmpty)
    }

    // MARK: - Personal files (FCL-008)

    @Test(arguments: ["Downloads/installer.dmg", "Movies/clip.mov", "Projects/App/build.zip", "notes.txt"])
    func homeFolderFilesArePersonalFiles(path: String) {
        #expect(owners(path) == OwnershipMap.personalFiles)
    }

    @Test(arguments: ["Library/Preferences/com.apple.finder.plist", "Library/Caches/com.example", ".npm/_cacache"])
    func libraryAndHiddenTopLevelFoldersHaveNoOwner(path: String) {
        #expect(owners(path).isEmpty)
    }

    @Test func deviceBackupsInLibraryArePersonalFiles() {
        #expect(owners("Library/Application Support/MobileSync/Backup/00008110-ABC") == OwnershipMap.personalFiles)
        #expect(owners("Library/Application Support/MobileSync/Other").isEmpty)
    }

    @Test func hiddenFoldersBelowTheTopLevelStayPersonalFiles() {
        #expect(owners("Projects/App/.git/objects/pack/pack.pack") == OwnershipMap.personalFiles)
    }

    @Test func matchingIgnoresCaseLikeTheStartupVolume() {
        #expect(owners("library/caches/com.example").isEmpty)
        #expect(owners("LIBRARY/Application Support/mobilesync/backup/x") == OwnershipMap.personalFiles)
    }

    @Test func pathsOutsideTheHomeFolderHaveNoOwner() {
        #expect(map.owners(of: root.url.deletingLastPathComponent().appending(path: "Other/file")).isEmpty)
        #expect(map.owners(of: URL(filePath: "/Applications/Safari.app")).isEmpty)
        #expect(map.owners(of: root.url.appending(path: "Downloads/../Library/Caches")).isEmpty)
    }

    // MARK: - Most specific wins

    @Test func theMostSpecificPatternWins() {
        let map = OwnershipMap(
            home: root.url,
            entries: [
                .init("Library/Caches/*", owners: [.cachesAndLogs]),
                .init("Library/Caches/Homebrew", owners: [.developerJunk]),
                .init("Library/Containers/*/Data/Library/Caches", owners: [.cachesAndLogs]),
                .init("Library/Containers/com.docker.docker/Data/Library/Caches", owners: []),
            ])
        let owners = { (path: String) in map.owners(of: root.url.appending(path: path)) }

        #expect(owners("Library/Caches/com.apple.Safari/data") == [.cachesAndLogs])
        #expect(owners("Library/Caches/Homebrew/downloads/x.tar.gz") == [.developerJunk])
        #expect(owners("Library/Caches") == [])
        #expect(owners("Library/Containers/com.example.App/Data/Library/Caches/x") == [.cachesAndLogs])
        #expect(owners("Library/Containers/com.docker.docker/Data/Library/Caches/x") == [])
    }

    /// Pairs of entries with different owners that could both match one path with equal specificity, so neither wins.
    /// Conservative: two components could match the same name if they are equal ignoring case or either is a wildcard.
    static func overlaps(in entries: [OwnershipMap.Entry]) -> [(String, String)] {
        func parts(_ entry: OwnershipMap.Entry) -> [String] { entry.pattern.split(separator: "/").map(String.init) }
        func isWildcard(_ part: String) -> Bool { part.contains { "*?[".contains($0) } }
        func literals(_ entry: OwnershipMap.Entry) -> Int { parts(entry).filter { !isWildcard($0) }.count }

        var found: [(String, String)] = []
        for (index, first) in entries.enumerated() {
            for second in entries[(index + 1)...] where first.owners != second.owners {
                let (a, b) = (parts(first), parts(second))
                guard a.count == b.count, literals(first) == literals(second) else { continue }
                let couldMatchSamePath = zip(a, b).allSatisfy {
                    $0.caseInsensitiveCompare($1) == .orderedSame || isWildcard($0) || isWildcard($1)
                }
                if couldMatchSamePath { found.append((first.pattern, second.pattern)) }
            }
        }
        return found
    }
}
