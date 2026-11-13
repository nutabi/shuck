import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Caches & Logs' scan: its scope, grouping, selection and running-app check (CAC-001 to CAC-005, CAC-008, FCL-005).
struct CachesAndLogsTests {
    let root: FixtureRoot
    let longAgo = Date.now.addingTimeInterval(-40 * 86_400)
    let lastMonth = Date.now.addingTimeInterval(-10 * 86_400)
    let names = StubAppNames(
        [
            "com.example.Notes": "Notes", "com.example.Mail": "Mail Pro", "com.example.Stale": "Stale",
            "com.example.Recent": "Recent", "com.example.Busy": "Busy",
        ],
        byName: ["Firefox": ["org.mozilla.firefox"], "Twin": ["com.example.twin-a", "com.example.twin-b"]])

    init() throws {
        root = try FixtureRoot()
    }

    private func events(running: Set<String> = [], ownership: OwnershipMap? = nil) async -> [ScanEvent] {
        let context = ScanContext(
            home: root.url, ownership: ownership ?? OwnershipMap(home: root.url),
            protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running))
        var result: [ScanEvent] = []
        for await event in CachesAndLogs(appNames: names).scan(context) { result.append(event) }
        return result
    }

    /// The items by path relative to the home folder.
    private func items(running: Set<String> = [], ownership: OwnershipMap? = nil) async -> [String: ScanItem] {
        var result: [String: ScanItem] = [:]
        let home = root.url.path + "/"
        for case .item(let item) in await events(running: running, ownership: ownership) {
            result[String((item.url?.path ?? "").dropFirst(home.count))] = item
        }
        return result
    }

    /// An app cache that nothing has touched for a while, which the scan selects.
    private func cache(_ name: String, modified: Date? = nil) throws {
        try root.file("Library/Caches/\(name)/data.db", size: 4096, modified: modified ?? longAgo)
        try FileManager.default.setAttributes(
            [.modificationDate: modified ?? longAgo], ofItemAtPath: root.url("Library/Caches/\(name)").path)
    }

    @Test func theSubToolIsAvailableAndRebuildableCAC006() {
        let info = CachesAndLogs().info
        #expect(info.id == .cachesAndLogs && info.availability == .available)
        #expect(CachesAndLogs().tiers == [.rebuildable])
    }

    @Test func everyEntryOfCachesAndLogsIsOneItemCAC001() async throws {
        try cache("com.example.Notes")
        try root.file("Library/Caches/loose.dat", size: 100)
        try root.file("Library/Logs/Notes/notes.log", size: 100)
        try root.file("Library/Logs/old.log", size: 100)
        try root.file("Library/Containers/com.example.Mail/Data/Library/Caches/m.db", size: 100)

        let items = await items()

        #expect(
            Set(items.keys) == [
                "Library/Caches/com.example.Notes", "Library/Caches/loose.dat", "Library/Logs/Notes",
                "Library/Logs/old.log", "Library/Containers/com.example.Mail/Data/Library/Caches",
            ])
        #expect(
            items.values.allSatisfy { $0.tier == .rebuildable && $0.method == .delete && $0.source == .cachesAndLogs })
        #expect(items["Library/Caches/com.example.Notes"]?.scope == .contents)
        #expect(items["Library/Logs/Notes"]?.scope == .contents)
        #expect(items["Library/Containers/com.example.Mail/Data/Library/Caches"]?.scope == .contents)
        #expect(items["Library/Caches/loose.dat"]?.scope == .item)
        #expect(items["Library/Logs/old.log"]?.scope == .item)
    }

    @Test func itemsNameTheirAppCAC002() async throws {
        try cache("com.example.Notes")
        try cache("Firefox")
        try root.file("Library/Caches/loose.dat", size: 10)
        try root.file("Library/Logs/com.example.Mail/mail.log", size: 10)
        try root.file("Library/Containers/com.example.Notes/Data/Library/Caches/n.db", size: 10)
        try root.file("Library/Containers/com.unknown.Thing/Data/Library/Caches/n.db", size: 10)

        let items = await items()

        // A bundle ID the Mac knows becomes the app's name, in the caches and in the container; others keep their name.
        #expect(items["Library/Caches/com.example.Notes"]?.appName == "Notes")
        #expect(items["Library/Containers/com.example.Notes/Data/Library/Caches"]?.appName == "Notes")
        #expect(items["Library/Logs/com.example.Mail"]?.appName == "Mail Pro")
        #expect(items["Library/Caches/Firefox"]?.appName == "Firefox")
        #expect(items["Library/Caches/loose.dat"]?.appName == "loose")
        #expect(items["Library/Containers/com.unknown.Thing/Data/Library/Caches"]?.appName == "com.unknown.Thing")
        #expect(items["Library/Caches/com.example.Notes"]?.category.id == "caches")
        #expect(items["Library/Containers/com.example.Notes/Data/Library/Caches"]?.category.id == "container-caches")
        #expect(items["Library/Logs/com.example.Mail"]?.category.id == "logs")
    }

    @Test func bundleIDShapedNamesAreRecognised() {
        #expect(CachesAndLogs.bundleID(ofFolder: "com.example.Notes") == "com.example.Notes")
        #expect(CachesAndLogs.bundleID(ofFolder: "org.mozilla.firefox-nightly") == "org.mozilla.firefox-nightly")
        #expect(CachesAndLogs.bundleID(ofFolder: "Firefox") == nil)
        #expect(CachesAndLogs.bundleID(ofFolder: "foo.log") == nil)
        #expect(CachesAndLogs.bundleID(ofFolder: "Google Chrome Helper.x.y") == nil)
        #expect(CachesAndLogs.bundleID(ofFolder: "a..b") == nil)
    }

    @Test func cachesOfARunningAppAreDisabledCAC003() async throws {
        try cache("com.example.Notes")
        try cache("com.example.Mail")
        try root.file("Library/Containers/com.example.Notes/Data/Library/Caches/n.db", size: 10)
        try root.file("Library/Logs/com.example.Notes/notes.log", size: 10, modified: longAgo)

        let items = await items(running: ["COM.example.notes"])

        #expect(items["Library/Caches/com.example.Notes"]?.selection == .appIsRunning(nil))
        #expect(items["Library/Containers/com.example.Notes/Data/Library/Caches"]?.selection == .appIsRunning(nil))
        #expect(items["Library/Logs/com.example.Notes"]?.selection == .appIsRunning(nil))
        #expect(items["Library/Caches/com.example.Notes"]?.apps == ["com.example.Notes"])
        #expect(items["Library/Caches/com.example.Mail"]?.selection == .selected)
    }

    @Test func aFolderNamedAfterARunningAppIsDisabledCAC003SAF009() async throws {
        try cache("Firefox")
        try cache("FIREFOX-not")
        try root.file("Library/Logs/firefox/f.log", size: 10, modified: longAgo)
        try root.file("Library/Caches/Firefox.log", size: 10, modified: longAgo)

        let items = await items(running: ["org.mozilla.firefox"])

        // The name compares without case; a loose file and another name stay untied (D-189).
        #expect(items["Library/Caches/Firefox"]?.selection == .appIsRunning(nil))
        #expect(items["Library/Caches/Firefox"]?.apps == ["org.mozilla.firefox"])
        #expect(items["Library/Logs/firefox"]?.selection == .appIsRunning(nil))
        #expect(items["Library/Caches/FIREFOX-not"]?.selection == .unselected)
        #expect(items["Library/Caches/Firefox.log"]?.apps == [])
    }

    @Test func aFolderNamedAfterAnAppThatIsNotRunningStaysUnselectedCAC009() async throws {
        try cache("Firefox")

        let item = try #require(await items()["Library/Caches/Firefox"])

        // A name alone never makes the owner known, so the tie only ever disables (CAC-009).
        #expect(item.selection == .unselected)
        #expect(
            String(localized: item.reason) == "Shuck can't tell which app this belongs to, so it starts unselected.")
        #expect(item.appName == "Firefox")
    }

    @Test func aNameTwoAppsShareIsTiedToBothCAC003() async throws {
        try cache("Twin")

        let items = await items(running: ["com.example.twin-b"])

        #expect(items["Library/Caches/Twin"]?.apps == ["com.example.twin-a", "com.example.twin-b"])
        #expect(items["Library/Caches/Twin"]?.selection == .appIsRunning(nil))
    }

    @Test func aCacheIsSelectedOnlyWhenNothingInItChangedForThirtyDaysCAC005() async throws {
        try cache("com.example.Stale")
        try cache("com.example.Recent", modified: .now)
        // The folder's own date is old, but a file inside it was just written: the app is using it.
        try root.file("Library/Caches/com.example.Busy/data.db", size: 100, modified: .now)
        try FileManager.default.setAttributes(
            [.modificationDate: longAgo], ofItemAtPath: root.url("Library/Caches/com.example.Busy").path)
        try root.file("Library/Caches/old.dat", size: 100, modified: longAgo)
        try root.file("Library/Caches/new.dat", size: 100, modified: .now)

        let items = await items()

        #expect(items["Library/Caches/com.example.Stale"]?.selection == .selected)
        #expect(items["Library/Caches/com.example.Recent"]?.selection == .unselected)
        #expect(items["Library/Caches/com.example.Busy"]?.selection == .unselected)
        // A loose file names no app, so its age never selects it (CAC-009).
        #expect(items["Library/Caches/old.dat"]?.selection == .unselected)
        #expect(items["Library/Caches/new.dat"]?.selection == .unselected)
    }

    @Test func aCacheWhoseAppIsUnknownIsListedButNeverSelectedCAC009() async throws {
        // Not named like a bundle ID, named like one no installed app has, and a sandboxed app that is gone.
        try cache("Firefox")
        try cache("claude-cli-nodejs")
        try cache("com.example.Gone")
        try root.file("Library/Containers/com.example.Gone/Data/Library/Caches/g.db", size: 10, modified: longAgo)
        try FileManager.default.setAttributes(
            [.modificationDate: longAgo],
            ofItemAtPath: root.url("Library/Containers/com.example.Gone/Data/Library/Caches").path)
        try cache("com.example.Notes")
        // A folder named `cache` outside Caches is no sub-tool's to list, whatever its name.
        try root.file("Library/Application Support/Notes/cache/state.db", size: 100, modified: longAgo)

        let items = await items()

        for path in [
            "Library/Caches/Firefox", "Library/Caches/claude-cli-nodejs", "Library/Caches/com.example.Gone",
            "Library/Containers/com.example.Gone/Data/Library/Caches",
        ] {
            let item = try #require(items[path], "\(path) is not listed")
            #expect(item.selection == .unselected, "\(path) is selected")
            #expect(
                String(localized: item.reason) == "Shuck can't tell which app this belongs to, so it starts unselected."
            )
        }
        #expect(items["Library/Caches/com.example.Notes"]?.selection == .selected)
        #expect(!items.keys.contains { $0.hasPrefix("Library/Application Support") })
    }

    @Test func aLogIsSelectedByItsAgeWhoeverWroteItCAC005CAC009() async throws {
        try root.file("Library/Logs/Unknown Tool/old.log", size: 100, modified: lastMonth)
        try FileManager.default.setAttributes(
            [.modificationDate: lastMonth], ofItemAtPath: root.url("Library/Logs/Unknown Tool").path)

        #expect(await items()["Library/Logs/Unknown Tool"]?.selection == .selected)
    }

    @Test func logsNotChangedForSevenDaysAreSelectedAndNewerOnesAreListedCAC005() async throws {
        try root.file("Library/Logs/old.log", size: 100, modified: lastMonth)
        try root.file("Library/Logs/new.log", size: 100, modified: .now)
        try root.file("Library/Logs/Tool/old.log", size: 100, modified: lastMonth)
        try FileManager.default.setAttributes(
            [.modificationDate: lastMonth], ofItemAtPath: root.url("Library/Logs/Tool").path)
        try root.file("Library/Logs/Active/today.log", size: 100, modified: .now)
        try FileManager.default.setAttributes(
            [.modificationDate: lastMonth], ofItemAtPath: root.url("Library/Logs/Active").path)

        let items = await items()

        #expect(items["Library/Logs/old.log"]?.selection == .selected)
        #expect(items["Library/Logs/new.log"]?.selection == .unselected)
        #expect(items["Library/Logs/Tool"]?.selection == .selected)
        #expect(items["Library/Logs/Active"]?.selection == .unselected)
        #expect(CachesAndLogs.staleLogDays == 7 && CachesAndLogs.staleCacheDays == 30)
    }

    @Test func appleCachesAreListedButNeverSelectedByDefaultD120() async throws {
        try cache("com.apple.Safari")
        try root.file("Library/Containers/com.apple.Notes/Data/Library/Caches/n.db", size: 10, modified: longAgo)
        try FileManager.default.setAttributes(
            [.modificationDate: longAgo],
            ofItemAtPath: root.url("Library/Containers/com.apple.Notes/Data/Library/Caches").path)

        let items = await items()

        #expect(items["Library/Caches/com.apple.Safari"]?.selection == .unselected)
        #expect(items["Library/Containers/com.apple.Notes/Data/Library/Caches"]?.selection == .unselected)
    }

    @Test func aStaleItemSaysWhyItIsSelected() async throws {
        try cache("com.example.Notes")
        let item = try #require(await items()["Library/Caches/com.example.Notes"])
        #expect(String(localized: item.reason) == "Not changed for 30 days or more.")
    }

    @Test func foldersWithNothingInsideAreNotListedAndLinksAreNotEntries() async throws {
        try root.folder("Library/Caches/Empty")
        try root.folder("Library/Logs/Empty")
        try root.symlink("Library/Caches/link", to: root.folder("Elsewhere"))
        try root.file("Elsewhere/file", size: 10)
        try root.symlink("Library/Logs/link.log", to: root.url("Elsewhere/file"))
        try root.folder("Library/Containers/com.example.Notes/Data/Library/Caches")

        #expect(await items().isEmpty)
    }

    @Test func cachesADeveloperToolOwnsAreLeftToDeveloperJunkFCL005() async throws {
        for name in [
            "Homebrew", "pip", "org.swift.swiftpm", "CocoaPods", "Yarn", "pnpm", "go-build", "com.apple.dt.Xcode",
        ] {
            try cache(name)
        }
        try root.file("Library/Logs/Homebrew/brew.log", size: 10)
        try root.file("Library/Logs/CoreSimulator/sim.log", size: 10)
        try cache("com.example.Notes")

        #expect(Set(await items().keys) == ["Library/Caches/com.example.Notes"])
    }

    @Test func shucksOwnCachesAndDockersAreLeftOutCAC001DEV007() async throws {
        try cache(ShuckKit.bundleID)
        try cache(ShuckKit.debugBundleID)
        try root.file("Library/Logs/\(ShuckKit.bundleID)/shuck.log", size: 10)
        try root.file("Library/Containers/com.docker.docker/Data/Library/Caches/d.db", size: 10)
        try cache("com.example.Notes")

        #expect(Set(await items().keys) == ["Library/Caches/com.example.Notes"])
    }

    @Test func aScanLeavesOutWhatTheMapGivesAnotherSubToolFCL005() async throws {
        try cache("com.example.Notes")
        #expect(await items(ownership: OwnershipMap(home: root.url, entries: [])).isEmpty)
    }

    @Test func theScanNeverListsAnythingOutsideTheLibraryFoldersCAC008() async throws {
        try root.file("Library/Preferences/com.example.plist", size: 10)
        try root.file("Library/Application Support/Notes/data", size: 10)
        try root.file("Library/Containers/com.example.Notes/Data/Documents/essay.txt", size: 10)
        try root.file("Library/Containers/com.example.Notes/Data/Library/Application Support/x", size: 10)
        try root.file("Downloads/big.bin", size: 10)

        #expect(await items().isEmpty)
    }

    @Test func aFolderMacOSHidesIsReportedNotAccessibleOnceSAF012() async throws {
        try root.file("Library/Containers/com.example.A/Data/Library/Caches/a.db", size: 10)
        try root.folder("Library/Containers/com.example.B", permissions: 0o000)
        try root.folder("Library/Containers/com.example.C", permissions: 0o000)

        let events = await events()

        let denied = events.compactMap { event -> String? in
            if case .notAccessible(let url) = event { url.lastPathComponent } else { nil }
        }
        #expect(denied.count == 1 && ["com.example.B", "com.example.C"].contains(denied[0]))
        #expect(events.contains { if case .item = $0 { true } else { false } })
    }

    @Test func aCacheShuckMayNotReadIsReportedNotListedSAF011SAF012() async throws {
        try root.file("Library/Caches/com.example.Open/a.db", size: 10)
        try root.folder("Library/Caches/com.example.Locked", permissions: 0o000)

        let events = await events()

        let denied = events.compactMap { event -> String? in
            if case .notAccessible(let url) = event { url.lastPathComponent } else { nil }
        }
        let listed = events.compactMap { event -> String? in
            if case .item(let item) = event { item.url?.lastPathComponent } else { nil }
        }
        #expect(denied == ["com.example.Locked"])
        #expect(listed == ["com.example.Open"])
    }

    @Test func aCacheAnExclusionHidesIsNotReportedSAF011SAF012() async throws {
        let locked = try root.folder("Library/Caches/com.example.Locked", permissions: 0o000)
        let context = ScanContext(
            home: root.url, ownership: OwnershipMap(home: root.url),
            protection: root.pathGuardConfiguration(userExclusions: [locked]), runningApps: StubRunningApps([]))

        var events: [ScanEvent] = []
        for await event in CachesAndLogs(appNames: names).scan(context) { events.append(event) }

        #expect(events.isEmpty)
    }

    @Test func eachRuleValidatesAndDeletesOnlyWithinItsAreaCAC001CAC004() throws {
        for kind in CachesAndLogs.Kind.allCases {
            let rule = try CachesAndLogs.rule(kind, home: root.url)
            #expect(rule.tier == .rebuildable && rule.action.method == .delete)
        }
        let cacheRule = try CachesAndLogs.rule(.cacheFolders, home: root.url)
        func accepts(_ rule: CleanupRule, _ path: String, scope: ItemScope) throws -> Bool {
            rule.accepts(.path(try root.url(path)), tier: .rebuildable, method: .delete, scope: scope)
        }
        #expect(try accepts(cacheRule, "Library/Caches/com.example.Notes", scope: .contents))
        #expect(try !accepts(cacheRule, "Library/Caches/com.example.Notes", scope: .item))
        #expect(try !accepts(cacheRule, "Library/Caches/com.example.Notes/data.db", scope: .contents))
        #expect(try !accepts(cacheRule, "Library/Caches", scope: .contents))
        #expect(try !accepts(cacheRule, "Library/Logs/Notes", scope: .contents))
        let containerRule = try CachesAndLogs.rule(.containerCaches, home: root.url)
        let caches = "Library/Containers/com.example.Notes/Data/Library/Caches"
        #expect(try accepts(containerRule, caches, scope: .contents))
        #expect(try !accepts(containerRule, "Library/Containers/com.example.Notes/Data/Documents", scope: .contents))
    }

    @Test func adminFoldersAreNeverAllowedCAC008() throws {
        let someone = URL(filePath: "/Users/someone")
        let roots = CachesAndLogs().allowedRoots(home: someone)
        #expect(
            roots.map(\.path) == [
                "/Users/someone/Library/Caches", "/Users/someone/Library/Logs", "/Users/someone/Library/Containers",
            ])
        let guardConfiguration = PathGuard(
            configuration: .production(
                home: someone, appBundle: URL(filePath: "/Applications/Shuck.app"), userExclusions: []))
        for path in ["/Library/Caches/com.example", "/Library/Logs/DiagnosticReports", "/private/var/folders/x/C/y"] {
            #expect(throws: PathGuardError.self, "\(path)") {
                try guardConfiguration.validate(path: path, allowedRoots: roots)
            }
        }
    }

    @Test func appNamesComeFromTheInstalledAppsAndStubsCompareWithoutCase() {
        #expect(SystemAppNames().name(ofBundleID: "com.apple.finder") == "Finder")
        #expect(SystemAppNames().name(ofBundleID: "com.example.not-installed.app") == nil)
        #expect(StubAppNames(["COM.A.B": "AB"]).name(ofBundleID: "com.a.b") == "AB")
        let byName = StubAppNames(byName: ["Fire Fox": ["a.b.c"], "fire fox": ["d.e.f"]])
            .bundleIDsByName(home: root.url)
        #expect(byName.bundleIDs(named: "FIRE FOX") == ["a.b.c", "d.e.f"])
        #expect(byName.bundleIDs(named: "Other").isEmpty)
    }
}
