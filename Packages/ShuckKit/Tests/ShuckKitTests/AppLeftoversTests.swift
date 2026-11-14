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
    private func find(
        _ app: InstalledApp, groups: [String] = [], installed: AppsByName = AppsByName()
    ) async -> [ScanEvent] {
        let applications = Applications(
            appFolders: [root.url.appending(path: "Applications")], appGroups: { _ in groups },
            systemLibrary: root.url.appending(path: "SystemLibrary"))
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
        var events: [ScanEvent] = []
        for await event in applications.leftovers(of: app, among: installed, context) { events.append(event) }
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

    /// APP-003, OQ-07 (D-192): an exact bundle-ID match is preselected unless it is in Application Support,
    /// Containers or Group Containers, which can hold the only copy of the user's data. Those are still High and
    /// selectable.
    @Test func findsEveryLocationNamedByTheBundleIDAndPreselectsThemPerFolderAPP002APP003OQ07() async throws {
        let app = try app()
        let host = "2B6CE6C7-8B0E-4B52-A4A2-4B0D3D8E4F11"
        let selected = [
            "Library/Caches/\(id)", "Library/Logs/\(id)", "Library/WebKit/\(id)", "Library/HTTPStorages/\(id)",
            "Library/Application Scripts/\(id)", "Library/Saved Application State/\(id).savedState",
        ]
        let unselected = [
            "Library/Application Support/\(id)", "Library/Containers/\(id)", "Library/Group Containers/\(group)",
        ]
        let files = [
            "Library/Preferences/\(id).plist", "Library/Preferences/ByHost/\(id).\(host).plist",
            "Library/HTTPStorages/\(id).binarycookies", "Library/Cookies/\(id).binarycookies",
        ]
        for path in selected + unselected { try root.file("\(path)/data", size: 5) }
        for path in files { try root.file(path, size: 5) }
        try plist("Library/LaunchAgents/a.plist", ["Label": id])
        try plist("Library/LaunchAgents/b.plist", ["Label": "\(id).helper"])
        try plist("Library/LaunchAgents/c.plist", ["Label": "x", "Program": "\(app.url.path)/Contents/MacOS/Notes"])

        let found = items(await find(app, groups: [group]))

        let agents = ["a", "b", "c"].map { "Library/LaunchAgents/\($0).plist" }
        #expect(Set(found.keys) == Set(selected + unselected + files + agents))
        for item in found.values {
            #expect(item.tier == .yourData && item.method == .trash && item.confidence == .high)
            #expect(item.source == .applications && item.appName == "Notes")
            #expect(item.snapshot != nil && item.modified != nil && item.selection.isSelectable)
        }
        for path in unselected + [agents[1], agents[2]] {
            #expect(found[path]?.selection == .unselected, "\(path)")
        }
        let preselected =
            selected + ["Library/Preferences/\(id).plist", "Library/Cookies/\(id).binarycookies", agents[0]]
        for path in preselected { #expect(found[path]?.selection == .selected, "\(path)") }
    }

    @Test func aSimilarNameIsNotMatchedR05() async throws {
        for path in [
            "Library/Caches/com.example.NotesPro", "Library/Caches/\(id)old",
            "Library/Preferences/\(id).plist.lockfile", "Library/Preferences/\(id)Pro.plist",
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

    @Test func aLinkIsNotALeftoverByIDOrByNameAPP002APP003() async throws {
        let target = try root.file("Documents/real/data", size: 5)
        try root.symlink("Library/Caches/\(id)", to: target.deletingLastPathComponent())
        try root.symlink("Library/Caches/Notes", to: target.deletingLastPathComponent())
        #expect(items(await find(try app(), installed: AppsByName(["Notes": [id]]))).isEmpty)
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

        let app = try app()
        #expect(Applications.declaredAppGroups(of: app.url).isEmpty)
        let found = items(await find(app, groups: [group, "group.com.example.Missing", "../x"]))

        let item = try #require(found["Library/Group Containers/\(group)"])
        #expect(found.count == 1 && item.confidence == .high)
        #expect(String(localized: item.reason) == "In an app group the app declares: \(group)")
    }

    /// A folder macOS refuses, in the user's Library, in a leftover's own folder or in the system-wide Library, is
    /// reported once, and the scan goes on (SAF-012).
    @Test func eachFolderMacOSRefusesIsReportedOnceAndTheScanGoesOnSAF012() async throws {
        try root.file("Library/Caches/\(id)/data", size: 5)
        try root.file("SystemLibrary/Application Support/\(id)/data", size: 5)
        let locked = try [
            root.folder("Library/Application Support", permissions: 0o000),
            root.folder("Library/Containers/\(id)", permissions: 0o000),
            root.folder("SystemLibrary/LaunchDaemons", permissions: 0o000),
        ]
        defer {
            for url in locked {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }

        let events = await find(try app())

        let denied = events.compactMap { event in
            if case .notAccessible(let url) = event { url.path } else { nil }
        }
        #expect(denied.sorted() == locked.map(\.path).sorted())
        #expect(Set(items(events).keys) == ["Library/Caches/\(id)", "SystemLibrary/Application Support/\(id)"])
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

    // MARK: Medium and Low (APP-003)

    @Test func anEntryNamedLikeTheAppOrItsMakerIsMediumAndUnselectedAPP003() async throws {
        for path in [
            "Library/Application Support/notes", "Library/Caches/Notes", "Library/Logs/EXAMPLE",
            "Library/Caches/Other", "Library/Preferences/Notes", "Library/Containers/Notes",
        ] {
            try root.file("\(path)/data", size: 5)
        }
        let installed = AppsByName(["Notes": [id]])

        let found = items(await find(try app(), installed: installed))

        #expect(
            Set(found.keys) == ["Library/Application Support/notes", "Library/Caches/Notes", "Library/Logs/EXAMPLE"])
        for item in found.values {
            #expect(item.confidence == .medium && item.selection == .unselected)
            #expect(item.tier == .yourData && item.method == .trash)
        }
        let reasons = found.mapValues { String(localized: $0.reason) }
        #expect(reasons["Library/Caches/Notes"] == "Named like the app: Notes")
        #expect(reasons["Library/Logs/EXAMPLE"] == "Named like the app's maker: EXAMPLE")
    }

    @Test func aFolderAnotherInstalledAppGoesByIsNotOfferedR05() async throws {
        // Two apps from one vendor: the vendor's folder belongs to neither.
        let other = "com.example.Mail"
        try root.file("Library/Application Support/example/data", size: 5)
        try root.file("Library/Caches/Mail/data", size: 5)
        try root.file("Library/Caches/Notes/data", size: 5)
        let installed = AppsByName(["Notes": [id], "Mail": [other]])

        let notesApp = try app()
        let notes = items(await find(notesApp, installed: installed))

        #expect(Set(notes.keys) == ["Library/Caches/Notes"])
        let mailURL = try root.app("Applications/Mail.app", bundleID: other, size: 10)
        let mail = InstalledApp(
            url: mailURL, name: "Mail", bundleID: other,
            snapshot: try #require(ItemSnapshot.read(mailURL, while: { true })),
            modified: try #require(ModificationDate.read(at: mailURL)))
        #expect(Set(items(await find(mail, installed: installed)).keys) == ["Library/Caches/Mail"])
        // The vendor folder is offered once only one app of the vendor is installed.
        let alone = items(await find(notesApp, installed: AppsByName(["Notes": [id]])))
        #expect(alone["Library/Application Support/example"]?.confidence == .medium)
        // Two apps called alike: the name is shared, so it is offered for neither.
        let twins = AppsByName(["Notes": [id, "org.other.Notes"]])
        #expect(items(await find(notesApp, installed: twins)).keys.contains("Library/Caches/Notes") == false)
    }

    @Test func aVendorNeverMatchesAppleOrAShortOrMissingOneAPP003() {
        #expect(Applications.vendor(of: "com.Example.Notes") == "example")
        #expect(Applications.vendor(of: "com.apple.dt.Xcode") == nil)
        #expect(Applications.vendor(of: "io.ab.App") == nil)
        #expect(Applications.vendor(of: "Notes.app") == nil)
        #expect(Applications.vendor(of: "com.example") == nil)
    }

    @Test func anEntryStartingWithTheBundleIDAndADotIsLowAndUnselectedAPP003() async throws {
        try root.file("Library/Caches/\(id).ShipIt/data", size: 5)
        try root.file("Library/Logs/\(id).helper.log", size: 5)
        try root.file("Library/Caches/\(id).Pro.Updater/data", size: 5)
        try root.file("Library/Caches/\(id)x/data", size: 5)
        let installed = AppsByName(["Notes": [id], "Notes Pro": ["\(id).Pro"]])

        let found = items(await find(try app(), installed: installed))

        // The one that starts with another installed app's bundle ID is that app's (R-05).
        #expect(Set(found.keys) == ["Library/Caches/\(id).ShipIt", "Library/Logs/\(id).helper.log"])
        for item in found.values {
            #expect(item.confidence == .low && item.selection == .unselected)
            #expect(String(localized: item.reason).hasPrefix("Starts with the app's bundle ID: "))
        }
    }

    // MARK: Needs admin (APP-004)

    @Test func systemWideItemsAreListedAsNeedingAdminAndNeverPlannedAPP004SAF007() async throws {
        let app = try app()
        let inside = "\(app.url.path)/Contents/MacOS/helper"
        try root.file("SystemLibrary/Application Support/\(id)/data", size: 5)
        try root.file("SystemLibrary/Preferences/\(id).plist", size: 5)
        try root.file("SystemLibrary/PrivilegedHelperTools/\(id).helper", size: 5)
        try root.file("SystemLibrary/PrivilegedHelperTools/com.example.NotesPro.helper", size: 5)
        try plist("SystemLibrary/LaunchAgents/a.plist", ["Label": "\(id).agent"])
        try plist("SystemLibrary/LaunchDaemons/b.plist", ["Label": "other", "Program": inside])
        try plist("SystemLibrary/LaunchDaemons/c.plist", ["Label": "com.example.NotesPro"])

        let found = items(await find(app))

        let expected: Set = [
            "SystemLibrary/Application Support/\(id)", "SystemLibrary/Preferences/\(id).plist",
            "SystemLibrary/PrivilegedHelperTools/\(id).helper", "SystemLibrary/LaunchAgents/a.plist",
            "SystemLibrary/LaunchDaemons/b.plist",
        ]
        #expect(Set(found.keys) == expected)
        for item in found.values {
            let reason = item.selection.disabledReason.map { String(localized: $0) }
            #expect(reason == "Needs admin — not removable in this version")
            #expect(item.snapshot != nil && item.modified != nil && item.confidence == .high)
        }

        let item = try #require(found["SystemLibrary/Preferences/\(id).plist"])
        let applications = Applications(appFolders: [root.url.appending(path: "Applications")])
        let pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        func plan(_ selection: ItemSelection) throws -> Plan {
            let planned = PlannedItem(
                url: try #require(item.url), tier: .yourData, method: .trash, snapshot: try #require(item.snapshot),
                modified: item.modified, selection: selection)
            return try Plan(
                tool: applications.id, allowedRoots: applications.allowedRoots(home: root.url), items: [planned],
                pathGuard: pathGuard)
        }
        // Disabled, and even if a caller selects it, outside the allowed roots.
        #expect(throws: PlanError.self) { try plan(item.selection) }
        #expect(throws: PlanError.self) { try plan(.selected) }
    }

    // MARK: Launch agent plists

    @Test func aPlistThatIsNotARegularFileIsSkippedWithoutBeingReadAPP002() async throws {
        try root.fifo("Library/LaunchAgents/pipe.plist")
        try plist("Library/LaunchAgents/real.plist", ["Label": id])

        let found = items(await find(try app()))

        #expect(Set(found.keys) == ["Library/LaunchAgents/real.plist"])
    }
}
