import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Applications' tier, allowed roots and app inventory (APP-001, APP-002, SAF-007, SAF-012, SAF-016).
struct ApplicationsTests {
    let root: FixtureRoot
    let appFolders: [URL]

    init() throws {
        root = try FixtureRoot()
        // Both app folders are inside the fixture root, so no test reads the real /Applications (SAF-016).
        appFolders = [try root.url("System Apps"), try root.url("Applications")]
    }

    private func events(
        protected: Set<String> = [], lastUsed: [String: Date] = [:], owner: uid_t? = nil
    ) async -> [AppInventoryEvent] {
        let applications = Applications(
            appFolders: appFolders, isSystemProtected: { protected.contains($0.lastPathComponent) },
            lastUsedDate: { lastUsed[$0.lastPathComponent] }, owner: { _ in owner ?? getuid() })
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        var result: [AppInventoryEvent] = []
        for await event in applications.scan(context) { result.append(event) }
        return result
    }

    /// The apps found, by path relative to the fixture root.
    private func apps(
        protected: Set<String> = [], lastUsed: [String: Date] = [:], owner: uid_t? = nil
    ) async -> [String: InstalledApp] {
        var result: [String: InstalledApp] = [:]
        for case .app(let app) in await events(protected: protected, lastUsed: lastUsed, owner: owner) {
            result[String(app.url.path.dropFirst(root.url.path.count + 1))] = app
        }
        return result
    }

    @Test func allowedRootsAreTheAppFoldersAndTheLeftoverFoldersAPP002() {
        let home = URL(filePath: "/Users/someone")
        let roots = Set(Applications().allowedRoots(home: home).map(\.path))
        #expect(roots.contains("/Applications") && roots.contains("/Users/someone/Applications"))
        for folder in [
            "Application Support", "Caches", "Containers", "Group Containers", "Preferences",
            "Saved Application State", "HTTPStorages", "WebKit", "Cookies", "Logs", "Application Scripts",
            "LaunchAgents",
        ] {
            #expect(roots.contains("/Users/someone/Library/\(folder)"), "\(folder)")
        }
        #expect(roots.count == 14)
        #expect(!roots.contains("/Users/someone/Library") && !roots.contains("/Users/someone"))
    }

    @Test func listsAppsWithNameBundleIDAndSizeAPP001() async throws {
        try root.app("System Apps/Notes.app", bundleID: "com.example.Notes", name: "Notes", size: 8192)
        try root.app(
            "Applications/Mail Pro.app", bundleID: "com.example.Mail", name: "Mail", displayName: "Mail Pro",
            size: 4096)
        try root.app("Applications/Bare.app", bundleID: nil)

        let apps = await apps()
        #expect(Set(apps.keys) == ["System Apps/Notes.app", "Applications/Mail Pro.app", "Applications/Bare.app"])
        let notes = try #require(apps["System Apps/Notes.app"])
        #expect(notes.name == "Notes" && notes.bundleID == "com.example.Notes")
        #expect(notes.snapshot.kind == .folder && notes.allocatedSize >= 8192)
        #expect(notes.modified == RuleMatch.modificationDate(at: notes.url))
        #expect(apps["Applications/Mail Pro.app"]?.name == "Mail Pro")
        #expect(apps["Applications/Bare.app"]?.name == "Bare" && apps["Applications/Bare.app"]?.bundleID == nil)
    }

    @Test func readsTheVersionAndWhenTheAppWasLastOpenedAPP001() async throws {
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        try root.app("Applications/Notes.app", bundleID: "com.example.Notes", version: "2.1", build: "210")
        try root.app("Applications/Build.app", bundleID: "com.example.Build", build: "42")
        try root.app("Applications/None.app", bundleID: "com.example.None", version: "")

        let apps = await apps(lastUsed: ["Notes.app": opened])
        #expect(apps["Applications/Notes.app"]?.version == "2.1")
        #expect(apps["Applications/Notes.app"]?.lastOpened == opened)
        #expect(apps["Applications/Build.app"]?.version == "42")
        // Spotlight has no record of an app never opened; its modified date says nothing about use (D-187).
        #expect(apps["Applications/Build.app"]?.lastOpened == nil)
        #expect(apps["Applications/None.app"]?.version == nil)
    }

    @Test func sortsByNameSizeAndLastOpenedAPP009() {
        func app(_ name: String, size: Int64, opened: TimeInterval?) -> InstalledApp {
            InstalledApp(
                url: URL(filePath: "/Applications/\(name).app"), name: name, bundleID: nil,
                snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), modified: .now,
                lastOpened: opened.map(Date.init(timeIntervalSince1970:)))
        }
        let apps = [
            app("app 10", size: 300, opened: 100), app("App 9", size: 100, opened: nil),
            app("Zed", size: 200, opened: 50), app("Alpha", size: 200, opened: nil),
        ]
        func order(_ key: AppSortKey) -> [String] { apps.sorted { $0.precedes($1, by: key) }.map(\.name) }

        // Names compare as Finder compares them: numbers by value, case ignored.
        #expect(order(.name) == ["Alpha", "App 9", "app 10", "Zed"])
        // Ties fall back to the name.
        #expect(order(.size) == ["App 9", "Alpha", "Zed", "app 10"])
        // Never opened comes first.
        #expect(order(.lastOpened) == ["Alpha", "App 9", "Zed", "app 10"])
    }

    /// One app and what the check should say about it: `mode` is the bundle's, `folderMode` its folder's.
    struct RemovabilityCase: Sendable, CustomTestStringConvertible {
        let name: String
        let path: String
        var mode: Int = 0o755
        var folderMode: Int? = nil
        var owner: uid_t? = nil
        let expected: AppRemovability
        var testDescription: String { name }
    }

    @Test(
        arguments: [
            RemovabilityCase(name: "plain app", path: "Applications/Plain.app", expected: .removable),
            RemovabilityCase(
                name: "bundle not writable", path: "Applications/Locked.app", mode: 0o555,
                expected: .blocked(.bundleNotWritable)),
            RemovabilityCase(
                name: "folder not writable", path: "Applications/Tools/Inner.app", folderMode: 0o555,
                expected: .blocked(.folderNotWritable)),
            RemovabilityCase(
                name: "root-owned", path: "Applications/Root.app", mode: 0o555, owner: 0,
                expected: .blocked(.ownedByAnotherUser)),
            // Whoever owns it, a bundle the user can change is removable.
            RemovabilityCase(
                name: "another owner, writable", path: "Applications/Shared.app", owner: 0, expected: .removable),
        ])
    func eachAppSaysWhetherItCanBeRemovedAPP005(_ test: RemovabilityCase) async throws {
        let bundle = try root.app(test.path, bundleID: "com.example.App")
        let folder = bundle.deletingLastPathComponent()
        // Restore the modes whatever happens, so the fixture root can be cleaned up.
        defer {
            for url in [bundle, folder] { chmod(url.path, 0o755) }
        }
        try #require(chmod(bundle.path, mode_t(test.mode)) == 0)
        if let folderMode = test.folderMode { try #require(chmod(folder.path, mode_t(folderMode)) == 0) }

        let found = try #require(await apps(owner: test.owner)[test.path])
        #expect(found.removability == test.expected)
    }

    // MARK: - The uninstall plan

    /// The scan's own `InstalledApp` and a leftover as the leftovers scan would report it, for a fixture file or folder.
    private func installedApp(
        _ bundle: URL, removability: AppRemovability = .removable
    ) throws -> InstalledApp {
        let snapshot = try #require(ItemSnapshot.read(bundle))
        return InstalledApp(
            url: bundle, name: "Fixture", bundleID: "com.example.Fixture", snapshot: snapshot,
            modified: try #require(ModificationDate.read(at: bundle)), removability: removability)
    }

    private func leftover(_ url: URL, source: ToolID = .applications, apps: Set<String> = []) throws -> ScanItem {
        ScanItem(
            url: url, snapshot: try #require(ItemSnapshot.read(url)), tier: .yourData, method: .trash,
            reason: "Fixture", source: source, modified: ModificationDate.read(at: url), apps: apps)
    }

    @Test func theUninstallPlanIsAChainWithTheBundleFirstAPP005APP007APP011() throws {
        let bundle = try root.app("Applications/Fixture.app", bundleID: "com.example.Fixture")
        let cache = try root.folder("Library/Caches/com.example.Fixture")
        let agent = try root.file("Library/LaunchAgents/com.example.Fixture.helper.plist", size: 10)
        let pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        let plan = try Applications(appFolders: [try root.url("Applications")]).uninstallPlan(
            for: installedApp(bundle),
            leftovers: [leftover(cache, apps: ["com.example.Other"]), leftover(agent)], pathGuard: pathGuard)

        #expect(plan.tool == .applications)
        #expect(plan.items.map(\.url) == [bundle, cache, agent, agent])
        #expect(plan.items.map(\.method) == [.trash, .trash, .launchctl, .trash])
        #expect(
            plan.items.map(\.dependency) == [
                nil, ItemDependency(plan.items[0]), ItemDependency(plan.items[0]), ItemDependency(plan.items[2]),
            ])
        // The plist's Trash item needs its own bootout, which needs the bundle: so no agent is unloaded for an app
        // that stays.
        #expect(plan.items.allSatisfy { $0.tier == .yourData && $0.apps.contains("com.example.Fixture") })
        #expect(plan.items[1].apps == ["com.example.Fixture", "com.example.Other"])
        #expect(plan.items[0].selection == .selected && plan.items[0].modified == apps(of: bundle))
    }

    private func apps(of url: URL) -> Date? { ModificationDate.read(at: url) }

    @Test func anUninstallPlanIsRefusedAsAWholeAPP005() throws {
        let bundle = try root.app("Applications/Fixture.app", bundleID: "com.example.Fixture")
        let cache = try root.folder("Library/Caches/com.example.Fixture")
        let download = try root.file("Downloads/big.bin", size: 10)
        let pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        let applications = Applications(appFolders: [try root.url("Applications")])
        func plan(_ app: InstalledApp, _ leftovers: [ScanItem]) throws -> UninstallPlanError? {
            do {
                _ = try applications.uninstallPlan(for: app, leftovers: leftovers, pathGuard: pathGuard)
                return nil
            } catch { return error }
        }

        // A blocked app is refused, and its leftovers are never removed on their own.
        #expect(
            try plan(installedApp(bundle, removability: .blocked(.bundleNotWritable)), [leftover(cache)])
                == .appBlocked(.bundleNotWritable))
        // A leftover another tool found mixes tools, and one outside the allowed roots fails the path guard.
        #expect(
            try plan(installedApp(bundle), [leftover(cache, source: .largeFiles)])
                == .plan(.otherSubTool(cache.path, .largeFiles)))
        guard
            case .plan(.rejected(let path, .outsideAllowedRoots)) = try plan(installedApp(bundle), [leftover(download)])
        else {
            Issue.record("Expected the guard to refuse a leftover outside the allowed roots")
            return
        }
        #expect(path == download.path)
    }

    @Test func findsOnlyRealInstalledAppsAPP001() async throws {
        let notes = try root.app("System Apps/Notes.app", bundleID: "com.example.Notes")
        try root.app("Applications/Utilities/Tool.app", bundleID: "com.example.Tool")
        // Only one level of subfolders is searched.
        try root.app("Applications/Utilities/More/Deep.app", bundleID: "com.example.Deep")
        // An app inside another app's bundle is part of that app, not an app of its own.
        try root.app("Applications/Host.app", bundleID: "com.example.Host")
        try root.app("Applications/Host.app/Contents/Helpers/Helper.app", bundleID: "com.example.Helper")
        // Links, files and non-apps are left out, as are apps System Integrity Protection protects.
        try root.symlink("Applications/Notes.app", to: notes)
        try root.file("Applications/Readme.txt", size: 10)
        try root.file("Applications/Fake.app", size: 10)
        try root.folder("Applications/Plugin.bundle")
        try root.app("Applications/Safari.app", bundleID: "com.apple.Safari")
        // The guard protects the running Shuck's bundle; every copy of either build is left out.
        try root.app("Applications/Shuck.app", bundleID: ShuckKit.bundleID)
        try root.app("System Apps/Shuck Old.app", bundleID: "ME.NUTABI.SHUCK")
        try root.app("System Apps/Shuck Debug.app", bundleID: ShuckKit.debugBundleID)

        let found = Set(await apps(protected: ["Safari.app"]).keys)

        #expect(found == ["System Apps/Notes.app", "Applications/Utilities/Tool.app", "Applications/Host.app"])
    }

    @Test func bundleIDsByNameCoverEveryAppThatCanRunCAC003() throws {
        try root.app(
            "Applications/Firefox.app", bundleID: "org.mozilla.firefox", name: "Firefox Browser", displayName: "Fox")
        try root.app("Applications/Utilities/Tool.app", bundleID: "com.example.Tool")
        try root.app("System Apps/Safari.app", bundleID: "com.apple.Safari")
        try root.app("System Apps/Tool.app", bundleID: "com.example.OtherTool")
        try root.app("Applications/Nameless.app", bundleID: nil)
        // An app SIP protects still runs, so the map leaves out none of them; it takes no exclusions either
        // (D-189).
        let applications = Applications(appFolders: appFolders, isSystemProtected: { _ in true })

        let byName = applications.bundleIDsByName(home: root.url)

        for name in ["firefox", "FIREFOX BROWSER", "Fox"] {
            #expect(byName.bundleIDs(named: name) == ["org.mozilla.firefox"], "\(name)")
        }
        #expect(byName.bundleIDs(named: "Tool") == ["com.example.Tool", "com.example.OtherTool"])
        #expect(byName.bundleIDs(named: "Safari") == ["com.apple.Safari"])
        #expect(byName.bundleIDs(named: "Nameless").isEmpty)
    }

    @Test func aMissingAppFolderIsNotAnError() async throws {
        try root.app("System Apps/Notes.app", bundleID: "com.example.Notes")

        let events = await events()
        #expect(events.count == 1)
    }

    @Test func anUnreadableFolderIsReportedSAF012() async throws {
        try root.app("System Apps/Notes.app", bundleID: "com.example.Notes")
        let locked = try root.folder("Applications/Locked", permissions: 0o000)

        let events = await events()
        let notAccessible = events.compactMap { event in
            if case .notAccessible(let url) = event { url.path } else { nil }
        }
        #expect(notAccessible == [locked.path])
        #expect(events.contains { if case .app = $0 { true } else { false } })
    }

    @Test func aFoundAppPassesThePathGuardInAnUninstallPlanSAF007() async throws {
        try root.app("Applications/Notes.app", bundleID: "com.example.Notes", size: 100)
        let app = try #require(await apps()["Applications/Notes.app"])
        let applications = Applications(appFolders: appFolders)
        // Apps and their leftovers are the user's data, moved to the Trash (SAF-004).
        #expect(applications.tiers == [.yourData])

        let plan = try Plan(
            tool: applications.id, allowedRoots: applications.allowedRoots(home: root.url),
            items: [
                PlannedItem(
                    url: app.url, tier: .yourData, method: .trash, snapshot: app.snapshot, modified: app.modified,
                    selection: .selected)
            ],
            pathGuard: PathGuard(configuration: root.pathGuardConfiguration()))
        #expect(plan.items.map(\.url) == [app.url])
    }

    /// The scan stops when its task is cancelled because the walk over the app folders, which every Applications scan
    /// runs, checks before each app. `bundleIDsByName(home:)` runs that walk in the caller's task, so a task cancelled
    /// before it starts reads no app at all. Counting a cancelled scan's events can't show this: a cancelled stream
    /// still hands over what the scan had already buffered, which on a fast Mac is every app (#247).
    @Test func stoppingTheScanEndsItSAF014() async throws {
        for index in 0..<20 { try root.app("Applications/App \(index).app", bundleID: "com.example.\(index)") }
        let applications = Applications(appFolders: appFolders)
        let home = root.url

        let walked = await Task { applications.bundleIDsByName(home: home) }.value
        #expect(walked.allBundleIDs.count == 20)

        let stopped = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return applications.bundleIDsByName(home: home)
        }.value
        #expect(stopped.allBundleIDs.isEmpty)
    }
}
