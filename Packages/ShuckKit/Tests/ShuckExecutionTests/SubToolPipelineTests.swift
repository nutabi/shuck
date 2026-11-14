import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Every sub-tool's items go through the whole safety pipeline: scan, plan, run, History, and Restore where the method
/// allows it. Trash items are put back (LRG-004, OLD-004, DEV-R05, FCL-003, SAF-002, SAF-004, SAF-005, HIS-003); Delete
/// items of rules are gone for good and keep what the sub-tool expects to find (DEV-R01, DEV-R02, DEV-R04, DEV-R06,
/// DEV-006, CAC-004, CAC-005, SAF-004, SAF-006, DEV-005, DEV-007).
struct SubToolPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func results() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
    }

    // MARK: - Trash: scan, plan, run, History, Restore

    /// What a Trash sub-tool lists in the fixture root.
    struct TrashSetup {
        let rig: Rig
        /// The items the user chooses, from everything the sub-tool lists.
        var pick: @Sendable ([ScanItem]) -> [ScanItem] = { $0 }
        let listed: [URL]
        let kept: [URL]
    }

    struct TrashCase: Sendable, CustomTestStringConvertible {
        let name: String
        let tool: ToolID
        let make: @Sendable (FixtureRoot) async throws -> TrashSetup

        var testDescription: String { name }

        static let all = personalFiles + others

        private static let personalFiles = PersonalFilesCase.all.map { tool in
            TrashCase(name: tool.name, tool: tool.tool) { root in
                let (subTool, listed, other) = try tool.make(root)
                let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration())
                return TrashSetup(rig: Rig(subTool: subTool, context: context), listed: [listed], kept: [other])
            }
        }

        private static let others: [TrashCase] = [
            TrashCase(name: "Xcode archives (DEV-R05)", tool: .developerJunk) { root in
                let archive = try root.xcarchive(day: "2026-11-10", name: "App")
                let kept = try root.xcarchive(day: "2026-11-11", name: "Kept")
                // The user chooses it by hand; a run of the chosen item moves only it.
                return TrashSetup(
                    rig: .developerJunk(root),
                    pick: { items in
                        let picked = items.filter { $0.url?.path == archive.path }
                        #expect(picked.map(\.selection) == [.unselected])
                        return picked
                    }, listed: [archive], kept: [kept])
            },
            TrashCase(name: "A test sub-tool (FCL-003)", tool: FixtureSubTool.id) { root in
                let wanted = [
                    try root.file("Pile/a.bin", size: 4_000), try root.file("Pile/Deeper/b.bin", size: 8_000),
                ]
                let notOwned = try root.file("Elsewhere/c.bin", size: 4_000)
                let ownership = OwnershipMap(home: root.url, entries: [.init("Pile", owners: [FixtureSubTool.id])])
                let registry = ToolRegistry(tools: [Tool(info: FixtureSubTool().info, subTools: [FixtureSubTool()])])
                let subTool = try #require(registry.subTool(FixtureSubTool.id))
                let context = ScanContext(home: root.url, ownership: ownership)
                return TrashSetup(rig: Rig(subTool: subTool, context: context), listed: wanted, kept: [notOwned])
            },
        ]
    }

    /// The files keep the modification dates they were written with, to the nanosecond, so this also checks that the
    /// scan and the run read the date at the same precision (D-132).
    @Test(arguments: TrashCase.all)
    func itemsAreTrashedLoggedAsRestorableAndRestoredLRG004OLD004DEVR05FCL003SAF005HIS003(_ trashCase: TrashCase)
        async throws
    {
        let setup = try await trashCase.make(root)
        let picked = setup.pick(await setup.rig.scan())
        #expect(Set(picked.compactMap { $0.url?.path }) == Set(setup.listed.map(\.path)))

        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(setup.rig.plan(picked, pathGuard))

        #expect(report.outcomes.count == setup.listed.count && report.outcomes.allSatisfy { $0.result.isDone })
        #expect(setup.listed.allSatisfy { !exists($0) } && setup.kept.allSatisfy(exists))
        let history = try HistoryLog.read(folder: root.historyFolder)
        let results = history.records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == Array(repeating: trashCase.tool, count: setup.listed.count))
        #expect(results.allSatisfy { $0.operation == .trash && $0.tier == .yourData && $0.status == .ok })
        #expect(results.allSatisfy { $0.trashedPath != nil })
        let trashed = history.entries().compactMap { entry -> TrashedItem? in
            guard case .restorable(let item) = entry.restorability else { return nil }
            return item
        }
        #expect(trashed.count == setup.listed.count && trashed.allSatisfy { exists($0.trashedURL) })

        let restore = RestoreExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: root.historyFolder),
            trash: FakeTrash(folder: root.trashFolder), toolRunner: ToolRunner(executableRoots: [root.url]))
        let restored = await restore.run(trashed.map { RestoreRequest(item: $0) })

        #expect(restored.outcomes.count == trashed.count)
        #expect(restored.outcomes.allSatisfy { if case .done = $0.result { true } else { false } })
        #expect(setup.listed.allSatisfy(exists))
    }

    // MARK: - Delete: scan, plan, run, History

    /// What a rule-based sub-tool lists, and what its Delete run must do.
    struct DeleteSetup {
        let rig: Rig
        let tool: ToolID
        /// How many items the scan lists in all, if the case checks it, and how many of them it selects.
        var listed: Int?
        let selected: Int
        /// Gone after the run; folders the sub-tool expects to find, emptied; and what must stay.
        let gone: [URL]
        var emptied: [URL] = []
        let kept: [URL]
    }

    struct DeleteCase: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable (FixtureRoot) async throws -> DeleteSetup

        var testDescription: String { name }

        static let all: [DeleteCase] = [
            DeleteCase(name: "Caches & Logs: caches keep their folder (CAC-004)") { root in
                let cache = try root.staleFolder("Library/Caches/com.example.Notes")
                let container = try root.staleFolder("Library/Containers/com.example.Mail/Data/Library/Caches")
                let recent = try root.file("Library/Caches/com.example.Recent/data.db", size: 4096)
                return DeleteSetup(
                    rig: .cachesAndLogs(root), tool: .cachesAndLogs, selected: 2, gone: [],
                    emptied: [cache, container],
                    kept: [recent])
            },
            DeleteCase(name: "Caches & Logs: stale logs (CAC-005)") { root in
                let old = try root.file("Library/Logs/old.log", size: 4096, modified: .longAgo)
                let recent = try root.file("Library/Logs/new.log", size: 4096)
                let folder = try root.staleFolder("Library/Logs/Tool")
                return DeleteSetup(
                    rig: .cachesAndLogs(root), tool: .cachesAndLogs, selected: 2, gone: [old], emptied: [folder],
                    kept: [recent, try root.url("Library/Logs")])
            },
            DeleteCase(name: "Developer Junk: DerivedData projects (DEV-R01)") { root in
                let hash = "abcdefghijklmnopqrstuvwxyzab"
                let stale = try root.derivedDataProject("Old-\(hash)", workspace: nil, modified: .longAgo)
                let gone = try root.derivedDataProject(
                    "Gone-\(hash)", workspace: root.url("Projects/Gone"), modified: .now)
                let recent = try root.derivedDataProject(
                    "Recent-\(hash)", workspace: root.folder("Projects/Live"), modified: .now)
                // DerivedData itself stays, as Xcode expects it.
                return DeleteSetup(
                    rig: .developerJunk(root), tool: .developerJunk, selected: 2, gone: [stale, gone],
                    kept: [recent, stale.deletingLastPathComponent()])
            },
            DeleteCase(name: "Developer Junk: old device support, the newest stays (DEV-R02)") { root in
                let old = try root.deviceSupport("iOS", "16.4 (20E247)")
                let newest = try root.deviceSupport("iOS", "17.2 (21C62) arm64e")
                return DeleteSetup(
                    rig: .developerJunk(root), tool: .developerJunk, selected: 1, gone: [old],
                    kept: [newest, newest.deletingLastPathComponent()])
            },
            DeleteCase(name: "Developer Junk: simulator caches, not the devices (DEV-R04, DEV-007)") { root in
                let cache = try root.file("Library/Developer/CoreSimulator/Caches/dyld/21C62/cache", size: 4096)
                let device = try root.file("Library/Developer/CoreSimulator/Devices/ABCD-1234/device.plist", size: 10)
                return DeleteSetup(
                    rig: .developerJunk(root), tool: .developerJunk, selected: 1, gone: [cache],
                    kept: [device, try root.url("Library/Developer/CoreSimulator/Caches")])
            },
            DeleteCase(name: "Developer Junk: a stale project's node_modules (DEV-R06)") { root in
                let stale = try root.nodeProject("Developer/stale", edited: .longAgo)
                let busy = try root.nodeProject("Developer/busy", edited: .now)
                // Only `node_modules` goes: the project's own files stay, and so does the other project.
                let own = ["package.json", "package-lock.json", "src/index.js"].map { stale.appending(path: $0) }
                return DeleteSetup(
                    rig: .nodeModules(root), tool: .developerJunk, listed: 2, selected: 1,
                    gone: [stale.appending(path: "node_modules")],
                    kept: own + [busy.appending(path: "node_modules/dep/index.js")])
            },
        ]
    }

    @Test(arguments: DeleteCase.all)
    func rebuildableItemsAreDeletedForGoodAndLoggedNotRestorableSAF004SAF006(_ deleteCase: DeleteCase) async throws {
        let setup = try await deleteCase.make(root)
        let items = await setup.rig.scan()
        let selected = items.filter { $0.selection == .selected }
        #expect(selected.count == setup.selected && items.count == setup.listed ?? items.count)

        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(setup.rig.plan(selected, pathGuard))

        #expect(report.outcomes.count == setup.selected && report.outcomes.allSatisfy { $0.result == .done(nil) })
        #expect(setup.gone.allSatisfy { !exists($0) } && setup.kept.allSatisfy(exists))
        for folder in setup.emptied {
            #expect(exists(folder), "The folder stays, as the app expects it")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
        let history = try HistoryLog.read(folder: root.historyFolder)
        let results = history.records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == Array(repeating: setup.tool, count: setup.selected))
        #expect(results.allSatisfy { $0.operation == .delete && $0.tier == .rebuildable && $0.status == .ok })
        #expect(results.allSatisfy { $0.trashedPath == nil })
        #expect(history.entries().map(\.restorability) == Array(repeating: .permanent, count: setup.selected))
    }
}

/// A sub-tool of the personal-files scan, the file it lists and a file next to it that it leaves alone (LRG-004, OLD-004,
/// FCL-003). The two sub-tools differ only in what they list, so one set of tests runs for both.
struct PersonalFilesCase: CustomTestStringConvertible, Sendable {
    let name: String
    let tool: ToolID
    /// Creates the fixtures in `root` and returns the sub-tool, the file it lists and the file it leaves alone.
    let make: @Sendable (FixtureRoot) throws -> (subTool: any SubTool, listed: URL, other: URL)

    var testDescription: String { name }

    static let largeFiles = PersonalFilesCase(name: "Large Files (LRG-004)", tool: .largeFiles) { root in
        let large = try root.file("Downloads/Installer.dmg", size: 1 << 20)
        let small = try root.file("Downloads/notes.txt", size: 10)
        return (LargeFiles(minimumSize: 1 << 20), large, small)
    }

    static let oldFiles = PersonalFilesCase(name: "Old Files (OLD-004)", tool: .oldFiles) { root in
        let yearsAgo = Date.now.addingTimeInterval(-2 * 365 * 86_400)
        let old = try root.file("Downloads/Installer.dmg", size: 1 << 20, modified: yearsAgo)
        let recent = try root.file("Downloads/Recent.dmg", size: 1 << 20)
        // Every fixture file was added just now (D-140).
        let subTool = OldFiles(minimumSize: 1 << 20, lastUsedDate: { _ in nil }, addedDate: { _ in nil })
        return (subTool, old, recent)
    }

    static let all = [largeFiles, oldFiles]
}
