import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Developer Junk's first rule, Xcode DerivedData: one item per project (DEV-R01, DEV-008, DEV-005).
struct DeveloperJunkTests {
    let root: FixtureRoot
    let now = Date.now
    let longAgo = Date.now.addingTimeInterval(-31 * 86_400)
    let hash = "abcdefghijklmnopqrstuvwxyzab"

    init() throws {
        root = try FixtureRoot()
    }

    private func scan(running: Set<String> = []) async -> [ScanEvent] {
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running))
        var events: [ScanEvent] = []
        for await event in DeveloperJunk().scan(context) { events.append(event) }
        return events
    }

    private func items(running: Set<String> = []) async -> [String: ScanItem] {
        var result: [String: ScanItem] = [:]
        for case .item(let item) in await scan(running: running) {
            result[item.url?.lastPathComponent ?? ""] = item
        }
        return result
    }

    private func reason(_ item: ScanItem?) -> String {
        item.map { String(localized: $0.reason) } ?? ""
    }

    @Test func eachProjectIsOneItemSelectedWhenStaleOrWhenItsProjectIsGoneDEV005DEV008() async throws {
        let project = try root.folder("Projects/Live")
        try root.derivedDataProject("Live-\(hash)", workspace: project, modified: now)
        try root.derivedDataProject("Old-\(hash)", workspace: project, modified: longAgo)
        let gone = try root.url("Projects/Gone.xcodeproj")
        try root.derivedDataProject("Gone-\(hash)", workspace: gone, modified: now)
        try root.derivedDataProject("GoneAndOld-\(hash)", workspace: gone, modified: longAgo)

        let items = await items()

        #expect(Set(items.keys) == ["Live-\(hash)", "Old-\(hash)", "Gone-\(hash)", "GoneAndOld-\(hash)"])
        #expect(items["Live-\(hash)"]?.selection == .unselected)
        #expect(items["Old-\(hash)"]?.selection == .selected)
        #expect(items["Gone-\(hash)"]?.selection == .selected)
        #expect(items["GoneAndOld-\(hash)"]?.selection == .selected)
        #expect(reason(items["Gone-\(hash)"]) == "Its project is no longer on this Mac.")
        #expect(reason(items["Old-\(hash)"]) == "Not built for 30 days or more.")
        #expect(
            reason(items["Live-\(hash)"])
                == "Xcode builds this project again when you next need it. Its Swift package checkouts go too, and Xcode needs an internet connection to download them again. Its compilation cache goes too, so the next build is slower."
        )
        // DEV-R01 and DEV-005: the explanation names both the package checkouts and the compilation cache.
        let explanation = reason(items["Live-\(hash)"])
        #expect(explanation.contains("Swift package checkouts") && explanation.contains("compilation cache"))
        // Each row names its project's path, so two projects of one name differ (D-138).
        #expect(items["Live-\(hash)"]?.project?.path == project.path)
        #expect(items["Gone-\(hash)"]?.project?.path == gone.path)
        for item in items.values {
            #expect(item.tier == .rebuildable && item.method == .delete && item.source == .developerJunk)
            #expect(item.snapshot?.kind == .folder && item.allocatedSize >= 4096)
            #expect(item.ruleMatch?.rule.id == "DEV-R01" && item.apps == ["com.apple.dt.Xcode"])
            #expect(item.category.id == "xcode")
        }
    }

    @Test func aProjectWithRecentBuildsDeepInsideIsNotStaleDEV005() async throws {
        let folder = try root.derivedDataProject(
            "Busy-\(hash)", workspace: root.folder("Projects/Busy"), modified: longAgo)
        // A rebuild changes files in Build/Products, not the project folder's own date.
        try FileManager.default.setAttributes(
            [.modificationDate: now], ofItemAtPath: folder.appending(path: "Build/Products").path)

        let item = try #require(await items()["Busy-\(hash)"])

        #expect(item.selection == .unselected)
        // The date kept for re-validation is the folder's own (SAF-008).
        #expect(item.ruleMatch?.modified == RuleMatch.modificationDate(at: folder))
        #expect(try #require(item.ruleMatch?.modified) < now.addingTimeInterval(-86_400))
    }

    @Test func aProjectIsGoneOnlyWhenTheSystemSaysItIsNotThereDEV008() async throws {
        let live = try root.folder("Projects/Live")
        let missing = try root.url("Projects/Missing")
        let file = try root.file("Projects/file")
        let away = URL(filePath: "/Volumes/ShuckNoSuchDisk/App.xcodeproj")
        // Unreadable plist or none: nothing to judge by, so not flagged and not selected unless stale.
        try root.derivedDataProject("NoPlist-\(hash)", workspace: nil, modified: now)
        let broken = try root.derivedDataProject("Broken-\(hash)", workspace: live, modified: now)
        try Data("not a plist".utf8).write(to: broken.appending(path: "info.plist"))
        // A project on a disk that is not connected is away, not gone.
        try root.derivedDataProject("Away-\(hash)", workspace: away, modified: now)
        // A file where a folder should be: the path cannot exist.
        try root.derivedDataProject("Below-\(hash)", workspace: file.appending(path: "App.xcodeproj"), modified: now)
        try root.derivedDataProject("Missing-\(hash)", workspace: missing, modified: now)

        let items = await items()

        #expect(items["NoPlist-\(hash)"]?.selection == .unselected)
        #expect(items["Broken-\(hash)"]?.selection == .unselected)
        #expect(items["Away-\(hash)"]?.selection == .unselected)
        #expect(items["Below-\(hash)"]?.selection == .selected)
        #expect(items["Missing-\(hash)"]?.selection == .selected)
    }

    @Test func aRunningXcodeDisablesEveryProjectSAF009() async throws {
        try root.derivedDataProject("Old-\(hash)", workspace: nil, modified: longAgo)

        let items = await items(running: ["com.apple.dt.xcode"])

        #expect(items.values.map(\.selection) == [.appIsRunning(nil)])
    }

    @Test func onlyFoldersAreListedAndOnlyWhenDerivedDataExistsDEV002() async throws {
        #expect(await scan().isEmpty)
        try root.derivedDataProject("Real-\(hash)", workspace: nil, modified: longAgo)
        try root.file("Library/Developer/Xcode/DerivedData/stray.txt", size: 10)
        try root.symlink("Library/Developer/Xcode/DerivedData/Link", to: root.folder("Elsewhere"))

        let items = await items()

        #expect(Set(items.keys) == ["Real-\(hash)"])
    }

    @Test func aScanLeavesOutFoldersTheMapGivesAnotherSubToolFCL005() async throws {
        try root.derivedDataProject("Mine-\(hash)", workspace: nil, modified: longAgo)
        let context = ScanContext(
            home: root.url, ownership: OwnershipMap(home: root.url, entries: []),
            protection: root.pathGuardConfiguration())
        var found = 0
        for await event in DeveloperJunk().scan(context) {
            if case .item = event { found += 1 }
        }
        #expect(found == 0)
        let map = OwnershipMap(home: root.url)
        #expect(map.owners(of: try root.url("Library/Developer/Xcode/DerivedData/Mine")) == [.developerJunk])
        #expect(map.owners(of: try root.url("Library/Developer/Xcode/UserData/Snippets")).isEmpty)
    }

    @Test(arguments: [
        ("MyApp-abcdefghijklmnopqrstuvwxyzab", "MyApp"), ("My-App-abcdefghijklmnopqrstuvwxyzab", "My-App"),
        ("ModuleCache.noindex", "ModuleCache.noindex"), ("Short-abc", "Short-abc"),
        ("-abcdefghijklmnopqrstuvwxyzab", "-abcdefghijklmnopqrstuvwxyzab"),
    ])
    func theProjectNameDropsXcodesHashDEV008(folder: String, name: String) {
        #expect(DerivedDataProject.name(ofFolder: folder) == name)
    }

    @Test func projectFoldersOutsideTheHomeFolderOrRepeatedAreIgnoredSET003() throws {
        let inside = try root.url("Developer")
        let outside = URL(filePath: "/Users/someone/Projects")
        let junk = DeveloperJunk(projectFolders: [
            inside, root.url, outside, inside, root.url.appending(path: "Developer/../Code"),
        ])

        #expect(junk.projects(home: root.url) == [inside])
        #expect(DeveloperJunk().projects(home: root.url).isEmpty)
    }

    @Test func aProjectFolderKeepsItsRootUnlessItLeavesTheHomeFolderSAF007() throws {
        let kept = try root.folder("Developer")
        let outside = try FixtureRoot()
        let elsewhere = try outside.folder("Projects")
        let linked = try root.symlink("Code", to: elsewhere)
        let junk = DeveloperJunk(projectFolders: [kept, linked])

        #expect(junk.projects(home: root.url) == [kept, linked])
        let roots = junk.allowedRoots(home: root.url)
        #expect(roots.contains(kept))
        #expect(!roots.contains(linked))
        #expect(roots.contains { $0.lastPathComponent == "Archives" })
    }

    private func notAccessible(excluding exclusions: [URL] = []) async -> (denied: [String], items: Set<String>) {
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(userExclusions: exclusions),
            runningApps: StubRunningApps([]))
        var denied: [String] = []
        var items: Set<String> = []
        for await event in DeveloperJunk().scan(context) {
            switch event {
            case .notAccessible(let url): denied.append(url.lastPathComponent)
            case .item(let item): items.insert(item.url?.lastPathComponent ?? "")
            default: break
            }
        }
        return (denied, items)
    }

    @Test func aFolderShuckMayNotReadIsReportedNotListedSAF011SAF012() async throws {
        try root.derivedDataProject("Open-\(hash)", workspace: nil, modified: longAgo)
        try root.folder("Library/Developer/Xcode/DerivedData/Locked-\(hash)", permissions: 0o000)

        let result = await notAccessible()

        #expect(result.denied == ["Locked-\(hash)"])
        #expect(result.items == ["Open-\(hash)"])
    }

    @Test func aFolderAnExclusionHidesIsNotReportedSAF011SAF012() async throws {
        try root.derivedDataProject("Open-\(hash)", workspace: nil, modified: longAgo)
        let locked = try root.folder("Library/Developer/Xcode/DerivedData/Locked-\(hash)", permissions: 0o000)

        let result = await notAccessible(excluding: [locked])

        #expect(result.denied.isEmpty)
        #expect(result.items == ["Open-\(hash)"])
    }
}
