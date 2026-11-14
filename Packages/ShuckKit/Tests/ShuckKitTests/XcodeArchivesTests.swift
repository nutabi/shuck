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
        // The rule takes an archive only as Your data moved to the Trash, and never preselects it.
        let rule = try DeveloperJunk.archivesRule(home: root.url)
        #expect(rule.accepts(.path(first), tier: .yourData, method: .trash, scope: .item))
        #expect(!rule.accepts(.path(first), tier: .yourData, method: .delete, scope: .item))
        #expect(!rule.accepts(.path(first), tier: .rebuildable, method: .trash, scope: .item))
        #expect(rule.selection == .never && rule.tier == .yourData)
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
