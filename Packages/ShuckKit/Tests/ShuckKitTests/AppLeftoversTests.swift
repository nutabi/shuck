import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Applications' leftovers by exact bundle ID and app group (APP-002, APP-003, R-05, SAF-007, SAF-012, SET-001).
struct AppLeftoversTests {
    let root: FixtureRoot
    let id = "com.example.Notes"
    let group = "group.com.example.Notes"

    init() throws {
        root = try FixtureRoot()
    }

    private func app(bundleID: String? = "com.example.Notes") throws -> InstalledApp {
        let url = try root.app("Applications/Notes.app", bundleID: bundleID, size: 10)
        return InstalledApp(
            url: url, name: "Notes", bundleID: bundleID,
            snapshot: try #require(ItemSnapshot.read(url, while: { true })),
            modified: try #require(ModificationDate.read(at: url)))
    }

    /// What the scan reports for `app`, whose declared groups are `groups`.
    private func find(_ app: InstalledApp, groups: [String] = []) async -> [ScanEvent] {
        let applications = Applications(
            appFolders: [root.url.appending(path: "Applications")], appGroups: { _ in groups })
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        var events: [ScanEvent] = []
        for await event in applications.leftovers(of: app, context) { events.append(event) }
        return events
    }

    /// The items of `events`, by path relative to the fixture root.
    private func items(_ events: [ScanEvent]) -> [String: ScanItem] {
        var result: [String: ScanItem] = [:]
        for case .item(let item) in events {
            guard let url = item.url else { continue }
            result[String(url.path.dropFirst(root.url.path.count + 1))] = item
        }
        return result
    }

    private func plist(_ path: String, _ values: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try root.file(path, text: String(decoding: data, as: UTF8.self))
    }

    @Test func findsEveryLocationNamedByTheBundleIDAPP002() async throws {
        let host = "2B6CE6C7-8B0E-4B52-A4A2-4B0D3D8E4F11"
        let folders = [
            "Library/Application Support/\(id)", "Library/Caches/\(id)", "Library/Containers/\(id)",
            "Library/Logs/\(id)", "Library/HTTPStorages/\(id)", "Library/WebKit/\(id)",
            "Library/Application Scripts/\(id)", "Library/Saved Application State/\(id).savedState",
        ]
        let files = [
            "Library/Preferences/\(id).plist", "Library/Preferences/ByHost/\(id).\(host).plist",
            "Library/HTTPStorages/\(id).binarycookies", "Library/Cookies/\(id).binarycookies",
        ]
        for path in folders { try root.file("\(path)/data", size: 5) }
        for path in files { try root.file(path, size: 5) }

        let found = items(await find(try app()))

        #expect(Set(found.keys) == Set(folders + files))
        for item in found.values {
            #expect(item.tier == .yourData && item.method == .trash && item.confidence == .high)
            #expect(item.source == .applications && item.appName == "Notes")
            #expect(item.snapshot != nil && item.modified != nil)
        }
    }

    @Test func aSimilarNameIsNotMatchedR05() async throws {
        for path in [
            "Library/Caches/com.example.NotesPro", "Library/Caches/\(id).old",
            "Library/Caches/Notes", "Library/Preferences/\(id).plist.lockfile", "Library/Preferences/\(id)Pro.plist",
            "Library/Preferences/ByHost/\(id).not-a-uuid.plist",
            "Library/Preferences/ByHost/\(id)Pro.\(UUID().uuidString).plist",
            "Library/Saved Application State/com.example.NotesPro.savedState",
            "Library/Group Containers/group.com.example.Other",
        ] {
            try root.file("\(path)/data", size: 5)
        }

        #expect(items(await find(try app(), groups: [group])).isEmpty)
    }

    @Test func anAppWithoutABundleIDOrWithAPathLikeOneHasNoLeftoversAPP002() async throws {
        try root.file("Library/Caches/data", size: 5)
        let url = try root.app("Applications/Notes.app", bundleID: nil)
        let snapshot = try #require(ItemSnapshot.read(url, while: { true }))
        let modified = try #require(ModificationDate.read(at: url))
        for bundleID in [nil, "../Caches"] {
            let app = InstalledApp(url: url, name: "Notes", bundleID: bundleID, snapshot: snapshot, modified: modified)
            #expect(await find(app).isEmpty)
        }
    }

    @Test func aLinkIsNotALeftoverAPP002() async throws {
        let target = try root.file("Documents/real/data", size: 5)
        try root.symlink("Library/Caches/\(id)", to: target.deletingLastPathComponent())
        #expect(items(await find(try app())).isEmpty)
    }

    @Test func aLaunchAgentIsFoundByLabelOrByProgramInsideTheAppAPP002() async throws {
        let app = try app()
        let inside = "\(app.url.path)/Contents/MacOS/Notes"
        try plist("Library/LaunchAgents/a.plist", ["Label": id, "ProgramArguments": ["/usr/bin/true"]])
        try plist("Library/LaunchAgents/b.plist", ["Label": "\(id).helper"])
        try plist("Library/LaunchAgents/c.plist", ["Label": "other", "Program": inside])
        try plist("Library/LaunchAgents/d.plist", ["Label": "x", "ProgramArguments": [inside]])
        try plist("Library/LaunchAgents/e.plist", ["Label": "\(id)Pro", "ProgramArguments": ["\(app.url.path)Pro/x"]])
        try plist("Library/LaunchAgents/f.plist", ["Label": "com.example.Other"])
        // A bare prefix is not a match: com.example.Notes must not claim com.example.NotesHelper (R-05).
        try plist("Library/LaunchAgents/g.plist", ["Label": "\(id)Helper"])
        try root.file("Library/LaunchAgents/broken.plist", text: "not a plist")

        let found = items(await find(app))

        #expect(Set(found.keys) == Set(["a", "b", "c", "d"].map { "Library/LaunchAgents/\($0).plist" }))
    }

    @Test func anAppGroupIsFoundThroughTheDeclaredGroupsAPP002() async throws {
        try root.file("Library/Group Containers/\(group)/data", size: 5)
        try root.file("Library/Group Containers/group.com.example.Other/data", size: 5)

        let found = items(await find(try app(), groups: [group, "group.com.example.Missing", "../x"]))

        let item = try #require(found["Library/Group Containers/\(group)"])
        #expect(found.count == 1 && item.confidence == .high)
        #expect(String(localized: item.reason) == "In an app group the app declares: \(group)")
    }

    @Test func aFixtureAppDeclaresNoGroupsAPP002() throws {
        #expect(Applications.declaredAppGroups(of: try app().url).isEmpty)
    }

    /// APP-003, OQ-07 (D-NEXT-oq07): an exact bundle-ID match is preselected unless it is in Application Support,
    /// Containers or Group Containers, which can hold the only copy of the user's data. Those are still High and
    /// selectable.
    @Test func preselectionPerFolderAPP003OQ07() async throws {
        let app = try app()
        let selected = [
            "Library/Caches/\(id)", "Library/Logs/\(id)", "Library/WebKit/\(id)", "Library/HTTPStorages/\(id)",
            "Library/Application Scripts/\(id)", "Library/Saved Application State/\(id).savedState",
        ]
        let unselected = [
            "Library/Application Support/\(id)", "Library/Containers/\(id)", "Library/Group Containers/\(group)",
        ]
        for path in selected + unselected { try root.file("\(path)/data", size: 5) }
        try root.file("Library/Preferences/\(id).plist", size: 5)
        try root.file("Library/Cookies/\(id).binarycookies", size: 5)
        try plist("Library/LaunchAgents/a.plist", ["Label": id])
        try plist("Library/LaunchAgents/b.plist", ["Label": "\(id).helper"])
        try plist("Library/LaunchAgents/c.plist", ["Label": "x", "Program": "\(app.url.path)/Contents/MacOS/Notes"])

        let found = items(await find(app, groups: [group]))

        let chosen = Set(found.filter { $0.value.selection == .selected }.keys)
        let expected = selected + ["Library/Preferences/\(id).plist", "Library/Cookies/\(id).binarycookies"]
        #expect(chosen == Set(expected + ["Library/LaunchAgents/a.plist"]))
        for path in unselected + ["Library/LaunchAgents/b.plist", "Library/LaunchAgents/c.plist"] {
            #expect(found[path]?.selection == .unselected, "\(path)")
        }
        #expect(found.values.allSatisfy { $0.confidence == .high && $0.selection.isSelectable })
    }

    @Test func anUnreadableFolderIsReportedOnceSAF012() async throws {
        try root.file("Library/Caches/\(id)/data", size: 5)
        let locked = try root.folder("Library/Application Support", permissions: 0o000)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let events = await find(try app())

        let denied = events.compactMap { event in
            if case .notAccessible(let url) = event { url.path } else { nil }
        }
        #expect(denied == [locked.path])
        #expect(Set(items(events).keys) == ["Library/Caches/\(id)"])
    }

    @Test func anUnreadableLeftoverIsReportedAndSkippedSAF012() async throws {
        let locked = try root.folder("Library/Containers/\(id)", permissions: 0o000)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let events = await find(try app())

        #expect(events == [.notAccessible(locked)])
    }

    @Test func everyLeftoverPassesThePathGuardInAnUninstallPlanSAF007() async throws {
        let app = try app()
        try root.file("Library/Caches/\(id)/data", size: 5)
        try root.file("Library/Preferences/\(id).plist", size: 5)
        try root.file("Library/Group Containers/\(group)/data", size: 5)
        let found = items(await find(app, groups: [group])).values
        let applications = Applications(appFolders: [root.url.appending(path: "Applications")])

        let planned = found.compactMap { item in
            item.url.flatMap { url in
                item.snapshot.map {
                    PlannedItem(
                        url: url, tier: .yourData, method: .trash, snapshot: $0, modified: item.modified,
                        selection: item.selection)
                }
            }
        }
        let plan = try Plan(
            tool: applications.id, allowedRoots: applications.allowedRoots(home: root.url), items: planned,
            pathGuard: PathGuard(configuration: root.pathGuardConfiguration()))

        #expect(planned.count == 3 && plan.items.count == 3)
    }
}
