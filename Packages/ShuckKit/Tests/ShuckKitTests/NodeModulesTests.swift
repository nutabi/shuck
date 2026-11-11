import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Developer Junk's stale `node_modules` rule: one Delete item per project with a lockfile, in the project folders
/// (DEV-R06, DEV-006, SET-003, FCL-005, D-152, D-153).
struct NodeModulesTests {
    let root: FixtureRoot
    let longAgo = Date.now.addingTimeInterval(-40 * 86_400)

    init() throws {
        root = try FixtureRoot()
    }

    private func context(
        projects: [String] = ["Developer"], exclusions: [String] = [], mapKnowsProjects: Bool = true
    ) throws -> ScanContext {
        let folders = try projects.map(root.url)
        return ScanContext(
            home: root.url,
            ownership: OwnershipMap(home: root.url, projectFolders: mapKnowsProjects ? folders : []),
            protection: root.pathGuardConfiguration(userExclusions: try exclusions.map(root.url)),
            runningApps: StubRunningApps([]))
    }

    /// The items by their project's path inside the root.
    private func scan(
        projects: [String] = ["Developer"], exclusions: [String] = [], mapKnowsProjects: Bool = true
    ) async throws -> [String: ScanItem] {
        let folders = try projects.map(root.url)
        let context = try context(projects: projects, exclusions: exclusions, mapKnowsProjects: mapKnowsProjects)
        var result: [String: ScanItem] = [:]
        for await event in DeveloperJunk(projectFolders: folders).scan(context) {
            guard case .item(let item) = event, item.ruleMatch?.rule.id == "DEV-R06" else { continue }
            let project = try #require(item.project)
            result[String(project.path.dropFirst(root.url.path.count + 1))] = item
        }
        return result
    }

    private func words(_ item: ScanItem?) -> String {
        item.map { String(localized: $0.reason) } ?? ""
    }

    @Test func aStaleProjectIsOneSelectedDeleteItemDEVR06() async throws {
        let project = try root.nodeProject("Developer/app", edited: longAgo, size: 8192)

        let items = try await scan()
        let item = try #require(items["Developer/app"])

        #expect(items.count == 1)
        #expect(item.url?.path == project.appending(path: "node_modules").path)
        #expect(item.tier == .rebuildable && item.method == .delete && item.source == .developerJunk)
        #expect(item.selection == .selected)
        #expect(item.snapshot?.kind == .folder && item.allocatedSize >= 8192)
        #expect(item.modified != nil && item.identity == nil && item.apps.isEmpty)
        #expect(item.category.id == "node-projects")
        #expect(item.ruleMatch?.rule.id == "DEV-R06" && item.ruleMatch?.rule.apps.isEmpty == true)
        // Shuck has no network, so the row says that restoring needs an install and a connection.
        #expect(words(item).contains("npm install") && words(item).contains("internet connection"))
    }

    /// `node_modules` was just made, as an install does; the project's own files say it was left alone (DEV-006).
    @Test func staleIsTheNewestOfTheProjectsOwnFilesNotTheFoldersDateDEV006() async throws {
        try root.nodeProject("Developer/idle", edited: longAgo)
        try root.nodeProject("Developer/busy", edited: longAgo)
        try root.file("Developer/busy/src/deep/new.js", size: 8, modified: .now.addingTimeInterval(-3_600))
        try root.nodeProject("Developer/fresh", edited: .now)

        let items = try await scan()

        #expect(items["Developer/idle"]?.selection == .selected)
        #expect(items["Developer/busy"]?.selection == .unselected)
        #expect(items["Developer/fresh"]?.selection == .unselected)
        #expect(items.count == 3)
    }

    @Test func nothingThatIsNotTheProjectsOwnWorkMakesItActiveDEV006() async throws {
        try root.nodeProject("Developer/app", edited: longAgo)
        // Finder, Git and the packages themselves change without anyone working on the project.
        try root.file("Developer/app/.DS_Store", size: 8)
        try root.file("Developer/app/.git/index", size: 8)
        try root.file("Developer/app/node_modules/dep/new.js", size: 8)
        try root.file("Developer/app/src/.DS_Store", size: 8)

        #expect(try await scan()["Developer/app"]?.selection == .selected)
    }

    @Test(arguments: NodeProject.lockfiles)
    func anyLockfileNextToItAllowsTheItemButNoneDoesNotDEV006(lockfile: String) async throws {
        try root.nodeProject("Developer/with", lockfile: lockfile, edited: longAgo)
        try root.nodeProject("Developer/without", lockfile: nil, edited: longAgo)
        // A lockfile elsewhere, or a link, is not one next to it.
        try root.nodeProject("Developer/parent/child", lockfile: nil, edited: longAgo)
        try root.file("Developer/parent/\(lockfile)", size: 8)
        try root.nodeProject("Developer/linked", lockfile: nil, edited: longAgo)
        try root.symlink("Developer/linked/\(lockfile)", to: try root.url("Developer/with/\(lockfile)"))

        let items = try await scan()

        #expect(Set(items.keys) == ["Developer/with"])
    }

    @Test func onlyTheTopMostNodeModulesOfAProjectIsTakenDEV006() async throws {
        let mono = try root.nodeProject("Developer/mono", edited: longAgo)
        try root.nodeProject("Developer/mono/packages/a", edited: longAgo)
        try root.file("Developer/mono/node_modules/dep/node_modules/inner/index.js", size: 8)
        // Folders without one of their own are not projects: each project below them is.
        try root.nodeProject("Developer/group/one", edited: longAgo)
        try root.nodeProject("Developer/group/two", edited: longAgo)

        let items = try await scan()

        #expect(Set(items.keys) == ["Developer/mono", "Developer/group/one", "Developer/group/two"])
        #expect(items["Developer/mono"]?.url?.path == mono.appending(path: "node_modules").path)
    }

    @Test func aProjectFolderMayBeAProjectItselfDEV006() async throws {
        try root.nodeProject("Code", edited: longAgo)

        #expect(try await scan(projects: ["Code"]).keys.sorted() == ["Code"])
    }

    @Test func aProjectRootLiesAtMostFourLevelsBelowTheProjectFolderDEV006() async throws {
        try root.nodeProject("Developer/a/b/c/d", edited: longAgo)
        try root.nodeProject("Developer/a/b/c/d/e/f", edited: longAgo)
        try root.nodeProject("Developer/w/x/y/z/deep", edited: longAgo)

        let items = try await scan()

        #expect(Set(items.keys) == ["Developer/a/b/c/d"])
        // A plan and a run check the pattern again, so a deeper one is refused even if something listed it.
        let rule = try DeveloperJunk.nodeModulesRule(projectFolder: root.url("Developer"))
        let deeper = try root.url("Developer/w/x/y/z/deep/node_modules")
        #expect(!rule.accepts(.path(deeper), tier: .rebuildable, method: .delete, scope: .item))
        let inside = try root.url("Developer/a/b/c/d/node_modules")
        #expect(rule.accepts(.path(inside), tier: .rebuildable, method: .delete, scope: .item))
    }

    @Test func linksPackagesGitAndOtherFoldersAreNotEnteredDEV006() async throws {
        let elsewhere = try root.nodeProject("Elsewhere/app", edited: longAgo)
        try root.symlink("Developer/linked", to: elsewhere.deletingLastPathComponent())
        try root.nodeProject("Developer/Tool.app/Contents/app", edited: longAgo)
        try root.nodeProject("Developer/real/.git/modules/app", edited: longAgo)
        // `node_modules` that is itself a link is no `node_modules`.
        try root.file("Developer/odd/package.json", size: 8)
        try root.file("Developer/odd/package-lock.json", size: 8, modified: longAgo)
        try root.symlink("Developer/odd/node_modules", to: elsewhere.appending(path: "node_modules"))

        #expect(try await scan().isEmpty)
    }

    @Test func aProjectFolderThatIsALinkIsNotFollowedSET003() async throws {
        let elsewhere = try root.nodeProject("Elsewhere/app", edited: longAgo)
        try root.symlink("Developer", to: elsewhere.deletingLastPathComponent())

        #expect(try await scan().isEmpty)
    }

    @Test func onlyTheProjectFoldersAreScannedDEV006() async throws {
        try root.nodeProject("Documents/site", edited: longAgo)
        try root.nodeProject("Developer/app", edited: longAgo)
        try root.nodeProject("Other/app", edited: longAgo)

        #expect(try await scan().keys.sorted() == ["Developer/app"])
        #expect(try await scan(projects: []).isEmpty)
    }

    @Test func aScanLeavesOutNodeModulesTheMapDoesNotGiveToDeveloperJunkFCL005() async throws {
        try root.nodeProject("Developer/app", edited: longAgo)

        #expect(try await scan(mapKnowsProjects: false).isEmpty)
    }

    @Test func anExcludedFolderIsNeitherListedNorEnteredNorCountedSET001() async throws {
        try root.nodeProject("Developer/Excluded/app", edited: longAgo)
        try root.nodeProject("Developer/Kept", edited: longAgo)
        try root.nodeProject("Developer/Holder/app", edited: longAgo)
        try root.nodeProject("Developer/Holder/Secret/app", edited: longAgo)
        // A recent file in an excluded folder of a project does not make the project active.
        try root.file("Developer/Kept/src/Private/notes.txt", size: 8, modified: .now)

        let items = try await scan(exclusions: [
            "Developer/Excluded", "Developer/Kept/src/Private", "Developer/Holder/Secret",
        ])

        #expect(Set(items.keys) == ["Developer/Kept", "Developer/Holder/app"])
        #expect(items["Developer/Kept"]?.selection == .selected)
    }

    @Test func aProjectThatHoldsAnExcludedFolderInsideNodeModulesIsHiddenSET001() async throws {
        try root.nodeProject("Developer/app", edited: longAgo)

        #expect(try await scan(exclusions: ["Developer/app/node_modules/dep"]).isEmpty)
    }

    @Test(arguments: [
        ("{\"devDependencies\": {\"patch-package\": \"^8.0.0\"}}", "patch-package"),
        ("{\"dependencies\": {\"patch-package\": \"8.0.0\"}}", "patch-package"),
        ("{\"scripts\": {\"postinstall\": \"patch-package\"}}", "patch-package"),
        ("{\"dependencies\": {\"shared\": \"file:../shared\"}}", "file:"),
        ("{\"devDependencies\": {\"shared\": \"FILE:../shared\"}}", "file:"),
        ("{\"scripts\": {\"postinstall\": \"patch-package\"}, \"dependencies\": {\"x\": \"file:../x\"}}", "both"),
    ])
    func aProjectThatAReinstallWouldNotFullyRestoreIsListedUnselectedAndWarnedDEV006(
        manifest: String, mentions: String
    ) async throws {
        try root.nodeProject("Developer/app", manifest: manifest, edited: longAgo)

        let item = try #require(try await scan()["Developer/app"])

        #expect(item.selection == .unselected)
        let text = words(item)
        #expect(text.contains("npm install") && text.contains("internet connection"))
        switch mentions {
        case "both": #expect(text.contains("patch-package") && text.contains("file:"))
        case "file:": #expect(text.contains("file:") && !text.contains("patch-package"))
        default: #expect(text.contains("patch-package") && !text.contains("file:"))
        }
    }

    @Test func aPatchesFolderWithPatchFilesWarnsEvenWithoutAScriptDEV006() async throws {
        try root.nodeProject("Developer/patched", edited: longAgo)
        try root.file("Developer/patched/patches/left-pad+1.3.0.patch", size: 8, modified: longAgo)
        try root.nodeProject("Developer/plain", edited: longAgo)
        try root.file("Developer/plain/patches/notes.txt", size: 8, modified: longAgo)

        let items = try await scan()

        #expect(items["Developer/patched"]?.selection == .unselected)
        #expect(words(items["Developer/patched"]).contains("patch-package"))
        #expect(items["Developer/plain"]?.selection == .selected)
    }

    @Test func aPackageJsonShuckCannotReadMakesTheItemUnselectedAndSaysSoDEV006() async throws {
        try root.nodeProject("Developer/broken", manifest: "{not json", edited: longAgo)
        try root.nodeProject("Developer/list", manifest: "[]", edited: longAgo)

        let items = try await scan()

        for name in ["Developer/broken", "Developer/list"] {
            #expect(items[name]?.selection == .unselected)
            #expect(words(items[name]).contains("could not read"))
        }
    }

    @Test func aWalkThatStopsEarlyNeverMakesAProjectLookStaleDEV006() throws {
        let project = try root.nodeProject("Developer/app", edited: longAgo)
        let full = NodeProject.newestActivity(in: project, isSkipped: { _ in false }, shouldContinue: { true })
        let cut = NodeProject.newestActivity(in: project, limit: 2, isSkipped: { _ in false }, shouldContinue: { true })
        let stopped = NodeProject.newestActivity(in: project, isSkipped: { _ in false }, shouldContinue: { false })

        #expect(full != nil && cut == nil && stopped == nil)
    }

    @Test func aRunningAppDoesNotDisableTheItemBecauseTheRuleNamesNoneSAF009() async throws {
        try root.nodeProject("Developer/app", edited: longAgo)
        let context = try context()
        var found: [ScanItem] = []
        let everything = StubRunningApps(["com.apple.dt.Xcode", "com.microsoft.VSCode"])
        let scanContext = ScanContext(
            home: root.url, ownership: context.ownership, protection: context.protection, runningApps: everything)
        for await event in DeveloperJunk(projectFolders: [try root.url("Developer")]).scan(scanContext) {
            if case .item(let item) = event, item.ruleMatch?.rule.id == "DEV-R06" { found.append(item) }
        }

        #expect(found.map(\.selection) == [.selected])
    }
}
