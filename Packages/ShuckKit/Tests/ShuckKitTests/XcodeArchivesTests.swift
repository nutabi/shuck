import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Developer Junk's Xcode Archives rule: one "Your data" item per archive, moved to the Trash, never selected
/// (DEV-R05, SAF-002, SAF-004, SAF-009, D-145).
struct XcodeArchivesTests {
    let root: FixtureRoot

    init() throws {
        root = try FixtureRoot()
    }

    private func items(running: Set<String> = [], ownership: OwnershipMap? = nil) async -> [ScanItem] {
        let context = ScanContext(
            home: root.url, ownership: ownership ?? OwnershipMap(home: root.url),
            protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running))
        var result: [ScanItem] = []
        for await event in DeveloperJunk().scan(context) {
            if case .item(let item) = event, item.ruleMatch?.rule.id == "DEV-R05" { result.append(item) }
        }
        return result
    }

    @Test func eachArchiveIsOneYourDataItemNeverSelectedDEVR05SAF002() async throws {
        let first = try root.xcarchive(day: "2026-11-10", name: "App 11-10-26, 9.41 AM")
        let second = try root.xcarchive(day: "2026-11-10", name: "Other")
        let third = try root.xcarchive(day: "2026-11-11", name: "App")

        let items = await items()

        #expect(Set(items.compactMap(\.url?.path)) == [first.path, second.path, third.path])
        for item in items {
            #expect(item.tier == .yourData && item.method == .trash && item.source == .developerJunk)
            #expect(item.selection == .unselected)
            #expect(item.snapshot?.kind == .folder && item.allocatedSize >= 4096)
            #expect(item.identity != nil && item.modified != nil)
            #expect(item.ruleMatch?.rule.apps == ["com.apple.dt.Xcode"] && item.apps == ["com.apple.dt.Xcode"])
            #expect(item.category.id == "xcode-archives")
            #expect(String(localized: item.reason).contains("keep the archive of every build you distribute"))
        }
    }

    @Test func aRunningXcodeDisablesEveryArchiveSAF009() async throws {
        try root.xcarchive(day: "2026-11-10", name: "App")

        let items = await items(running: ["com.apple.dt.Xcode"])

        #expect(items.map(\.selection) == [.appIsRunning(nil)])
    }

    @Test func onlyArchiveBundlesInDateFoldersAreListedDEVR05() async throws {
        #expect(await items().isEmpty)
        let real = try root.xcarchive(day: "2026-11-10", name: "Real")
        try root.file("Library/Developer/Xcode/Archives/stray.xcarchive/Info.plist", size: 10)
        try root.file("Library/Developer/Xcode/Archives/2026-11-10/notes.txt", size: 10)
        try root.file("Library/Developer/Xcode/Archives/2026-11-10/Plain/Info.plist", size: 10)
        try root.file("Library/Developer/Xcode/Archives/2026-11-10/file.xcarchive", size: 10)
        let elsewhere = try root.folder("Elsewhere")
        try root.symlink("Library/Developer/Xcode/Archives/2026-11-10/Link.xcarchive", to: elsewhere)
        try root.symlink("Library/Developer/Xcode/Archives/2026-12-01", to: elsewhere)

        #expect(await items().compactMap(\.url?.path) == [real.path])
    }

    @Test func theRuleTargetsArchiveBundlesOnlyAndTheMapGivesThemToDeveloperJunkFCL005() throws {
        let rule = try DeveloperJunk.archivesRule(home: root.url)
        let archive = try root.url("Library/Developer/Xcode/Archives/2026-11-10/App.xcarchive")
        let day = try root.url("Library/Developer/Xcode/Archives/2026-11-10")
        let inside = archive.appending(path: "Products")
        let other = try root.url("Library/Developer/Xcode/UserData/Snippets")

        #expect(rule.accepts(.path(archive), tier: .yourData, method: .trash, scope: .item))
        #expect(!rule.accepts(.path(archive), tier: .yourData, method: .delete, scope: .item))
        #expect(!rule.accepts(.path(archive), tier: .rebuildable, method: .trash, scope: .item))
        #expect(!rule.accepts(.path(day), tier: .yourData, method: .trash, scope: .item))
        #expect(!rule.accepts(.path(inside), tier: .yourData, method: .trash, scope: .item))
        #expect(rule.selection == .never && rule.tier == .yourData)
        let map = OwnershipMap(home: root.url)
        #expect(map.owners(of: archive) == [.developerJunk])
        #expect(map.owners(of: day).isEmpty && map.owners(of: other).isEmpty)
    }

    @Test func aScanLeavesOutArchivesTheMapGivesAnotherSubToolFCL005() async throws {
        try root.xcarchive(day: "2026-11-10", name: "App")

        #expect(await items(ownership: OwnershipMap(home: root.url, entries: [])).isEmpty)
    }

    @Test func archivesAreARootOfDeveloperJunkAndTheGuardAcceptsABundleDEVR05SAF007() throws {
        let archive = try root.xcarchive(day: "2026-11-10", name: "App")
        let roots = DeveloperJunk().allowedRoots(home: root.url)
        let guardrail = PathGuard(configuration: root.pathGuardConfiguration())

        #expect(roots.contains { $0.lastPathComponent == "Archives" })
        #expect(throws: Never.self) { try guardrail.validate(archive, allowedRoots: roots) }
        // The folder of a day and the Archives folder itself are not targets of the rule, and the guard refuses the
        // root itself (strictly inside).
        #expect(throws: PathGuardError.self) {
            try guardrail.validate(archive.deletingLastPathComponent().deletingLastPathComponent(), allowedRoots: roots)
        }
    }
}
