import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// What a tool item reports as removed: the folder it is sized from, measured before and after the command, not the
/// scan's estimate and never the tool's output (DEV-003, DEV-R09, SAF-011, R-07, D-184).
struct MeasuredRemovalTests {
    let root: FixtureRoot
    let pathGuard: PathGuard

    init() throws {
        root = try FixtureRoot()
        pathGuard = PathGuard(configuration: root.pathGuardConfiguration())
    }

    private func scanned() async -> [ScanItem] {
        let context = ScanContext(home: root.url, protection: root.pathGuardConfiguration(), toolRoot: root.url)
        return await items(from: DeveloperJunk(), context: context).filter { $0.method == .tool }
    }

    private func run(_ items: [ScanItem]) async throws -> RunReport {
        let plan = try Plan(subTool: DeveloperJunk(), items: items, pathGuard: pathGuard)
        return await (try PlanExecutor(root: root, pathGuard: pathGuard)).run(plan)
    }

    private func size(_ folder: String) throws -> Int64 {
        try #require(ItemSnapshot.read(try root.url(folder))).allocatedSize
    }

    /// The intent record's and the result record's `bytes` of the run's one item.
    private func recordedBytes() throws -> (intent: Int64?, result: Int64?) {
        let records = try HistoryLog.read(folder: root.historyFolder).records
        return (records.first { $0.phase == .intent }?.bytes, records.first { $0.phase == .result }?.bytes)
    }

    @Test func homebrewReportsWhatItRemovedNotTheWholeCacheDEVR09DEV003SAF011() async throws {
        let cache = "Library/Caches/Homebrew"
        try root.tool("opt/homebrew/bin/brew", .removes(["\(cache)/downloads/old"]))
        try root.file("\(cache)/downloads/current", size: 200_000)
        try root.file("\(cache)/downloads/old", size: 80_000)
        let items = await scanned()
        let estimate = try #require(items.first).allocatedSize
        #expect(estimate == 0, "Homebrew's item has no size before the run (D-194)")
        let before = try size(cache)

        let report = try await run(items)

        let removed = try #require(report.outcomes.first?.removedBytes)
        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(removed == before - (try size(cache)))
        #expect(removed >= 80_000 && removed < before)
        // The intent keeps the estimate; the result has the measured size, which History shows (SAF-005, SAF-006).
        let bytes = try recordedBytes()
        #expect(bytes.intent == estimate && bytes.result == removed)
        #expect(!FileManager.default.fileExists(atPath: try root.url("\(cache)/downloads/old").path))
    }

    @Test func aRunThatRemovesNothingReportsZeroDEVR09DEV003SAF011() async throws {
        let cache = "Library/Caches/Homebrew"
        try root.tool("opt/homebrew/bin/brew", .exits(0))
        try root.file("\(cache)/downloads/current", size: 200_000)
        let items = await scanned()

        let report = try await run(items)

        #expect(report.outcomes.first?.removedBytes == 0)
        let bytes = try recordedBytes()
        #expect(bytes.intent == items.first?.allocatedSize && bytes.result == 0)
    }

    @Test func aToolThatSaysItRemovedMoreIsNotBelievedR07() async throws {
        let cache = "Library/Caches/Homebrew"
        try root.tool("opt/homebrew/bin/brew", .exits(0, output: "Removing: \(cache)/downloads/current... (200 MB)"))
        try root.file("\(cache)/downloads/current", size: 200_000)

        let report = try await run(await scanned())

        #expect(report.outcomes.first?.removedBytes == 0)
    }

    @Test func aFailedRunKeepsTheEstimateAndReportsNoMeasurementDEV003SAF011() async throws {
        let cache = ".npm/_cacache"
        try root.tool("opt/homebrew/bin/npm", .removes(["\(cache)/content-v2/a"], status: 1))
        try root.file("\(cache)/content-v2/a", size: 50_000)
        try root.file("\(cache)/content-v2/b", size: 50_000)
        let items = await scanned()

        let report = try await run(items)

        #expect(report.outcomes.first?.removedBytes == nil)
        if case .failed = report.outcomes[0].result {} else { Issue.record("not a failure") }
        let bytes = try recordedBytes()
        #expect(bytes.intent == items.first?.allocatedSize && bytes.result == bytes.intent)
    }

    @Test(arguments: [("opt/homebrew/bin/npm", ".npm/_cacache"), ("opt/homebrew/bin/pip3", "Library/Caches/pip")])
    func npmAndPipAreMeasuredToo(tool: String, cache: String) async throws {
        try root.tool(tool, .removes(["\(cache)/a"]))
        try root.file("\(cache)/a", size: 60_000)
        try root.file("\(cache)/b", size: 30_000)
        let items = await scanned()
        let before = try size(cache)

        let report = try await run(items)

        let removed = try #require(report.outcomes.first?.removedBytes)
        #expect(removed == before - (try size(cache)) && removed >= 60_000)
        #expect(try recordedBytes().result == removed)
    }

    @Test func unavailableSimulatorsHaveNoFolderToMeasureDEV003() async throws {
        try root.xcrun(.exits(0))
        try root.file("Library/Developer/CoreSimulator/Devices/ABCD/data", size: 4096)

        let report = try await run(await scanned())

        #expect(report.outcomes.map(\.result) == [.done(nil)])
        #expect(report.outcomes.first?.removedBytes == nil)
    }
}
