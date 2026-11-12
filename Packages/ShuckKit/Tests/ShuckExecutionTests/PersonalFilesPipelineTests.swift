import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// Large Files' and Old Files' items go through the whole safety pipeline: scan, plan, Trash, log (LRG-004, OLD-004,
/// FCL-003). The two sub-tools differ only in what they list, so one set of tests runs for both.
struct PersonalFilesPipelineTests {
    /// A sub-tool, the file it lists and a file next to it that it leaves alone.
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let tool: ToolID
        /// Creates the fixtures in `root` and returns the sub-tool, the file it lists and the file it leaves alone.
        let make: @Sendable (FixtureRoot) throws -> (subTool: any SubTool, listed: URL, other: URL)

        var testDescription: String { name }

        static let largeFiles = Case(name: "Large Files (LRG-004)", tool: .largeFiles) { root in
            let large = try root.file("Downloads/Installer.dmg", size: 1 << 20)
            let small = try root.file("Downloads/notes.txt", size: 10)
            return (LargeFiles(minimumSize: 1 << 20), large, small)
        }

        static let oldFiles = Case(name: "Old Files (OLD-004)", tool: .oldFiles) { root in
            let yearsAgo = Date.now.addingTimeInterval(-2 * 365 * 86_400)
            let old = try root.file("Downloads/Installer.dmg", size: 1 << 20, modified: yearsAgo)
            let recent = try root.file("Downloads/Recent.dmg", size: 1 << 20)
            // Every fixture file was added just now (D-140).
            let subTool = OldFiles(minimumSize: 1 << 20, lastUsedDate: { _ in nil }, addedDate: { _ in nil })
            return (subTool, old, recent)
        }
    }

    static let cases = [Case.largeFiles, Case.oldFiles]

    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    /// The files keep the modification dates they were written with, to the nanosecond, so this also checks that the
    /// scan and the run read the date at the same precision (D-132).
    @Test(arguments: cases)
    func itemsAreMovedToTheTrashAndLoggedForRestoreLRG004OLD004(_ tool: Case) async throws {
        let (subTool, listed, other) = try tool.make(root)

        let items = await items(
            from: subTool, context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()))
        #expect(items.compactMap { $0.url?.lastPathComponent } == [listed.lastPathComponent])

        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.allSatisfy { if case .done = $0.result { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: listed.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.tool) == [tool.tool])
        #expect(results.allSatisfy { $0.status == .ok && $0.trashedPath != nil })
    }

    @Test(arguments: cases)
    func aFileReplacedBetweenScanAndRunIsNotTrashedSAF008(_ tool: Case) async throws {
        let (subTool, listed, _) = try tool.make(root)
        let items = await items(
            from: subTool, context: ScanContext(home: root.url, protection: root.pathGuardConfiguration()))
        let plan = try Plan(subTool: subTool, items: items, pathGuard: pathGuard)
        #expect(plan.items.map(\.identity) == [FileIdentity.read(listed)])

        // The installer is downloaded again: another file of the same kind and size at the same path.
        try FileManager.default.removeItem(at: listed)
        try root.file("Downloads/Installer.dmg", size: 1 << 20)
        let report = try await PlanExecutor(root: root, pathGuard: pathGuard).run(plan)

        #expect(report.outcomes.map(\.result) == [.skipped(.replaced)])
        #expect(FileManager.default.fileExists(atPath: listed.path))
        let results = try HistoryLog.read(folder: root.historyFolder).records.filter { $0.phase == .result }
        #expect(results.map(\.status) == [.skipped])
        #expect(results.map(\.detail) == ["replaced"])
    }
}
