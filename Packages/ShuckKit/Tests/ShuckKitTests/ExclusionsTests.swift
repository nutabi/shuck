import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The user's exclusions hide what they cover from every sub-tool's scan (SET-001, SAF-007, D-149).
struct ExclusionsTests {
    let root: FixtureRoot
    let longAgo = Date.now.addingTimeInterval(-3 * 365 * 86_400)
    let hash = "abcdefghijklmnopqrstuvwxyzab"
    let xcode = "Library/Developer/Xcode"

    init() throws {
        root = try FixtureRoot()
    }

    /// Every sub-tool of the standard registry, set up to list small fixture items.
    private var registry: ToolRegistry {
        .standard(
            largeFiles: LargeFiles(minimumSize: 1 << 20), oldFiles: oldFiles,
            developerJunk: DeveloperJunk(projectFolders: [root.url.appending(path: "Developer")]),
            // A fixed list, so the scan never reads the real `/Applications` (SAF-016).
            cachesAndLogs: CachesAndLogs(appNames: StubAppNames()))
    }

    private var oldFiles: OldFiles {
        OldFiles(periodMonths: 12, minimumSize: 1 << 20, lastUsedDate: { _ in nil }, addedDate: { _ in nil })
    }

    private func scan(excluding exclusions: [URL]) async -> [ScanItem] {
        let context = ScanContext(
            home: root.url,
            ownership: OwnershipMap(home: root.url, projectFolders: [root.url.appending(path: "Developer")]),
            protection: root.pathGuardConfiguration(userExclusions: exclusions), runningApps: StubRunningApps([]),
            toolRoot: root.url)
        var items: [ScanItem] = []
        for subTool in registry.subTools {
            items += await ShuckKitTestSupport.items(from: subTool, context: context)
        }
        return items
    }

    /// Whether the two paths are the same, or one is inside the other.
    private func overlap(_ a: URL, _ b: URL) -> Bool {
        let (first, second) = (a.pathComponents, b.pathComponents)
        return first.starts(with: second) || second.starts(with: first)
    }

    /// One item or more for every sub-tool that scans, each a place a user may want to exclude.
    private func makeWorld() throws {
        for folder in ["Excluded", "Kept"] {
            try root.file("Documents/\(folder)/big.bin", size: 2 << 20)
            try root.file("Documents/\(folder)/old.bin", size: 2 << 20, modified: longAgo)
        }
        // A package is one item, so an exclusion inside it hides the whole package.
        try root.file("Documents/Holder.pages/Secret/data", size: 2 << 20)
        try root.file("Documents/Holder.pages/Index", size: 4096)
        let live = try root.folder("Projects/Live")
        for name in ["Excluded", "Deep", "Kept"] {
            try root.derivedDataProject("\(name)-\(hash)", workspace: live, modified: .now)
        }
        for version in ["17.0", "17.1", "17.2"] { try root.deviceSupport("iOS", version) }
        for name in ["excluded", "kept"] {
            try root.file("Library/Developer/CoreSimulator/Caches/\(name)/f", size: 4096)
        }
        for name in ["Excluded", "Kept"] { try root.xcarchive(day: "2026-11-10", name: name) }
        for name in ["com.example.excluded", "com.example.kept"] {
            try root.file("Library/Caches/\(name)/f", size: 4096)
            try root.file("Library/Containers/\(name)/Data/Library/Caches/f", size: 4096)
        }
        for name in ["excluded.log", "kept.log"] { try root.file("Library/Logs/\(name)", size: 4096) }
        for name in ["Excluded", "Kept"] { try root.nodeProject("Developer/\(name)", edited: longAgo) }
    }

    private func makeTools() throws {
        for tool in ["opt/homebrew/bin/npm", "opt/homebrew/bin/pip3", "opt/homebrew/bin/brew"] {
            try root.tool(tool, .exits(0))
        }
        try root.xcrun(.exits(0))
        for folder in [
            ".npm/_cacache", "Library/Caches/pip", "Library/Caches/Homebrew", "Library/Logs/Homebrew",
            "opt/homebrew/Cellar/node/22.1.0/bin", "opt/homebrew/Caskroom/app/1.0",
        ] {
            try root.file("\(folder)/f", size: 4096)
        }
        try root.file("Library/Developer/CoreSimulator/Devices/ABCD/data", size: 4096)
    }

    @Test func noSubToolListsAnythingInsideOrHoldingAnExclusionSET001() async throws {
        try makeWorld()
        let excluded = try [
            "Documents/Excluded", "Documents/Holder.pages/Secret", "\(xcode)/DerivedData/Excluded-\(hash)",
            "\(xcode)/DerivedData/Deep-\(hash)/Build", "\(xcode)/iOS DeviceSupport/17.0",
            "Library/Developer/CoreSimulator/Caches/excluded", "\(xcode)/Archives/2026-11-10/Excluded.xcarchive",
            "Library/Caches/com.example.excluded", "Library/Logs/excluded.log",
            "Library/Containers/com.example.excluded/Data/Library/Caches", "Developer/Excluded",
        ].map { try root.url($0) }

        let before = await scan(excluding: [])
        let after = await scan(excluding: excluded)

        // The scan finds something in each sub-tool that scans, so the test notices a new one it does not cover.
        let available = registry.subTools.filter { $0.info.availability == .available }.map(\.id)
        #expect(Set(before.map(\.source)) == Set(available))
        for exclusion in excluded {
            #expect(
                before.contains { $0.url.map { overlap($0, exclusion) } == true },
                "Nothing listed for \(exclusion.lastPathComponent)")
        }
        for item in after {
            let url = try #require(item.url)
            #expect(!excluded.contains { overlap(url, $0) }, "\(url.path) is listed")
        }
        // The model drops rows with `hides` when the user adds an exclusion, so it must say what a rescan leaves out.
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(userExclusions: excluded), toolRoot: root.url)
        let listed = Set(after.map(\.target))
        for item in before {
            #expect(context.hides(item) == !listed.contains(item.target), "\(item.target.description)")
        }
        // Everything else is still listed.
        let expected = before.compactMap(\.url).filter { url in !excluded.contains { overlap(url, $0) } }
        #expect(Set(after.compactMap(\.url)) == Set(expected))
        #expect(!expected.isEmpty && after.count < before.count)
        for kept in try [
            "Documents/Kept", "\(xcode)/DerivedData/Kept-\(hash)", "Library/Logs/kept.log",
            "Developer/Kept/node_modules",
        ].map(root.url) {
            #expect(after.contains { $0.url.map { overlap($0, kept) } == true }, "\(kept.lastPathComponent)")
        }
    }

    @Test(
        arguments: [
            ("DEV-R07", ".npm/_cacache"), ("DEV-R07", ".npm"), ("DEV-R08", "Library/Caches/pip"),
            ("DEV-R09", "Library/Caches/Homebrew"), ("DEV-R09", "Library/Logs/Homebrew"),
            ("DEV-R09", "opt/homebrew/Cellar"), ("DEV-R09", "opt/homebrew/Cellar/node/22.1.0"),
            ("DEV-R09", "opt/homebrew/Caskroom"), ("DEV-R09", "opt/homebrew/Caskroom/app"),
            ("DEV-R09", "opt/homebrew"), ("DEV-R09", "opt"),
            ("DEV-R03", "Library/Developer/CoreSimulator/Devices/ABCD"),
            ("DEV-R03", "Library/Developer/CoreSimulator"), ("DEV-R03", "Library/Developer"),
        ])
    func aToolRuleIsHiddenWhenItsFolderIsOrHoldsAnExclusionSET001(rule: String, exclusion: String) async throws {
        try makeTools()
        let tools: Set = ["DEV-R03", "DEV-R07", "DEV-R08", "DEV-R09"]

        let before = Set(await scan(excluding: []).compactMap { $0.ruleMatch?.rule.id }).intersection(tools)
        let after = Set(
            await scan(excluding: [try root.url(exclusion)]).compactMap { $0.ruleMatch?.rule.id }
        ).intersection(tools)

        #expect(before == tools)
        #expect(!after.contains(rule))
        let hidden = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(userExclusions: [try root.url(exclusion)]),
            toolRoot: root.url)
        let items = await scan(excluding: [])
        for item in items {
            guard let id = item.ruleMatch?.rule.id, tools.contains(id) else { continue }
            #expect(hidden.hides(item) == (id == rule), "\(id)")
        }
        // A rule whose folder is elsewhere stays.
        #expect(after.contains(rule == "DEV-R07" ? "DEV-R09" : "DEV-R07"))
    }

    /// Only the prefix of the `brew` Shuck would run counts: an exclusion on the other candidate prefix hides nothing.
    @Test func anotherHomebrewPrefixDoesNotHideBrewCleanupSET001() async throws {
        try makeTools()
        try root.file("usr/local/Cellar/old/f", size: 4096)
        let other = try root.url("usr/local")

        let after = await scan(excluding: [other]).compactMap { $0.ruleMatch?.rule.id }
        #expect(after.contains("DEV-R09"))
    }

    /// An exclusion may be the home folder or a folder above it: then nothing is listed anywhere.
    @Test func excludingTheHomeFolderOrOneAboveItHidesEverythingSET001() async throws {
        try makeWorld()
        try makeTools()
        #expect(!(await scan(excluding: [])).isEmpty)

        #expect(await scan(excluding: [root.url]).isEmpty)
        #expect(await scan(excluding: [root.url.deletingLastPathComponent()]).isEmpty)
    }

    @Test func removingAnExclusionListsItAgainOnTheNextScanSET001() async throws {
        try makeWorld()
        let kept = try root.url("Documents/Kept")
        let before = await scan(excluding: [])
        let hidden = await scan(excluding: [kept])
        let after = await scan(excluding: [])

        #expect(before.contains { $0.url.map { overlap($0, kept) } == true })
        #expect(!hidden.contains { $0.url.map { overlap($0, kept) } == true })
        #expect(Set(after.compactMap(\.url)) == Set(before.compactMap(\.url)))
    }

    /// Applications is a tool of its own, not in the registry's sub-tools, so the test above cannot see it (D-186).
    @Test func applicationsListsNoAppInsideOrHoldingAnExclusionSET001() async throws {
        try root.app("Applications/Excluded.app", bundleID: "com.example.Excluded")
        try root.app("Applications/Holder.app", bundleID: "com.example.Holder")
        try root.app("Applications/Utilities/Tool.app", bundleID: "com.example.Tool")
        try root.app("Applications/Kept.app", bundleID: "com.example.Kept")
        try root.app("Applications/Games/Chess.app", bundleID: "com.example.Chess")
        let excluded = try [
            "Applications/Excluded.app", "Applications/Holder.app/Contents/Resources", "Applications/Utilities",
        ].map { try root.url($0) }
        let applications = Applications(
            appFolders: [try root.url("Applications")], isSystemProtected: { _ in false }, lastUsedDate: { _ in nil })

        func scan(excluding exclusions: [URL]) async -> [URL] {
            let context = ScanContext(
                home: root.url, protection: root.pathGuardConfiguration(userExclusions: exclusions))
            var urls: [URL] = []
            for await case .app(let app) in applications.scan(context) { urls.append(app.url) }
            return urls
        }

        let before = await scan(excluding: [])
        let after = await scan(excluding: excluded)
        #expect(before.count == 5)
        #expect(Set(after.map(\.lastPathComponent)) == ["Kept.app", "Chess.app"])
        // The page drops rows with `hides` when the user adds an exclusion, so it must agree with a rescan.
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration(userExclusions: excluded))
        for url in before {
            #expect(context.hides(url) == !after.contains(url), "\(url.lastPathComponent)")
        }
    }

    /// An app's leftovers are found by Applications too, so a leftover inside or holding an exclusion is not listed
    /// (APP-002, D-149).
    @Test func leftoversListNoItemInsideOrHoldingAnExclusionSET001() async throws {
        let id = "com.example.Notes"
        let url = try root.app("Applications/Notes.app", bundleID: id)
        let app = InstalledApp(
            url: url, name: "Notes", bundleID: id, snapshot: try #require(ItemSnapshot.read(url, while: { true })),
            modified: try #require(ModificationDate.read(at: url)))
        try root.file("Library/Caches/\(id)/data", size: 5)
        try root.file("Library/Application Support/\(id)/Documents/keep/data", size: 5)
        try root.file("Library/Logs/\(id)/data", size: 5)
        try root.file("Library/Group Containers/group.\(id)/data", size: 5)
        let excluded = try [
            "Library/Caches/\(id)/data", "Library/Application Support/\(id)/Documents/keep",
            "Library/Group Containers",
        ].map { try root.url($0) }
        let applications = Applications(
            appFolders: [try root.url("Applications")], appGroups: { _ in ["group.\(id)"] })

        func scan(excluding exclusions: [URL]) async -> Set<String> {
            let context = ScanContext(
                home: root.url, protection: root.pathGuardConfiguration(userExclusions: exclusions))
            var found: Set<String> = []
            for await case .item(let item) in applications.leftovers(of: app, context) {
                found.insert(item.url?.deletingLastPathComponent().lastPathComponent ?? "")
            }
            return found
        }

        #expect(await scan(excluding: []) == ["Caches", "Application Support", "Logs", "Group Containers"])
        #expect(await scan(excluding: excluded) == ["Logs"])
    }
}
