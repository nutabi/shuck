import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Every item of a sub-tool whose items come from rules needs a rule that accepts it, Trash included (SAF-004,
/// SAF-007, SAF-008, R-03). A plan refuses one without (`PlanRefusalTests`); the executor skips one that reaches it some
/// other way.
struct RuleRequiredTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    @Test func theExecutorSkipsAnItemWithoutARuleForARuleBasedSubToolSAF008() async throws {
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        for scanned in try root.rulelessItems() {
            let item = try root.planned(#require(scanned.url), tier: .yourData, method: .trash)
            let acted = await executor.act(on: item, allowedRoots: [root.url], requiresRule: true)
            #expect(acted.result == .skipped(.ruleChanged))
            #expect(FileManager.default.fileExists(atPath: try #require(item.url).path))
        }
    }

    @Test func personalFilesTrashItemsNeedNoRuleSAF004() async throws {
        #expect(!LargeFiles().requiresRule && !OldFiles().requiresRule)
        let file = try root.file("Downloads/big.bin", size: 10)
        let item = try root.byHand(file, source: .largeFiles)
        let plan = try Plan(subTool: LargeFiles(), items: [item], pathGuard: pathGuard)

        #expect(!plan.requiresRule)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)
        #expect(report.outcomes.allSatisfy { $0.result.isDone })
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
