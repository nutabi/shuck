import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// A test-only sub-tool registers and runs through the whole safety pipeline: scan, plan, Trash, log (FCL-003).
struct SubToolPipelineTests {
    let root: FixtureRoot
    let pathGuard: PathGuard
    let context: ScanContext

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
        let ownership = OwnershipMap(home: root.url, entries: [.init("Pile", owners: [FixtureSubTool.id])])
        context = ScanContext(home: root.url, ownership: ownership)
    }

    @Test func aTestSubToolScansPlansAndTrashesThroughTheSafetyPipelineFCL003() async throws {
        let wanted = [try root.file("Pile/a.bin", size: 4_000), try root.file("Pile/Deeper/b.bin", size: 8_000)]
        let notOwned = try root.file("Elsewhere/c.bin", size: 4_000)
        let registry = ToolRegistry(tools: [Tool(info: FixtureSubTool().info, subTools: [FixtureSubTool()])])
        let subTool = try #require(registry.subTool(FixtureSubTool.id))

        let items = await items(from: subTool, context: context)
        #expect(Set(items.map(\.url.path)) == Set(wanted.map(\.path)))

        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        let report = try await TrashExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.allSatisfy { if case .trashed = $0.result { true } else { false } })
        #expect(wanted.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: notOwned.path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.count == wanted.count)
        #expect(results.allSatisfy { $0.tool == FixtureSubTool.id && $0.status == .ok })
    }

    @Test func aProtectedFileTheSubToolFindsNeverReachesTheTrashSAF007() async throws {
        let key = try root.file(".ssh/id_ed25519", size: 10)
        let ownership = OwnershipMap(home: root.url, entries: [.init(".ssh", owners: [FixtureSubTool.id])])

        let items = await items(from: FixtureSubTool(), context: ScanContext(home: root.url, ownership: ownership))
        #expect(items.map(\.url.path) == [key.path])
        #expect(throws: PlanError.self) {
            try Plan(subTool: FixtureSubTool(), items: items, pathGuard: pathGuard)
        }
    }
}
