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

        // Stopping the stalled scan puts back its previous state and leaves the others as they were.
        stalledScan?.cancel()
        await stalledScan?.value
        #expect(model.state(of: stalled.id) == .notScanned)
        #expect(model.state(of: healthy.id) == .scanned(succeeded))
    }

    @Test func aPlannedSubToolCannotScan() {
        let planned = ToolRegistry.standard.subTools.filter { $0.info.availability != .available }
        let model = FileCleanupModel(subTools: planned, context: context)

        #expect(planned.allSatisfy { !model.canScan($0) && model.scan($0) == nil })
        #expect(!model.canScanAll)
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
}

/// A sub-tool whose scan reports `events` and finishes.
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
