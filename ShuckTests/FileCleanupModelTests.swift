import Foundation
import ShuckKit
import Testing

@testable import Shuck

/// The landing page's scan states: each sub-tool scans on its own (FCL-002, FCL-004).
///
/// The stub sub-tools below never touch the file system: their items are made up, and the model only adds up sizes.
@MainActor
struct FileCleanupModelTests {
    let context = ScanContext(home: URL(filePath: "/StubHome"))

    @Test func aScanSumsItsItemsAndRecordsWhenItFinished() async throws {
        let subTool = StubSubTool("TSA", events: [.item(.stub("a", size: 1_000)), .item(.stub("b", size: 3_000))])
        let model = FileCleanupModel(subTools: [subTool], context: context)

        let before = Date.now
        await model.scan(subTool)?.value

        guard case .scanned(let summary) = model.state(of: subTool.id) else {
            Issue.record("Not scanned: \(model.state(of: subTool.id))")
            return
        }
        #expect(summary.itemCount == 2)
        #expect(summary.reclaimableBytes == 4_000)
        #expect(summary.notAccessibleCount == 0)
        #expect(summary.finished >= before)
    }

    @Test func aStalledAndAFailingScanLeaveAnotherSubToolsScanUnaffectedFCL002() async throws {
        let stalled = StallingSubTool()
        let failing = StubSubTool("TSB", events: [.notAccessible(URL(filePath: "/StubHome/Locked"))])
        let healthy = StubSubTool("TSA", events: [.item(.stub("a", size: 2_000))])
        let model = FileCleanupModel(subTools: [stalled, failing, healthy], context: context)

        let stalledScan = model.scan(stalled)
        await model.scan(failing)?.value
        await model.scan(healthy)?.value

        #expect(model.state(of: stalled.id) == .scanning)
        guard case .scanned(let failed) = model.state(of: failing.id),
            case .scanned(let succeeded) = model.state(of: healthy.id)
        else {
            Issue.record("Scans did not finish")
            return
        }
        #expect(failed.notAccessibleCount == 1)
        #expect(succeeded.reclaimableBytes == 2_000)
        #expect(succeeded.notAccessibleCount == 0)

        // Stopping the stalled scan leaves it stopped and the others as they were.
        stalledScan?.cancel()
        await stalledScan?.value
        #expect(model.state(of: stalled.id) == .stopped)
        #expect(model.state(of: healthy.id) == .scanned(succeeded))
    }

    /// The landing page counts the folders a scan could not read apart from those macOS did not let it read (SAF-011,
    /// SAF-012).
    @Test func foldersAScanCouldNotReadAreCountedSAF011() async throws {
        let subTool = StubSubTool(
            "TSA",
            events: [
                .notAccessible(URL(filePath: "/StubHome/Locked")), .unreadable(URL(filePath: "/StubHome/Broken")),
                .unreadable(URL(filePath: "/StubHome/Gone")),
            ])
        let model = FileCleanupModel(subTools: [subTool], context: context)

        await model.scan(subTool)?.value

        guard case .scanned(let summary) = model.state(of: subTool.id) else {
            Issue.record("Not scanned: \(model.state(of: subTool.id))")
            return
        }
        #expect(summary.notAccessibleCount == 1)
        #expect(summary.unreadableCount == 2)
    }

    @Test func aPlannedSubToolCannotScan() {
        let planned = [PlannedSubTool.stub]
        let model = FileCleanupModel(subTools: planned, context: context)

        #expect(planned.allSatisfy { !model.canScan($0) && model.scan($0) == nil })
        #expect(!model.canScanAll)
    }

    /// Opening a sub-tool's page scans only if it has not scanned yet (D-61).
    @Test func openingAPageScansOnlyTheFirstTime() async {
        let subTool = StubSubTool("TSA", events: [.item(.stub("a", size: 1_000))])
        let model = FileCleanupModel(subTools: [subTool], context: context)

        let first = model.scanIfNotScanned(subTool)
        #expect(first != nil)
        await first?.value
        #expect(model.scanIfNotScanned(subTool) == nil)

        #expect(model.scanIfNotScanned(PlannedSubTool.stub) == nil)
    }

    @Test func aSubToolThatIsScanningCannotStartAgain() {
        let stalled = StallingSubTool()
        let model = FileCleanupModel(subTools: [stalled], context: context)

        let scan = model.scan(stalled)
        #expect(scan != nil)
        #expect(model.scan(stalled) == nil)
        #expect(!model.canScanAll)
        scan?.cancel()
    }

    /// Each sub-tool keeps its own list and selection: removing an item one list shows leaves another list as it was
    /// (FCL-002).
    @Test func eachSubToolListsItsOwnItemsFCL002() async throws {
        let first = StubSubTool("TSA", events: [.item(.stub("a", size: 1_000)), .item(.stub("b", size: 3_000))])
        let second = StubSubTool("TSB", events: [.item(.stub("c", size: 2_000))])
        let model = FileCleanupModel(subTools: [first, second], context: context)
        #expect(model.results(of: first.id)?.isEmpty == true)

        await model.scan(first)?.value
        await model.scan(second)?.value
        let firstList = try #require(model.scanResults[first.id])
        let secondList = try #require(model.scanResults[second.id])
        #expect(firstList.items.compactMap { $0.url?.lastPathComponent } == ["a", "b"])
        #expect(secondList.items.compactMap { $0.url?.lastPathComponent } == ["c"])
        firstList.selection = [.path(URL(filePath: "/StubHome/b"))]
        secondList.selection = [.path(URL(filePath: "/StubHome/c"))]

        // A review acts on the selected rows in the order given, and only on rows the list still has.
        let urls = ["b", "gone", "a"].map { URL(filePath: "/StubHome/\($0)") }
        #expect(model.scanItems(first, urls: urls).compactMap { $0.url?.lastPathComponent } == ["b", "a"])

        model.remove([URL(filePath: "/StubHome/b")])
        #expect(firstList.items.compactMap { $0.url?.lastPathComponent } == ["a"])
        #expect(firstList.selection.isEmpty)
        #expect(secondList.selection == [.path(URL(filePath: "/StubHome/c"))])
        guard case .scanned(let summary) = model.state(of: first.id) else {
            Issue.record("Not scanned: \(model.state(of: first.id))")
            return
        }
        #expect(summary.itemCount == 1)
        #expect(summary.reclaimableBytes == 1_000)
    }

    /// Stop cancels the scan's task and leaves the sub-tool not scanned with an empty list, so it can scan again
    /// (SAF-014).
    @Test func stoppingAScanLeavesItNotScannedSAF014() async throws {
        let stalled = StallingSubTool()
        let other = StubSubTool("TSA", events: [.item(.stub("a", size: 1_000))])
        let model = FileCleanupModel(subTools: [stalled, other], context: context)
        await model.scan(other)?.value

        let scan = model.scan(stalled)
        model.cancelScan(stalled)
        // Stopping a sub-tool that isn't scanning does nothing.
        model.cancelScan(other)
        await scan?.value

        #expect(scan?.isCancelled == true)
        #expect(model.state(of: stalled.id) == .stopped)
        #expect(model.results(of: stalled.id)?.isEmpty == true)
        #expect(model.canScan(stalled))
        // Opening its page again doesn't restart a stopped scan; Scan does.
        #expect(model.scanIfNotScanned(stalled) == nil)
        #expect(model.state(of: stalled.id) == .stopped)
        let again = model.scan(stalled)
        #expect(model.state(of: stalled.id) == .scanning)
        again?.cancel()
        await again?.value
        guard case .scanned = model.state(of: other.id) else {
            Issue.record("Stopping one scan changed another sub-tool: \(model.state(of: other.id))")
            return
        }
    }
}

/// A sub-tool whose scan reports `events` and finishes.
extension PlannedSubTool {
    /// A sub-tool a later milestone builds. Every sub-tool of File Cleanup is available now, so tests make one.
    fileprivate static var stub: PlannedSubTool {
        PlannedSubTool(
            info: ToolInfo(
                id: ToolID(rawValue: "TPL"), name: "Planned", summary: "Comes later.", symbolName: "clock",
                availability: .planned(milestone: "M9")),
            tiers: [.rebuildable])
    }
}

private struct StubSubTool: SubTool {
    let info: ToolInfo
    let tiers: Set<Tier> = [.yourData]
    let events: [ScanEvent]

    init(_ id: String, events: [ScanEvent]) {
        info = ToolInfo(
            id: ToolID(rawValue: id), name: "Stub", summary: "Reports fixed events.", symbolName: "testtube.2",
            availability: .available)
        self.events = events
    }

    func allowedRoots(home: URL) -> [URL] { [] }

    func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// A sub-tool whose scan never finishes until its task is cancelled.
private struct StallingSubTool: SubTool {
    let info = ToolInfo(
        id: ToolID(rawValue: "TSC"), name: "Stalling", summary: "Never finishes.", symbolName: "hourglass",
        availability: .available)
    let tiers: Set<Tier> = [.yourData]

    func allowedRoots(home: URL) -> [URL] { [] }

    func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { _ in }
    }
}

extension ScanItem {
    fileprivate static func stub(_ name: String, size: Int64) -> ScanItem {
        ScanItem(
            url: URL(filePath: "/StubHome/\(name)"), snapshot: ItemSnapshot(kind: .file, allocatedSize: size),
            tier: .yourData, method: .trash, reason: "Stub", source: ToolID(rawValue: "TSA"))
    }
}
