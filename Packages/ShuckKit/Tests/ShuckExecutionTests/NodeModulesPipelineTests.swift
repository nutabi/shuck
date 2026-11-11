import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// A stale `node_modules` goes through the whole safety pipeline: scan, plan, Delete, log (DEV-R06, DEV-006, SAF-004,
/// SAF-006 to SAF-008).
struct NodeModulesPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let longAgo = Date.now.addingTimeInterval(-40 * 86_400)

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private var subTool: DeveloperJunk {
        DeveloperJunk(projectFolders: [root.url.appending(path: "Developer")])
    }

    private func scanned() async -> [ScanItem] {
        let context = ScanContext(
            home: root.url,
            ownership: OwnershipMap(home: root.url, projectFolders: [root.url.appending(path: "Developer")]),
            protection: root.pathGuardConfiguration(), runningApps: StubRunningApps([]))
        return await items(from: subTool, context: context)
    }

    private func plan(_ items: [ScanItem]) throws -> Plan {
        try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
    }

    @Test func aStaleProjectsNodeModulesIsDeletedAndTheProjectStaysLoggedNotRestorableDEVR06SAF006() async throws {
        let stale = try root.nodeProject("Developer/stale", edited: longAgo)
        let busy = try root.nodeProject("Developer/busy", edited: .now)

        let items = await scanned()
        let selected = items.filter { $0.selection == .selected }
        #expect(items.count == 2 && selected.count == 1)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan(selected))

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(!FileManager.default.fileExists(atPath: stale.appending(path: "node_modules").path))
        // Only `node_modules` goes: the project's own files stay, and so does the other project.
        for kept in ["package.json", "package-lock.json", "src/index.js"] {
            #expect(FileManager.default.fileExists(atPath: stale.appending(path: kept).path))
        }
        #expect(FileManager.default.fileExists(atPath: busy.appending(path: "node_modules/dep/index.js").path))
        let history = try HistoryLog.read(folder: root.historyFolder)
        let results = history.records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.developerJunk])
        #expect(results.allSatisfy { $0.operation == .delete && $0.tier == .rebuildable && $0.status == .ok })
        #expect(history.entries().map(\.restorability) == [.permanent])
    }

    @Test func aNodeModulesChangedAfterTheScanIsSkippedSAF008() async throws {
        let project = try root.nodeProject("Developer/app", edited: longAgo)
        let modules = project.appending(path: "node_modules")
        let plan = try await plan(scanned())
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-60)], ofItemAtPath: modules.path)

        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.modifiedSinceScan)])
        #expect(FileManager.default.fileExists(atPath: modules.path))
    }

    @Test func aProjectFolderTheUserExcludedAfterTheScanIsSkippedSAF008() async throws {
        let project = try root.nodeProject("Developer/app", edited: longAgo)
        let plan = try await plan(scanned())
        let excluding = PathGuard(configuration: root.pathGuardConfiguration(userExclusions: [project]))

        let report = try await PlanExecutor(root: root, pathGuard: excluding).run(plan)

        #expect(report.outcomes.count == 1)
        if case .skipped(.rejected) = report.outcomes[0].result {} else { Issue.record("not rejected by the guard") }
        #expect(FileManager.default.fileExists(atPath: project.appending(path: "node_modules").path))
    }

    @Test func aPlanRefusesANodeModulesOutsideTheProjectFoldersSAF007() async throws {
        let inside = try root.nodeProject("Developer/app", edited: longAgo)
        let outside = try root.nodeProject("Documents/site", edited: longAgo)
        let item = try #require(await scanned().first)
        let target = outside.appending(path: "node_modules")
        let moved = try PlannedItem(
            url: target, tier: .rebuildable, method: .delete, snapshot: #require(item.snapshot),
            modified: ModificationDate.read(at: target), ruleMatch: item.ruleMatch)

        #expect(throws: PlanError.self) {
            try Plan(
                tool: .developerJunk, allowedRoots: self.subTool.allowedRoots(home: self.root.url), items: [moved],
                pathGuard: self.pathGuard)
        }
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: inside.appending(path: "node_modules").path))
    }
}
