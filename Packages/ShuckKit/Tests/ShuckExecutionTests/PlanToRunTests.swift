import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// What happens between a plan and its run, for every sub-tool and kind of item that plans through the Execution
/// layer. A rule every one of them follows is one test whose arguments are all of them (SAF-008, SAF-009, SET-001).
struct PlanToRunTests {
    /// A plan, what changes before it runs, and what the run must do to each item.
    struct Scenario: Sendable {
        var plan: Plan
        /// Per item: the skip it ends with, or `nil` for done.
        var skipped: [SkipCode?] = []
        /// Files that must be there after the run, and files that must not.
        var kept: [URL] = []
        var gone: [URL] = []
        /// Applied after the plan is made and before the run.
        var change: @Sendable () throws -> Void = {}
        /// Apps that started after the scan.
        var running: Set<String> = []
        /// A folder the user excluded after the plan was made.
        var excluded: URL?
        /// Whether the plan's one item is a tool command, which must not start when it is skipped.
        var isTool = false
        var verify: @Sendable (RunReport) throws -> Void = { _ in }
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable (FixtureRoot, PathGuard) async throws -> Scenario

        var testDescription: String { name }
    }

    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func run(_ scenario: Scenario, using pathGuard: PathGuard? = nil) async throws -> RunReport {
        let executor = try PlanExecutor(
            root: root, pathGuard: pathGuard ?? self.pathGuard, runningApps: StubRunningApps(scenario.running))
        return await Task { await executor.run(scenario.plan) }.value
    }

    private func results() throws -> [HistoryRecord] {
        try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Changed since the scan, an app started since, and the same without the review (SAF-008, SAF-009)

    /// Every item ends with the outcome the scenario names, is logged with it, and nothing it skipped is touched.
    private func expectOutcomes(_ scenario: Scenario, _ report: RunReport) throws {
        #expect(report.outcomes.count == scenario.skipped.count)
        for (outcome, skip) in zip(report.outcomes, scenario.skipped) {
            if let skip {
                #expect(outcome.result.skipCode == skip, "\(outcome.result)")
            } else {
                #expect(outcome.result.isDone, "\(outcome.result)")
            }
        }
        #expect(scenario.kept.allSatisfy(exists) && !scenario.gone.contains(where: exists))
        #expect(!root.aFakeToolRan)
        let results = try results()
        #expect(results.map { $0.detail.flatMap(SkipCode.init(detail:)) } == scenario.skipped)
        #expect(results.map(\.status) == scenario.skipped.map { $0 == nil ? .ok : .skipped })
        try scenario.verify(report)
    }

    static let changedSinceTheScan: [Case] = pipelines + personalFiles

    private static let pipelines: [Case] = [
        Case(name: "Trash items that are gone, grown, replaced or unchanged") { root, pathGuard in
            let gone = try root.file("Downloads/gone.zip", size: 10_000)
            let grown = try root.file("Downloads/grown.log", size: 10_000)
            let replaced = try root.file("Downloads/replaced.dat", size: 10_000)
            let unchanged = try root.file("Downloads/unchanged.iso", size: 10_000)
            let items = try [gone, grown, replaced, unchanged].map {
                try root.planned($0, tier: .yourData, method: .trash)
            }
            let plan = try Plan(tool: .largeFiles, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
            return Scenario(
                plan: plan, skipped: [.missing, .changed, .changed, nil], kept: [grown, replaced],
                gone: [unchanged],
                change: {
                    try FileManager.default.removeItem(at: gone)
                    try Data(count: 1_000_000).write(to: grown)
                    try FileManager.default.removeItem(at: replaced)
                    try root.folder("Downloads/replaced.dat")
                },
                verify: { report in
                    // What the item is now comes with the skip.
                    guard case .skipped(.changed(let grownNow)) = report.outcomes[1].result,
                        case .skipped(.changed(let replacedNow)) = report.outcomes[2].result
                    else {
                        Issue.record("Expected the changed items to be skipped: \(report.outcomes.map(\.result))")
                        return
                    }
                    #expect(grownNow.kind == .file && grownNow.allocatedSize >= 1_000_000)
                    #expect(replacedNow.kind == .folder)
                })
        },
        // A file being written keeps its kind and, within 1%, its size, but not its modification date (D-132).
        Case(name: "A Trash item whose only change is its modification date") { root, pathGuard in
            let touched = try root.file("Downloads/touched.mov", size: 10_000)
            let unchanged = try root.file("Downloads/unchanged.mov", size: 10_000)
            let items = try [touched, unchanged].map { try root.planned($0, tier: .yourData, method: .trash) }
            let plan = try Plan(tool: .largeFiles, allowedRoots: [root.url], items: items, pathGuard: pathGuard)
            return Scenario(
                plan: plan, skipped: [.modifiedSinceScan, nil], kept: [touched], gone: [unchanged],
                change: {
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: touched.path)
                })
        },
        // Nothing shows that an item whose scan read no date is unchanged, so it is skipped (D-132).
        Case(name: "A Trash item without a scan date") { root, pathGuard in
            let file = try root.file("Downloads/undated.mov", size: 10_000)
            let item = PlannedItem(
                url: file, tier: .yourData, method: .trash, snapshot: try #require(ItemSnapshot.read(file)))
            let plan = try Plan(tool: .largeFiles, allowedRoots: [root.url], items: [item], pathGuard: pathGuard)
            return Scenario(plan: plan, skipped: [.modifiedSinceScan], kept: [file])
        },
        Case(name: "A rule's item in a cache folder used again") { root, pathGuard in
            let cache = try root.staleFolder("Library/Caches/com.example.Notes")
            let plan = try await Rig.cachesAndLogs(root).plan(pathGuard)
            return Scenario(
                plan: plan, skipped: [.modifiedSinceScan], kept: [cache.appending(path: "data.db")],
                change: {
                    // The app wrote a new file, which changes the folder's own date.
                    try root.file("Library/Caches/com.example.Notes/new.db", size: 10)
                })
        },
        Case(name: "Developer Junk: a DerivedData project built again") { root, pathGuard in
            let hash = "abcdefghijklmnopqrstuvwxyzab"
            let folder = try root.derivedDataProject("Old-\(hash)", workspace: nil, modified: .longAgo)
            let plan = try await Rig.developerJunk(root).plan(pathGuard)
            return Scenario(
                plan: plan, skipped: [.modifiedSinceScan], kept: [folder],
                change: {
                    try FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: folder.path)
                })
        },
        Case(name: "Developer Junk: a node_modules changed") { root, pathGuard in
            let modules = try root.nodeProject("Developer/app", edited: .longAgo).appending(path: "node_modules")
            let plan = try await Rig.nodeModules(root).plan(pathGuard)
            return Scenario(
                plan: plan, skipped: [.modifiedSinceScan], kept: [modules],
                change: {
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date.now.addingTimeInterval(-60)], ofItemAtPath: modules.path)
                })
        },
        Case(name: "Developer Junk: an Xcode archive changed (Trash)") { root, pathGuard in
            let archive = try root.xcarchive(day: "2026-11-10", name: "App")
            let plan = try await Rig.developerJunk(root).plan(pathGuard)
            return Scenario(
                plan: plan, skipped: [.modifiedSinceScan], kept: [archive],
                change: {
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date.now.addingTimeInterval(-3_600)], ofItemAtPath: archive.path)
                })
        },
        Case(name: "A rule's item whose date changed by a day") { root, pathGuard in
            try ruleDate(86_400)(root, pathGuard)
        },
        Case(name: "A rule's item whose date changed back by a day") { root, pathGuard in
            try ruleDate(-86_400)(root, pathGuard)
        },
        Case(name: "A rule's folder recreated and active again") { root, pathGuard in
            let fixture = try RuleFixture(root, pathGuard)
            let folder = try root.folder("Library/Caches/Fixture/build.cache", modified: fixture.stale)
            let plan = try fixture.plan([fixture.scanned(folder, rule: fixture.rule())])
            return Scenario(
                plan: plan, skipped: [.modifiedSinceScan], kept: [folder],
                change: {
                    try FileManager.default.removeItem(at: folder)
                    try root.folder("Library/Caches/Fixture/build.cache", modified: fixture.now)
                })
        },
    ]

    /// Another file of the same kind and size at the same path is a replaced one (D-132).
    private static let personalFiles: [Case] = PersonalFilesCase.all.map { tool in
        Case(name: "\(tool.name): a file replaced between scan and run") { root, pathGuard in
            let (subTool, listed, _) = try tool.make(root)
            let items = await items(
                from: subTool, context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()))
            let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
            #expect(plan.items.map(\.identity) == [FileIdentity.read(listed)])
            return Scenario(
                plan: plan, skipped: [.replaced], kept: [listed],
                change: {
                    try FileManager.default.removeItem(at: listed)
                    try root.file("Downloads/Installer.dmg", size: 1 << 20)
                })
        }
    }

    /// A rule's file whose modification date moved by `offset`, with its kind and size unchanged.
    private static func ruleDate(_ offset: Double) -> @Sendable (FixtureRoot, PathGuard) throws -> Scenario {
        { root, pathGuard in
            let fixture = try RuleFixture(root, pathGuard)
            let file = try root.file("Library/Caches/Fixture/old.cache", size: 4096, modified: fixture.stale)
            let item = try fixture.scanned(file, rule: fixture.rule())
            return Scenario(
                plan: try fixture.plan([item]), skipped: [.modifiedSinceScan], kept: [file],
                change: {
                    try FileManager.default.setAttributes(
                        [.modificationDate: fixture.stale.addingTimeInterval(offset)], ofItemAtPath: file.path)
                    #expect(item.snapshot == ItemSnapshot.read(file))
                })
        }
    }

    @Test(arguments: changedSinceTheScan)
    func anItemChangedSinceTheScanIsSkippedAndLoggedSAF008(_ scenario: Case) async throws {
        let scenario = try await scenario.make(root, pathGuard)
        try scenario.change()

        try expectOutcomes(scenario, try await run(scenario))
    }

    static let appStartingAfterTheScan: [Case] = [
        Case(name: "A rule's item next to one that needs no app") { root, pathGuard in
            let fixture = try RuleFixture(root, pathGuard)
            let folder = try root.folder("Library/Caches/Fixture/build.cache", modified: fixture.stale)
            let free = try root.folder("Library/Caches/Fixture/free.cache", modified: fixture.stale)
            let plan = try fixture.plan([
                fixture.scanned(folder, rule: fixture.rule(apps: ["com.example.Fixture"])),
                fixture.scanned(free, rule: fixture.rule()),
            ])
            // Bundle IDs compare without case.
            return Scenario(
                plan: plan, skipped: [.appRunning, nil], kept: [folder], gone: [free], running: ["com.example.fixture"])
        },
        Case(name: "Caches & Logs: the cache of an app") { root, pathGuard in
            let cache = try root.staleFolder("Library/Caches/com.example.Notes")
            let plan = try await Rig.cachesAndLogs(root).plan(pathGuard)
            return Scenario(
                plan: plan, skipped: [.appRunning], kept: [cache.appending(path: "data.db")],
                running: ["com.example.notes"])
        },
        Case(name: "Caches & Logs: the cache named after an app") { root, pathGuard in
            let cache = try root.staleFolder("Library/Caches/Firefox")
            // The cache starts unselected (CAC-009), and the user selects it in review.
            let plan = try await Rig.cachesAndLogs(root).plan(pathGuard)
            return Scenario(
                plan: plan, skipped: [.appRunning], kept: [cache.appending(path: "data.db")],
                running: ["org.mozilla.firefox"])
        },
        Case(name: "Developer Junk: a DerivedData project, Xcode starts") { root, pathGuard in
            let folder = try root.derivedDataProject(
                "Old-abcdefghijklmnopqrstuvwxyzab", workspace: nil, modified: .longAgo)
            let plan = try await Rig.developerJunk(root).plan(pathGuard)
            return Scenario(plan: plan, skipped: [.appRunning], kept: [folder], running: ["com.apple.dt.Xcode"])
        },
        Case(name: "Developer Junk: a device support version, Xcode starts") { root, pathGuard in
            let old = try root.deviceSupport("iOS", "16.4 (20E247)")
            try root.deviceSupport("iOS", "17.2 (21C62)")
            let plan = try await Rig.developerJunk(root).plan(pathGuard, selectedOnly: true)
            return Scenario(plan: plan, skipped: [.appRunning], kept: [old], running: ["com.apple.dt.Xcode"])
        },
        Case(name: "Developer Junk: the simulator caches, the simulator starts") { root, pathGuard in
            let cache = try root.file("Library/Developer/CoreSimulator/Caches/dyld/21C62/cache", size: 4096)
            let plan = try await Rig.developerJunk(root).plan(pathGuard)
            return Scenario(plan: plan, skipped: [.appRunning], kept: [cache], running: ["com.apple.iphonesimulator"])
        },
        Case(name: "Developer Junk: an Xcode archive, Xcode starts") { root, pathGuard in
            let archive = try root.xcarchive(day: "2026-11-10", name: "App")
            let plan = try await Rig.developerJunk(root).plan(pathGuard)
            return Scenario(plan: plan, skipped: [.appRunning], kept: [archive], running: ["com.apple.dt.Xcode"])
        },
        Case(name: "A tool command whose app starts") { root, pathGuard in
            let tool = try root.tool("tools/reporter", .reportsInvocation)
            let command = try ToolCommand(
                executable: tool.path, arguments: [], environment: ["PATH": "/usr/bin:/bin"])
            let rule = try CleanupRule(
                id: "fixture-tool", name: "Fixture tool", description: "Fixture",
                category: ItemCategory(id: "fixture", name: "Fixture tools"), detection: .executable(tool.path),
                action: .command(command), tier: .rebuildable, selection: .always, explanation: "Fixture command",
                documentation: #require(URL(string: "https://example.test/tool")), apps: ["com.example.app"])
            let item = try rule.scanItem(
                estimatedBytes: 4096, source: FixtureSubTool.id, runningApps: StubRunningApps())
            let plan = try Plan(
                subTool: FixtureSubTool(tier: .rebuildable, method: .tool), items: [item], pathGuard: pathGuard)
            return Scenario(plan: plan, skipped: [.appRunning], running: ["com.example.app"], isTool: true)
        },
    ]

    @Test(arguments: appStartingAfterTheScan)
    func anAppStartingAfterTheScanSkipsItsItemsAndIsLoggedSAF009SAF011(_ scenario: Case) async throws {
        let scenario = try await scenario.make(root, pathGuard)

        try expectOutcomes(scenario, try await run(scenario))
    }

    // MARK: - An app that runs at scan time disables its items (SAF-009, CAC-003)

    /// What a sub-tool lists while an app runs, as a plan would be asked to run it.
    struct DisabledCase: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable (FixtureRoot, PathGuard) async throws -> Plan

        var testDescription: String { name }

        static let all = [
            DisabledCase(name: "Caches & Logs: a cache, its app runs") { root, pathGuard in
                try root.staleFolder("Library/Caches/com.example.Notes")
                return try await Rig.cachesAndLogs(root, running: ["com.example.Notes"]).plan(pathGuard)
            },
            DisabledCase(name: "Developer Junk: a project, Xcode runs") { root, pathGuard in
                try root.derivedDataProject("Old-abcdefghijklmnopqrstuvwxyzab", workspace: nil, modified: .longAgo)
                return try await Rig.developerJunk(root, running: ["com.apple.dt.Xcode"]).plan(pathGuard)
            },
            DisabledCase(name: "A rule's item, its app runs") { root, pathGuard in
                let fixture = try RuleFixture(root, pathGuard)
                let folder = try root.folder("Library/Caches/Fixture/build.cache", modified: fixture.stale)
                let rule = try fixture.rule(apps: ["com.example.Fixture"])
                // Bundle IDs compare without case, as a folder named after one may differ in case from the app.
                let busy = try fixture.scanned(folder, rule: rule, running: ["COM.EXAMPLE.fixture"])
                #expect(busy.selection == .appIsRunning(nil) && busy.apps == ["com.example.Fixture"])
                #expect(busy.selection.disabledReason.map { String(localized: $0) } == "App is running")
                return try fixture.plan([busy])
            },
        ]
    }

    @Test(arguments: DisabledCase.all)
    func aDisabledItemCannotBePlannedWhileItsAppRunsSAF009CAC003(_ disabled: DisabledCase) async throws {
        await #expect(throws: PlanError.self) { try await disabled.make(root, pathGuard) }
    }

    // MARK: - Excluded after the plan (SET-001, SAF-008, D-150)

    /// A folder excluded after the plan was made is skipped when the run re-validates it, and an exclusion of another
    /// folder changes nothing.
    static let excludedAfterThePlan: [Case] =
        pipelineExclusions + ToolCommandTests.ToolCase.all.flatMap(\.exclusionCases)

    private static let pipelineExclusions: [Case] = [
        Case(name: "A Trash item of a folder") { root, pathGuard in
            let beach = try root.file("Pictures/Trip/beach.jpg", size: 10_000)
            let trip = beach.deletingLastPathComponent()
            let item = try root.planned(trip, tier: .yourData, method: .trash)
            return Scenario(
                plan: try Plan(tool: .largeFiles, allowedRoots: [root.url], items: [item], pathGuard: pathGuard),
                kept: [beach], excluded: trip,
                verify: { _ in #expect(!FileManager.default.fileExists(atPath: root.trashFolder.path + "/Trip")) })
        },
        Case(name: "Developer Junk: a node_modules, its project folder") { root, pathGuard in
            let project = try root.nodeProject("Developer/app", edited: .longAgo)
            return Scenario(
                plan: try await Rig.nodeModules(root).plan(pathGuard),
                kept: [project.appending(path: "node_modules")], excluded: project)
        },
    ]

    @Test(arguments: excludedAfterThePlan)
    func aFolderTheUserExcludedAfterThePlanIsSkippedSET001SAF008(_ scenario: Case) async throws {
        let scenario = try await scenario.make(root, pathGuard)
        let excluded = try #require(scenario.excluded)
        let excluding = PathGuard(configuration: root.pathGuardConfiguration(userExclusions: [excluded]))

        let report = try await run(scenario, using: excluding)

        #expect(report.outcomes.map(\.result) == [.skipped(.userExclusion(excluded.path))])
        #expect(try results().map(\.detail) == ["userExclusion: \(excluded.path)"])
        #expect(scenario.kept.allSatisfy(exists))
        #expect(!root.aFakeToolRan)
        try scenario.verify(report)

        // A folder that has nothing to do with the item changes nothing: the same plan runs.
        let other = PathGuard(
            configuration: root.pathGuardConfiguration(userExclusions: [try root.url("Unrelated/Folder")]))
        #expect(try await run(scenario, using: other).outcomes.map(\.result.isDone) == [true])
        #expect(root.aFakeToolRan == scenario.isTool)
    }
}
