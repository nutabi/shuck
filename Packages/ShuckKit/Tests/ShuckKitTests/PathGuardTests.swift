import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The path guard's test matrix (SAF-007, PRD section 8.4). The fixture root is the home folder (D-41).
struct PathGuardTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    var home: URL { root.url }

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    /// The error the guard throws for `path`, recording an issue if it accepts it.
    private func rejection(
        _ path: String,
        allowedRoots: [URL]? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> PathGuardError? {
        #expect(throws: PathGuardError.self, sourceLocation: sourceLocation) {
            try pathGuard.validate(path: path, allowedRoots: allowedRoots ?? [home])
        }
    }

    private func isProtected(_ error: PathGuardError?) -> Bool {
        if case .protectedLocation = error { true } else { false }
    }

    // MARK: - Accepted targets

    @Test func acceptsAFileInsideTheAllowedRootSAF007() throws {
        let file = try root.file("Downloads/installer.dmg", size: 10)
        #expect(try pathGuard.validate(file, allowedRoots: [home]) == file)
        #expect(try pathGuard.validate(file, allowedRoots: [home.appending(path: "Downloads")]) == file)
    }

    @Test func acceptsAPathThatDoesNotExistYetSAF007() throws {
        // A restore destination whose parent folders are gone (HIS-003).
        let destination = home.appending(path: "Documents/Gone/report.pdf")
        #expect(try pathGuard.validate(destination, allowedRoots: [home]) == destination)
    }

    @Test func acceptsASymlinkToAFileInsideTheRootAndReturnsTheLinkSAF007() throws {
        let report = try root.file("Documents/report.pdf")
        let link = try root.symlink("Desktop/report.pdf", to: report)
        #expect(try pathGuard.validate(link, allowedRoots: [home]) == link)
    }

    // MARK: - (a) Empty, root and home

    @Test func rejectsEmptyRootAndHomeSAF007() {
        #expect(rejection("") == .emptyPath)
        for path in ["/", "//", "/./", "/."] {
            #expect(rejection(path) == .rootFolder)
        }
        for path in [home.path, home.path + "/", home.path + "/."] {
            #expect(rejection(path) == .homeFolder)
        }
    }

    @Test func rejectsPathsBuiltFromAnEmptyVariableSAF007() {
        // The Steam bug pattern: a variable that should hold a folder is empty.
        let empty = ""
        #expect(rejection("\(empty)") == .emptyPath)
        #expect(rejection("/\(empty)") == .rootFolder)
        #expect(rejection("\(home.path)/\(empty)") == .homeFolder)
        #expect(isProtected(rejection("\(empty)/Library")))
    }

    // MARK: - (b) Relative paths and ..

    @Test(arguments: ["Documents/report.pdf", "~/Documents/report.pdf", "./report.pdf"])
    func rejectsRelativePathsSAF007(path: String) {
        #expect(rejection(path) == .notAbsolute(path))
    }

    @Test func rejectsURLsThatAreNotFileURLsSAF007() throws {
        let url = try #require(URL(string: "https://example.com/report.pdf"))
        let error = #expect(throws: PathGuardError.self) { try pathGuard.validate(url, allowedRoots: [home]) }
        #expect(error == .notAbsolute(url.absoluteString))
    }

    @Test func rejectsParentReferencesSAF007() {
        let path = home.path + "/Documents/../.ssh/id_ed25519"
        #expect(rejection(path) == .parentReference(path))
        #expect(rejection("/..") == .parentReference("/.."))
    }

    // MARK: - (c) Allowed roots and symlinks

    @Test func rejectsPathsOutsideTheAllowedRootsSAF007() throws {
        let downloads = home.appending(path: "Downloads")
        let document = home.appending(path: "Documents/report.pdf").path
        #expect(rejection(document, allowedRoots: [downloads]) == .outsideAllowedRoots(document))
        #expect(rejection(downloads.path, allowedRoots: [downloads]) == .outsideAllowedRoots(downloads.path))
        let lookalike = home.appending(path: "Downloads2/movie.mov").path
        #expect(rejection(lookalike, allowedRoots: [downloads]) == .outsideAllowedRoots(lookalike))
        #expect(rejection(document, allowedRoots: []) == .outsideAllowedRoots(document))
    }

    @Test func rejectsATargetReachedThroughASymlinkOutsideTheRootSAF007() throws {
        let other = try FixtureRoot()
        let victim = try other.file("victim.txt")
        try root.symlink("Linked", to: other.url)
        let path = home.appending(path: "Linked/victim.txt").path
        #expect(rejection(path) == .outsideAllowedRoots(victim.path))
    }

    @Test func rejectsASymlinkPointingOutsideTheRootSAF007() throws {
        let other = try FixtureRoot()
        let victim = try other.file("victim.txt")
        let link = try root.symlink("Downloads/victim.txt", to: victim)
        #expect(rejection(link.path) == .outsideAllowedRoots(victim.path))

        let system = try root.symlink("Downloads/bin", to: URL(filePath: "/usr/bin"))
        #expect(isProtected(rejection(system.path)))
    }

    @Test func rejectsDanglingSymlinksSAF007() throws {
        let missing = home.appending(path: "Documents/missing")
        let link = try root.symlink("Downloads/dangling", to: missing)
        #expect(rejection(link.path) == .unresolvable(link.path))
        let through = link.appending(path: "file.txt").path
        #expect(rejection(through) == .unresolvable(through))
    }

    // MARK: - (d) Protected locations

    @Test(arguments: PathGuardConfiguration.homeLocations)
    func rejectsProtectedLocationsInTheHomeFolderSAF007(location: String) {
        let protected = home.appending(path: location)
        #expect(rejection(protected.path) == .protectedLocation(protected.path, protected: protected.path))
        let inner = protected.appending(path: "inner/file").path
        #expect(rejection(inner) == .protectedLocation(inner, protected: protected.path))
    }

    /// D-70: every build protects both builds' data folders, so a debug build never acts on the release build's log.
    @Test func protectsTheDataFolderOfEveryBuildSAF007() {
        for bundleID in ["me.nutabi.shuck", "me.nutabi.shuck.debug"] {
            let folder = home.appending(path: "Library/Application Support/\(bundleID)/history.jsonl").path
            #expect(isProtected(rejection(folder)), "\(bundleID)")
        }
    }

    @Test(arguments: PathGuardConfiguration.systemLocations.filter { $0 != "/private" })
    func rejectsSystemLocationsSAF007(location: String) {
        let path = location + "/inner/file"
        let roots = [URL(filePath: "/")]
        #expect(rejection(path, allowedRoots: roots) == .protectedLocation(path, protected: location))
    }

    /// DEV-007: the stores a tool manages are refused, even when a rule or a sub-tool's roots would reach them.
    @Test(arguments: [
        "Library/Developer/CoreSimulator/Devices/ABCD-1234/data/Containers/Data/Application/App/Documents/note.txt",
        "Library/Developer/CoreSimulator/Devices/ABCD-1234",
        "Library/Developer/CoreSimulator/Devices",
        "Library/Developer/CoreSimulator/Volumes/iOS_21C62",
        "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
        "Library/Group Containers/group.com.docker/settings.json",
    ])
    func rejectsStoresAToolManagesDEV007(path: String) {
        let target = home.appending(path: path).path
        #expect(isProtected(rejection(target)))
        // Not even a rule whose roots lie outside the home folder's Library reaches them.
        #expect(isProtected(rejection(target, allowedRoots: [home.appending(path: "Library/Developer")])))
    }

    @Test func rejectsHomebrewsCellarDEV007() {
        let roots = [URL(filePath: "/")]
        for path in ["/opt/homebrew/Cellar/wget/1.24/bin/wget", "/opt/homebrew/Cellar", "/usr/local/Cellar/wget"] {
            #expect(isProtected(rejection(path, allowedRoots: roots)), "\(path)")
        }
    }

    @Test func theSimulatorsCachesNextToTheDevicesAreNotProtectedDEV007() throws {
        let cache = try root.file("Library/Developer/CoreSimulator/Caches/dyld/cache", size: 10)
        let allowed = [home.appending(path: "Library/Developer/CoreSimulator/Caches")]
        #expect(try pathGuard.validate(cache, allowedRoots: allowed) == cache)
    }

    @Test func rejectsFoldersThatContainAProtectedLocationSAF007() {
        #expect(isProtected(rejection(home.appending(path: "Library").path)))
        #expect(isProtected(rejection(home.appending(path: "Music").path)))
        #expect(isProtected(rejection(home.appending(path: ".config").path)))
    }

    @Test(arguments: [
        "Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
        "Pictures/Archive/Old.PhotosLibrary",
        "Pictures/iPhoto Library.photolibrary",
        "Music/Elsewhere/Music Library.musiclibrary",
        "Movies/Elsewhere/TV Library.tvlibrary",
        "Backups/Mac.backupbundle",
        "Backups/Backups.backupdb/Mac/Latest",
    ])
    func rejectsProtectedBundlesWhereverTheyAreSAF007(path: String) {
        #expect(isProtected(rejection(home.appending(path: path).path)))
    }

    @Test(arguments: [
        ".SSH", ".SSH/id_ed25519", "Library/KEYCHAINS", "Library/Keychains/LOGIN.keychain-db", "LIBRARY",
        "Library/Mobile documents/Notes", ".AWS/credentials",
    ])
    func rejectsProtectedLocationsSpelledInAnotherCaseSAF007(path: String) throws {
        // On disk, .ssh and Library/Keychains exist with their usual case; .aws does not exist at all.
        try root.file(".ssh/id_ed25519")
        try root.file("Library/Keychains/login.keychain-db")
        #expect(isProtected(rejection(home.appending(path: path).path)))
    }

    /// D-135: a folder is refused when a protected bundle or name is among its direct children.
    @Test(arguments: [
        "Photos Library.photoslibrary", "Old.PHOTOSLIBRARY", "Music Library.musiclibrary", "Mac.backupbundle",
        "BACKUPS.BACKUPDB", ".hidden.tvlibrary",
    ])
    func rejectsAFolderWithAProtectedBundleAmongItsChildrenSAF007(name: String) throws {
        let trip = try root.folder("Pictures/Trip")
        try root.file("Pictures/Trip/beach.jpg")
        let bundle = try root.folder("Pictures/Trip/\(name)")
        #expect(rejection(trip.path) == .protectedLocation(trip.path, protected: bundle.path))
    }

    /// D-135: only direct children are looked at; a deeper search would make every check as slow as a scan.
    @Test func looksForProtectedBundlesAmongDirectChildrenOnlySAF007() throws {
        let pictures = try root.folder("Pictures")
        try root.folder("Pictures/Trip")
        try root.folder("Pictures/Trip/Old.photoslibrary")
        #expect(try pathGuard.validate(pictures, allowedRoots: [home]) == pictures)
    }

    @Test func acceptsAFolderWhoseChildrenAreOrdinarySAF007() throws {
        let folder = try root.folder("Projects/App")
        try root.file("Projects/App/photoslibrary.txt")
        try root.folder("Projects/App/Backups")
        #expect(try pathGuard.validate(folder, allowedRoots: [home]) == folder)
    }

    /// A folder Shuck may not read could hold a protected bundle, so it is refused rather than assumed empty.
    @Test func rejectsAFolderItCannotReadSAF007SAF012() throws {
        let locked = try root.folder("Documents/Locked", permissions: 0o000)
        #expect(rejection(locked.path) == .notReadable(locked.path))
    }

    /// A symlink is never listed; its destination is checked as a folder of its own.
    @Test func rejectsASymlinkToAFolderWithAProtectedBundleSAF007() throws {
        let trip = try root.folder("Pictures/Trip")
        let bundle = try root.folder("Pictures/Trip/Old.photoslibrary")
        let link = try root.symlink("Desktop/Trip", to: trip)
        #expect(rejection(link.path) == .protectedLocation(trip.path, protected: bundle.path))
    }

    @Test func rejectsProtectedNamesInAnotherCaseOnDiskSAF007() throws {
        let backup = try root.folder("Backups/BACKUPS.BACKUPDB")
        #expect(isProtected(rejection(backup.appending(path: "Mac/Latest").path)))
        #expect(isProtected(rejection(home.appending(path: "Pictures/Old.PHOTOSLIBRARY").path)))
    }

    @Test func rejectsTheHomeFolderInAnotherCaseSAF007() {
        #expect(rejection(home.path.uppercased()) == .homeFolder)
    }

    @Test func matchesUserExclusionsAcrossCaseAndUnicodeFormsSAF007() {
        // "é" as one character (NFC) in the exclusion, and as "e" plus a combining accent (NFD) in the target.
        let keep = home.appending(path: "Documents/Caf\u{E9}")
        let guarded = PathGuard(configuration: root.pathGuardConfiguration(userExclusions: [keep]))
        for name in ["Cafe\u{301}", "CAF\u{C9}"] {
            let path = home.appending(path: "Documents/\(name)/menu.pdf").path
            let error = #expect(throws: PathGuardError.self) { try guarded.validate(path: path, allowedRoots: [home]) }
            #expect(error == .protectedLocation(path, protected: keep.path))
        }
        let sharpS = PathGuard(
            configuration: root.pathGuardConfiguration(userExclusions: [home.appending(path: "Stra\u{DF}e")]))
        #expect(throws: PathGuardError.self) {
            try sharpS.validate(path: home.appending(path: "STRASSE/map.pdf").path, allowedRoots: [home])
        }
    }

    /// SET-001: a scan compares a command's folder with the exclusions as the guard compares a path.
    @Test func overlapsUserExclusionIsTrueInsideAndAboveAnExclusionOnlySET001() {
        let configuration = root.pathGuardConfiguration(userExclusions: [home.appending(path: "Documents/Caf\u{E9}")])

        #expect(configuration.overlapsUserExclusion(home.appending(path: "Documents/Cafe\u{301}/menu.pdf")))
        #expect(configuration.overlapsUserExclusion(home.appending(path: "DOCUMENTS")))
        #expect(!configuration.overlapsUserExclusion(home.appending(path: "Documents/Cafeteria")))
        #expect(!configuration.overlapsUserExclusion(home.appending(path: "Downloads")))
        // Shuck's own protected locations are not the user's.
        #expect(!configuration.overlapsUserExclusion(home.appending(path: ".ssh")))
        #expect(!root.pathGuardConfiguration().overlapsUserExclusion(home))
    }

    @Test func allowedRootsStayCaseSensitiveSAF007() {
        let downloads = home.appending(path: "Downloads")
        let path = home.appending(path: "DOWNLOADS/movie.mov").path
        #expect(rejection(path, allowedRoots: [downloads]) == .outsideAllowedRoots(path))
    }

    @Test func rejectsShucksOwnAppBundleSAF007() {
        let app = home.appending(path: "Applications/Shuck.app")
        let path = app.appending(path: "Contents/MacOS/Shuck").path
        #expect(rejection(path) == .protectedLocation(path, protected: app.path))
    }

    @Test func rejectsLocationsTheUserExcludedSAF007() throws {
        let keep = home.appending(path: "Documents/Keep")
        let file = try root.file("Documents/Keep/thesis.pdf")
        #expect(try pathGuard.validate(file, allowedRoots: [home]) == file)

        let excluding = PathGuard(configuration: root.pathGuardConfiguration(userExclusions: [keep]))
        let error = #expect(throws: PathGuardError.self) { try excluding.validate(file, allowedRoots: [home]) }
        #expect(error == .protectedLocation(file.path, protected: keep.path))
    }

    // MARK: - D-41: the test configuration differs from production only by /private

    @Test func productionConfigurationRejectsTheTemporaryFolderSAF007() throws {
        let file = try root.file("Documents/report.pdf")
        let production = PathGuard(
            configuration: .production(
                home: home, appBundle: home.appending(path: "Applications/Shuck.app"), userExclusions: [])
        )
        let error = #expect(throws: PathGuardError.self) { try production.validate(file, allowedRoots: [home]) }
        #expect(error == .protectedLocation(file.path, protected: "/private"))
    }

    @Test func testConfigurationDropsOnlyPrivateSAF007() {
        let test = root.pathGuardConfiguration()
        let production = PathGuardConfiguration.production(
            home: home, appBundle: home.appending(path: "Applications/Shuck.app"), userExclusions: [])
        #expect(test.home == production.home)
        let dropped = Set(production.protectedLocations.map(\.path)).subtracting(test.protectedLocations.map(\.path))
        #expect(dropped == ["/private"])
        #expect(test.protectedLocations.count == production.protectedLocations.count - 1)
    }

    // MARK: - (e) Other volumes

    @Test func rejectsPathsOnAnotherVolumeSAF007() throws {
        // /dev is its own file system on every Mac, so it stands in for an external drive.
        #expect(rejection("/dev/null", allowedRoots: [URL(filePath: "/dev")]) == .otherVolume("/dev/null"))
        try root.symlink("Devices", to: URL(filePath: "/dev"))
        #expect(rejection(home.appending(path: "Devices/null").path) == .otherVolume("/dev/null"))
    }

    /// D-135: a volume mounted at the target is refused, although the folder it is mounted in is on the startup volume.
    /// /dev is mounted at a folder of the root file system, as a disk image would be inside the home folder.
    @Test func rejectsATargetThatIsItselfAMountPointSAF007() {
        #expect(rejection("/dev", allowedRoots: [URL(filePath: "/")]) == .otherVolume("/dev"))
    }
}
