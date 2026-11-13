import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// An Xcode archive goes through the whole safety pipeline: scan, plan, Trash, log, Restore (DEV-R05, SAF-002,
/// SAF-004, SAF-008, HIS-003).
struct XcodeArchivesPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func scanned(running: Set<String> = []) async -> [ScanItem] {
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running))
        return await items(from: DeveloperJunk(), context: context)
    }

    private func plan(_ items: [ScanItem]) throws -> Plan {
        try Plan(subTool: DeveloperJunk(), items: items, pathGuard: pathGuard)
    }

    @Test func anArchiveIsTrashedLoggedAsRestorableAndRestoredDEVR05HIS003() async throws {
        let archive = try root.xcarchive(day: "2026-11-10", name: "App")
        let kept = try root.xcarchive(day: "2026-11-11", name: "Kept")

        let item = try #require(await scanned().first { $0.url?.path == archive.path })
        #expect(item.selection == .unselected)
        // The user chooses it by hand; a run of the chosen item moves only it.
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan([item]))

        #expect(report.outcomes.count == 1)
        #expect(report.outcomes.allSatisfy { if case .done = $0.result { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(FileManager.default.fileExists(atPath: kept.path))
        let history = try HistoryLog.read(folder: root.historyFolder)
        let results = history.records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.developerJunk])
        #expect(results.allSatisfy { $0.operation == .trash && $0.tier == .yourData && $0.status == .ok })
        let trashed = try #require(
            history.entries().compactMap { entry -> TrashedItem? in
                guard case .restorable(let item) = entry.restorability else { return nil }
                return item
            }.first)
        #expect(FileManager.default.fileExists(atPath: trashed.trashedURL.path))

        let restore = RestoreExecutor(
            pathGuard: pathGuard, log: try HistoryLog(folder: root.historyFolder),
            trash: FakeTrash(folder: root.trashFolder),
            toolRunner: ToolRunner(executableRoots: [root.url]))
        let restored = await restore.run([RestoreRequest(item: trashed)])

        #expect(restored.outcomes.count == 1)
        #expect(restored.outcomes.allSatisfy { if case .done = $0.result { true } else { false } })
        #expect(FileManager.default.fileExists(atPath: archive.appending(path: "Info.plist").path))
    }

    @Test func aPlanRefusesToDeleteAnArchiveSAF004() async throws {
        let archive = try root.xcarchive(day: "2026-11-10", name: "App")
        let item = try #require(await scanned().first)
        // The same item with Delete as its method, as a caller that bypasses the review could ask for.
        let deleting = try PlannedItem(
            url: archive, tier: .yourData, method: .delete, snapshot: #require(item.snapshot), modified: item.modified,
            ruleMatch: item.ruleMatch)

        let error = #expect(throws: PlanError.self) {
            try Plan(
                tool: .developerJunk, allowedRoots: DeveloperJunk().allowedRoots(home: self.root.url),
                items: [deleting], pathGuard: self.pathGuard)
        }
        #expect(error == PlanError.methodNotAllowed(archive.path, tier: .yourData, method: .delete))
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func anArchiveChangedAfterTheScanIsNotTrashedSAF008() async throws {
        let archive = try root.xcarchive(day: "2026-11-10", name: "App")
        let plan = try await plan(scanned())
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-3_600)], ofItemAtPath: archive.path)

        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.modifiedSinceScan)])
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func xcodeStartingAfterTheScanSkipsTheArchiveSAF009() async throws {
        let archive = try root.xcarchive(day: "2026-11-10", name: "App")
        let plan = try await plan(scanned())

        let report = await
            (try PlanExecutor(root: root, pathGuard: pathGuard, runningApps: StubRunningApps(["com.apple.dt.Xcode"])))
            .run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.appRunning)])
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}
