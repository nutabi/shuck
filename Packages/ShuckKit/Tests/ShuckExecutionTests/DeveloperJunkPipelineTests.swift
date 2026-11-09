import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Xcode DerivedData items go through the whole safety pipeline: scan, plan, Delete, log (DEV-R01, SAF-004 to SAF-009).
struct DeveloperJunkPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let longAgo = Date.now.addingTimeInterval(-40 * 86_400)
    let hash = "abcdefghijklmnopqrstuvwxyzab"

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

    @Test func selectedProjectsAreDeletedForGoodAndLoggedNotRestorableSAF004SAF006() async throws {
        let stale = try root.derivedDataProject("Old-\(hash)", workspace: nil, modified: longAgo)
        let gone = try root.derivedDataProject("Gone-\(hash)", workspace: root.url("Projects/Gone"), modified: .now)
        let recent = try root.derivedDataProject(
            "Recent-\(hash)", workspace: root.folder("Projects/Live"), modified: .now)

        let items = await scanned()
        let selected = items.filter { $0.selection == .selected }
        #expect(selected.count == 2)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan(selected))

        #expect(report.outcomes.map(\.result) == [.done(nil), .done(nil)])
        #expect(
            !FileManager.default.fileExists(atPath: stale.path) && !FileManager.default.fileExists(atPath: gone.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        // DerivedData itself stays, as Xcode expects it.
        #expect(FileManager.default.fileExists(atPath: stale.deletingLastPathComponent().path))
        let history = try HistoryLog.read(folder: root.historyFolder)
        let results = history.records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.developerJunk, .developerJunk])
        #expect(results.allSatisfy { $0.operation == .delete && $0.tier == .rebuildable && $0.status == .ok })
        #expect(history.entries().map(\.restorability) == [.permanent, .permanent])
    }

    @Test func aProjectBuiltAgainAfterTheScanIsSkippedSAF008() async throws {
        let folder = try root.derivedDataProject("Old-\(hash)", workspace: nil, modified: longAgo)
        let plan = try await plan(scanned())
        try FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: folder.path)

        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.modifiedSinceScan)])
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func xcodeStartingAfterTheScanSkipsTheProjectSAF009() async throws {
        let folder = try root.derivedDataProject("Old-\(hash)", workspace: nil, modified: longAgo)
        let plan = try await plan(scanned())

        let report = await
            (try PlanExecutor(root: root, pathGuard: pathGuard, runningApps: StubRunningApps(["com.apple.dt.Xcode"])))
            .run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.appRunning)])
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func aDisabledProjectCannotBePlannedWhileXcodeRunsSAF009() async throws {
        try root.derivedDataProject("Old-\(hash)", workspace: nil, modified: longAgo)
        let items = await scanned(running: ["com.apple.dt.Xcode"])
        #expect(throws: PlanError.self) { try self.plan(items) }
    }

    @Test func oldDeviceSupportVersionsAreDeletedAndTheNewestStaysDEVR02() async throws {
        let old = try root.deviceSupport("iOS", "16.4 (20E247)")
        let newest = try root.deviceSupport("iOS", "17.2 (21C62) arm64e")

        let selected = await scanned().filter { $0.selection == .selected }
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan(selected))

        #expect(selected.count == 1)
        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: newest.path))
        // The platform's folder stays, as Xcode expects it.
        #expect(FileManager.default.fileExists(atPath: newest.deletingLastPathComponent().path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.developerJunk])
        #expect(results.allSatisfy { $0.operation == .delete && $0.tier == .rebuildable && $0.status == .ok })
    }

    @Test func xcodeStartingAfterTheScanSkipsADeviceSupportVersionSAF009() async throws {
        let old = try root.deviceSupport("iOS", "16.4 (20E247)")
        try root.deviceSupport("iOS", "17.2 (21C62)")
        let plan = try await plan(scanned().filter { $0.selection == .selected })

        let report = await
            (try PlanExecutor(root: root, pathGuard: pathGuard, runningApps: StubRunningApps(["com.apple.dt.Xcode"])))
            .run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.appRunning)])
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    @Test func simulatorCachesAreDeletedAndTheDevicesBesideThemStayDEVR04DEV007() async throws {
        let cache = try root.file("Library/Developer/CoreSimulator/Caches/dyld/21C62/cache", size: 4096)
        let device = try root.file("Library/Developer/CoreSimulator/Devices/ABCD-1234/device.plist", size: 10)

        let selected = await scanned().filter { $0.selection == .selected }
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan(selected))

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(FileManager.default.fileExists(atPath: device.path))
        // The Caches folder itself stays, as the simulators expect it.
        #expect(
            FileManager.default.fileExists(
                atPath: root.url.appending(path: "Library/Developer/CoreSimulator/Caches").path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [.developerJunk])
        #expect(results.allSatisfy { $0.operation == .delete && $0.tier == .rebuildable && $0.status == .ok })
    }

    @Test func aSimulatorStartingAfterTheScanSkipsTheCacheSAF009() async throws {
        let cache = try root.file("Library/Developer/CoreSimulator/Caches/dyld/21C62/cache", size: 4096)
        let plan = try await plan(scanned())

        let report = await
            (try PlanExecutor(
                root: root, pathGuard: pathGuard, runningApps: StubRunningApps(["com.apple.iphonesimulator"])))
            .run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.appRunning)])
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func aSimulatorDeviceCannotBePlannedByAnySubToolItemDEV007() throws {
        let device = try root.file("Library/Developer/CoreSimulator/Devices/ABCD-1234/device.plist", size: 10)
        let folder = device.deletingLastPathComponent()
        let item = ScanItem(
            url: folder, snapshot: try #require(ItemSnapshot.read(folder)), tier: .rebuildable, method: .delete,
            reason: "Not a rule's target", source: .developerJunk, selection: .selected)

        #expect(throws: PlanError.self) { try self.plan([item]) }
        #expect(FileManager.default.fileExists(atPath: device.path))
    }

    @Test func archivesAreOutsideTheSubToolsRootsEvenNextToDeviceSupportSAF007() throws {
        let archive = try root.file("Library/Developer/Xcode/Archives/App.xcarchive/Info.plist", size: 10)
        try root.deviceSupport("iOS", "16.4 (20E247)")
        let folder = archive.deletingLastPathComponent()
        let item = ScanItem(
            url: folder, snapshot: try #require(ItemSnapshot.read(folder)), tier: .rebuildable, method: .delete,
            reason: "Not a rule's target", source: .developerJunk, selection: .selected)

        #expect(throws: PlanError.self) { try self.plan([item]) }
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}
