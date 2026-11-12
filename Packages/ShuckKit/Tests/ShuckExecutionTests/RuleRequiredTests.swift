import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Every item of a sub-tool whose items come from rules needs a rule that accepts it, Trash included (SAF-004,
/// SAF-007, SAF-008, R-03).
struct RuleRequiredTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func scanItem(_ url: URL, source: ToolID, ruleMatch: RuleMatch? = nil) throws -> ScanItem {
        ScanItem(
            url: url, snapshot: try #require(ItemSnapshot.read(url)), tier: .yourData, method: .trash,
            reason: "By hand", source: source, modified: ModificationDate.read(at: url), ruleMatch: ruleMatch)
    }

    /// The three items of R-03's probe: a folder in a project folder, a whole project and an archive's date folder,
    /// each a "Your data" Trash item with no rule.
    private func ruleless() throws -> [ScanItem] {
        try root.folder("Developer")
        try root.folder("Developer/thesis")
        try root.folder("Developer/app")
        try root.folder("Library/Developer/Xcode/Archives")
        try root.folder("Library/Developer/Xcode/Archives/2026-11-10")
        return try ["Developer/thesis", "Developer/app", "Library/Developer/Xcode/Archives/2026-11-10"].map {
            try scanItem(root.url($0), source: .developerJunk)
        }
    }

    @Test func aPlanRefusesAnItemWithoutARuleForARuleBasedSubToolSAF008() throws {
        let items = try ruleless()
        let junk = DeveloperJunk(projectFolders: [try root.url("Developer")])
        #expect(junk.requiresRule && CachesAndLogs().requiresRule)
        for item in items {
            let error = #expect(throws: PlanError.self) {
                try Plan(subTool: junk, items: [item], pathGuard: self.pathGuard)
            }
            #expect(error == .ruleRequired(item.target.description))
        }
    }

    @Test func anArchivesRuleRefusesADateFolderSAF008() async throws {
        let archive = try root.xcarchive(day: "2026-11-10", name: "App")
        let dateFolder = archive.deletingLastPathComponent()
        let context = ScanContext(
            home: root.url, protection: root.pathGuardConfiguration(), runningApps: StubRunningApps([]))
        let scanned = await items(from: DeveloperJunk(), context: context)
        let match = try #require(scanned.first?.ruleMatch)
        let item = try scanItem(dateFolder, source: .developerJunk, ruleMatch: match)

        let error = #expect(throws: PlanError.self) {
            try Plan(subTool: DeveloperJunk(), items: [item], pathGuard: self.pathGuard)
        }
        #expect(error == .ruleMismatch(dateFolder.path))
    }

    @Test func theExecutorSkipsAnItemWithoutARuleForARuleBasedSubToolSAF008() async throws {
        let executor = try PlanExecutor(root: root, pathGuard: pathGuard)
        for scanned in try ruleless() {
            let item = try root.planned(#require(scanned.url), tier: .yourData, method: .trash)
            let acted = await executor.act(on: item, allowedRoots: [root.url], requiresRule: true)
            #expect(acted.result == .skipped(.ruleChanged))
            #expect(FileManager.default.fileExists(atPath: try #require(item.url).path))
        }
    }

    @Test func personalFilesTrashItemsNeedNoRuleSAF004() async throws {
        #expect(!LargeFiles().requiresRule && !OldFiles().requiresRule)
        let file = try root.file("Downloads/big.bin", size: 10)
        let item = try scanItem(file, source: .largeFiles)
        let plan = try Plan(subTool: LargeFiles(), items: [item], pathGuard: pathGuard)

        #expect(!plan.requiresRule)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)
        #expect(report.outcomes.allSatisfy { if case .done = $0.result { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
