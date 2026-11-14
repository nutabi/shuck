import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// What every Developer Junk rule over Xcode's folders shares: it lists only real entries (DEV-002), is disabled while
/// Xcode runs (SAF-009), leaves out what the map gives another sub-tool (FCL-005), and accepts only its own targets
/// (DEV-007, SAF-007). Each rule's own behavior is tested in its own file.
struct DeveloperJunkRulesTests {
    private static let suffix = "abcdefghijklmnopqrstuvwxyzab"
    private static let xcode = "Library/Developer/Xcode"

    /// One Xcode rule: how to give it one real entry and some strays, and what its rule accepts.
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        /// Bundle IDs whose running disables the rule's items.
        let runningApps: [String]
        let rule: @Sendable (URL) throws -> CleanupRule
        let tier: Tier
        let method: ActionMethod
        let makeReal: @Sendable (FixtureRoot) throws -> Void
        let makeStrays: @Sendable (FixtureRoot) throws -> Void
        let realName: String
        /// Paths relative to the home folder.
        let accepted: [String]
        let refused: [String]
        /// A path the map gives to Developer Junk, and one it gives to nobody.
        let owned: [String]
        let unowned: [String]

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "DerivedData", runningApps: ["com.apple.dt.xcode"],
            rule: { try DeveloperJunk.derivedDataRule(home: $0) }, tier: .rebuildable, method: .delete,
            makeReal: { try $0.derivedDataProject("Real-\(suffix)", workspace: nil, modified: .now - 31 * 86_400) },
            makeStrays: {
                try $0.file("\(xcode)/DerivedData/stray.txt", size: 10)
                try $0.symlink("\(xcode)/DerivedData/Link", to: $0.folder("Elsewhere"))
            },
            realName: "Real-\(suffix)", accepted: ["\(xcode)/DerivedData/Mine"],
            refused: ["\(xcode)/UserData/Snippets"], owned: ["\(xcode)/DerivedData/Mine"],
            unowned: ["\(xcode)/UserData/Snippets"]),
        Case(
            name: "DeviceSupport", runningApps: ["com.apple.dt.Xcode"],
            rule: { try DeveloperJunk.deviceSupportRule(home: $0) }, tier: .rebuildable, method: .delete,
            makeReal: { try $0.deviceSupport("iOS", "16.4 (20E247)") },
            makeStrays: {
                try $0.file("\(xcode)/iOS DeviceSupport/stray.txt", size: 10)
                try $0.symlink("\(xcode)/iOS DeviceSupport/18.0 (22A1)", to: $0.folder("Elsewhere"))
                try $0.file("\(xcode)/UserData/Snippets/one.codesnippet", size: 10)
                try $0.symlink("\(xcode)/tvOS DeviceSupport", to: $0.folder("Elsewhere/tv"))
            },
            realName: "16.4 (20E247)", accepted: ["\(xcode)/watchOS DeviceSupport/10.0 (21R355)"],
            refused: [
                "\(xcode)/UserData/Snippets", "\(xcode)/iOS DeviceSupport",
                "\(xcode)/watchOS DeviceSupport/10.0 (21R355)/Symbols",
            ],
            owned: ["\(xcode)/watchOS DeviceSupport/10.0 (21R355)", "\(xcode)/iOS DeviceSupport"],
            unowned: ["\(xcode)/UserData/Snippets"]),
        Case(
            name: "SimulatorCaches", runningApps: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"],
            rule: { try DeveloperJunk.simulatorCachesRule(home: $0) }, tier: .rebuildable, method: .delete,
            makeReal: { try $0.file("Library/Developer/CoreSimulator/Caches/real/file", size: 10) },
            makeStrays: {
                try $0.symlink("Library/Developer/CoreSimulator/Caches/link", to: $0.folder("Elsewhere"))
            },
            realName: "real", accepted: ["Library/Developer/CoreSimulator/Caches/dyld"],
            refused: [
                "Library/Developer/CoreSimulator/Caches", "Library/Developer/CoreSimulator/Caches/dyld/cache",
                "Library/Developer/CoreSimulator/Devices/ABCD-1234", "Library/Developer/CoreSimulator/Devices",
                "Library/Developer/CoreSimulator/Volumes/iOS_21C62",
            ],
            owned: ["Library/Developer/CoreSimulator/Caches/dyld"],
            unowned: ["Library/Developer/CoreSimulator/Devices/ABCD-1234", "Library/Developer/CoreSimulator/Devices"]),
        Case(
            name: "XcodeArchives", runningApps: ["com.apple.dt.Xcode"],
            rule: { try DeveloperJunk.archivesRule(home: $0) }, tier: .yourData, method: .trash,
            makeReal: { try $0.xcarchive(day: "2026-11-10", name: "Real") },
            makeStrays: {
                let archives = "\(xcode)/Archives"
                try $0.file("\(archives)/stray.xcarchive/Info.plist", size: 10)
                try $0.file("\(archives)/2026-11-10/notes.txt", size: 10)
                try $0.file("\(archives)/2026-11-10/Plain/Info.plist", size: 10)
                try $0.file("\(archives)/2026-11-10/file.xcarchive", size: 10)
                let elsewhere = try $0.folder("Elsewhere")
                try $0.symlink("\(archives)/2026-11-10/Link.xcarchive", to: elsewhere)
                try $0.symlink("\(archives)/2026-12-01", to: elsewhere)
            },
            realName: "Real.xcarchive", accepted: ["\(xcode)/Archives/2026-11-10/App.xcarchive"],
            refused: [
                "\(xcode)/Archives/2026-11-10", "\(xcode)/Archives/2026-11-10/App.xcarchive/Products",
            ],
            owned: ["\(xcode)/Archives/2026-11-10/App.xcarchive"],
            unowned: ["\(xcode)/Archives/2026-11-10", "\(xcode)/UserData/Snippets"]),
    ]

    private func items(
        _ root: FixtureRoot, running: [String] = [], ownership: OwnershipMap? = nil
    ) async -> [ScanItem] {
        let context = ScanContext(
            home: root.url, ownership: ownership ?? OwnershipMap(home: root.url),
            protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(Set(running)))
        var result: [ScanItem] = []
        for await event in DeveloperJunk().scan(context) {
            if case .item(let item) = event { result.append(item) }
        }
        return result
    }

    @Test(arguments: cases)
    func onlyRealEntriesAreListedNotStraysOrLinksDEV002DEVR05(_ rule: Case) async throws {
        let root = try FixtureRoot()
        #expect(await items(root).isEmpty)
        try rule.makeReal(root)
        try rule.makeStrays(root)

        #expect(await items(root).compactMap { $0.url?.lastPathComponent } == [rule.realName])
    }

    @Test(arguments: cases)
    func aRunningXcodeDisablesEveryItemSAF009(_ rule: Case) async throws {
        for app in rule.runningApps {
            let root = try FixtureRoot()
            try rule.makeReal(root)

            let items = await items(root, running: [app])

            #expect(items.map(\.selection) == [.appIsRunning(nil)], "\(rule.name) with \(app)")
        }
    }

    @Test(arguments: cases)
    func aScanLeavesOutWhatTheMapGivesAnotherSubToolFCL005(_ rule: Case) async throws {
        let root = try FixtureRoot()
        try rule.makeReal(root)
        #expect(await items(root).count == 1)

        #expect(await items(root, ownership: OwnershipMap(home: root.url, entries: [])).isEmpty)
    }

    @Test(arguments: cases)
    func theRuleAcceptsOnlyItsTargetsAndTheMapGivesThemToDeveloperJunkDEV007FCL005SAF007(_ rule: Case) throws {
        let root = try FixtureRoot()
        let cleanup = try rule.rule(root.url)
        func accepts(_ path: String) throws -> Bool {
            cleanup.accepts(.path(try root.url(path)), tier: rule.tier, method: rule.method, scope: .item)
        }

        for path in rule.accepted { #expect(try accepts(path), "\(path)") }
        for path in rule.refused { #expect(try !accepts(path), "\(path)") }
        #expect(cleanup.apps.map { $0.lowercased() }.sorted() == rule.runningApps.map { $0.lowercased() }.sorted())
        let map = OwnershipMap(home: root.url)
        for path in rule.owned { #expect(map.owners(of: try root.url(path)) == [.developerJunk], "\(path)") }
        for path in rule.unowned { #expect(map.owners(of: try root.url(path)).isEmpty, "\(path)") }
    }
}
