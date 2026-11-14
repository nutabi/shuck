import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// A plan refuses an item that no rule or sub-tool may act on, and what it refuses stays where it is (SAF-004, SAF-007,
/// SAF-008, CAC-008, DEV-007, R-03). Every case builds the item a caller that skips the review could hand to a plan.
struct PlanRefusalTests {
    /// The plan asked for, the error it must refuse with (any `PlanError` if `nil`) and what must not be touched.
    struct Refusal: Sendable {
        let attempt: @Sendable () throws -> Plan
        var error: PlanError?
        let untouched: URL
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable (FixtureRoot, PathGuard) async throws -> Refusal

        var testDescription: String { name }

        static let all = refusals + withoutARule

        private static let refusals: [Case] = [
            Case(name: "Docker's container caches, by any sub-tool (DEV-007)") { root, pathGuard in
                let folder = try root.staleFolder("Library/Containers/com.docker.docker/Data/Library/Caches")
                let item = try root.unlisted(folder, source: .cachesAndLogs, scope: .contents)
                return Refusal(
                    attempt: { try Rig.cachesAndLogs(root).plan([item], pathGuard) },
                    untouched: folder.appending(path: "data.db"))
            },
            Case(name: "A folder outside Caches & Logs' roots (CAC-008, SAF-007)") { root, pathGuard in
                let folder = try root.staleFolder("Library/Application Support/Notes")
                let item = try root.unlisted(folder, source: .cachesAndLogs, scope: .contents)
                return Refusal(
                    attempt: { try Rig.cachesAndLogs(root).plan([item], pathGuard) },
                    untouched: folder.appending(path: "data.db"))
            },
            Case(name: "A simulator device, by any sub-tool item (DEV-007)") { root, pathGuard in
                let device = try root.file("Library/Developer/CoreSimulator/Devices/ABCD-1234/device.plist", size: 10)
                let item = try root.unlisted(device.deletingLastPathComponent(), source: .developerJunk)
                return Refusal(attempt: { try Rig.developerJunk(root).plan([item], pathGuard) }, untouched: device)
            },
            Case(name: "The rest of Xcode, even next to device support (SAF-007)") { root, pathGuard in
                let other = try root.file("Library/Developer/Xcode/UserData/Snippets/one.codesnippet", size: 10)
                try root.deviceSupport("iOS", "16.4 (20E247)")
                let item = try root.unlisted(other.deletingLastPathComponent(), source: .developerJunk)
                return Refusal(attempt: { try Rig.developerJunk(root).plan([item], pathGuard) }, untouched: other)
            },
            Case(name: "The rest of Xcode, moved to the Trash (SAF-007)") { root, pathGuard in
                let other = try root.file("Library/Developer/Xcode/UserData/Snippets/one.codesnippet", size: 10)
                let folder = other.deletingLastPathComponent()
                let item = try root.unlisted(folder, source: .developerJunk, tier: .yourData, method: .trash)
                // Without a rule the plan refuses the item before the guard sees it (SAF-008, R-03).
                return Refusal(
                    attempt: { try Rig.developerJunk(root).plan([item], pathGuard) }, error: .ruleRequired(folder.path),
                    untouched: other)
            },
            Case(name: "A node_modules outside the project folders (SAF-007)") { root, pathGuard in
                let inside = try root.nodeProject("Developer/app", edited: .longAgo)
                let outside = try root.nodeProject("Documents/site", edited: .longAgo).appending(path: "node_modules")
                let rig = Rig.nodeModules(root)
                let item = try #require(await rig.scan().first)
                let moved = try PlannedItem(
                    url: outside, tier: .rebuildable, method: .delete, snapshot: #require(item.snapshot),
                    modified: ModificationDate.read(at: outside), ruleMatch: item.ruleMatch)
                return Refusal(
                    attempt: {
                        try Plan(
                            tool: .developerJunk, allowedRoots: rig.subTool.allowedRoots(home: root.url),
                            items: [moved],
                            pathGuard: pathGuard)
                    }, untouched: inside.appending(path: "node_modules"))
            },
            Case(name: "An Xcode archive deleted (SAF-004)") { root, pathGuard in
                let archive = try root.xcarchive(day: "2026-11-10", name: "App")
                let item = try #require(await Rig.developerJunk(root).scan().first)
                let deleting = try PlannedItem(
                    url: archive, tier: .yourData, method: .delete, snapshot: #require(item.snapshot),
                    modified: item.modified, ruleMatch: item.ruleMatch)
                return Refusal(
                    attempt: {
                        try Plan(
                            tool: .developerJunk, allowedRoots: DeveloperJunk().allowedRoots(home: root.url),
                            items: [deleting], pathGuard: pathGuard)
                    }, error: .methodNotAllowed(archive.path, tier: .yourData, method: .delete), untouched: archive)
            },
            Case(name: "An archive's date folder, which its rule does not accept (SAF-008)") { root, pathGuard in
                let dateFolder = try root.xcarchive(day: "2026-11-10", name: "App").deletingLastPathComponent()
                let match = try #require(await Rig.developerJunk(root).scan().first?.ruleMatch)
                let item = try root.byHand(dateFolder, source: .developerJunk, ruleMatch: match)
                return Refusal(
                    attempt: { try Rig.developerJunk(root).plan([item], pathGuard) },
                    error: .ruleMismatch(dateFolder.path),
                    untouched: dateFolder)
            },
            Case(name: "A protected file a sub-tool finds (SAF-007)") { root, pathGuard in
                let key = try root.file(".ssh/id_ed25519", size: 10)
                let ownership = OwnershipMap(home: root.url, entries: [.init(".ssh", owners: [FixtureSubTool.id])])
                let rig = Rig(subTool: FixtureSubTool(), context: ScanContext(home: root.url, ownership: ownership))
                let items = await rig.scan()
                #expect(items.compactMap { $0.url?.path } == [key.path])
                return Refusal(attempt: { try rig.plan(items, pathGuard) }, untouched: key)
            },
        ]

        /// R-03's probe: a "Your data" Trash item of a rule-based sub-tool with no rule.
        private static let withoutARule = [
            "Developer/thesis", "Developer/app", "Library/Developer/Xcode/Archives/2026-11-10",
        ].map { path in
            Case(name: "Without a rule: \(path) (SAF-008, R-03)") { root, pathGuard in
                let target = try root.url(path)
                let item = try #require(try root.rulelessItems().first { $0.url == target })
                let junk = DeveloperJunk(projectFolders: [try root.url("Developer")])
                #expect(junk.requiresRule && CachesAndLogs().requiresRule)
                return Refusal(
                    attempt: { try Plan(subTool: junk, items: [item], pathGuard: pathGuard) },
                    error: .ruleRequired(item.target.description), untouched: try root.url(path))
            }
        }
    }

    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test(arguments: Case.all)
    func aPlanRefusesItAndLeavesItAloneSAF004SAF007SAF008CAC008DEV007(_ refusal: Case) async throws {
        let refusal = try await refusal.make(root, pathGuard)

        let error = #expect(throws: PlanError.self) { try refusal.attempt() }

        if let expected = refusal.error { #expect(error == expected) }
        #expect(FileManager.default.fileExists(atPath: refusal.untouched.path))
    }
}
