import Foundation
import ShuckKit

/// The state of File Cleanup's scans, one per sub-tool, for the landing page (FCL-004).
///
/// Each scan runs in its own task and writes only its own sub-tool's state, so scanning, stalling or failing one never
/// blocks or changes another (FCL-002).
@Observable
final class FileCleanupModel {
    /// Where one sub-tool's scan stands.
    nonisolated enum ScanState: Equatable {
        case notScanned
        case scanning
        case scanned(ScanSummary)
    }

    /// What the landing page shows about a finished scan.
    nonisolated struct ScanSummary: Equatable {
        let finished: Date
        let itemCount: Int
        /// The allocated size of everything found, in bytes (SAF-013).
        let reclaimableBytes: Int64
        /// Folders the scan could not read (SAF-012).
        let notAccessibleCount: Int
    }

    let subTools: [any SubTool]
    private let context: ScanContext
    private var states: [ToolID: ScanState] = [:]

    init(subTools: [any SubTool], context: ScanContext) {
        self.subTools = subTools
        self.context = context
    }

    func state(of id: ToolID) -> ScanState {
        states[id] ?? .notScanned
    }

    /// Whether `subTool` is built and not scanning already.
    func canScan(_ subTool: any SubTool) -> Bool {
        subTool.info.availability == .available && state(of: subTool.id) != .scanning
    }

    var canScanAll: Bool {
        subTools.contains { canScan($0) }
    }

    /// Starts `subTool`'s scan, or returns `nil` if it cannot scan now. Cancelling the returned task stops the scan
    /// and puts back the state it had before.
    @discardableResult
    func scan(_ subTool: any SubTool) -> Task<Void, Never>? {
        guard canScan(subTool) else { return nil }
        let id = subTool.id
        let previous = state(of: id)
        states[id] = .scanning
        let context = context
        return Task {
            let summary = await Self.summarize(subTool, context: context)
            states[id] = summary.map(ScanState.scanned) ?? previous
        }
    }

    /// Starts the scan of every sub-tool that can scan now. Scanning never acts on anything (FCL-004).
    func scanAll() {
        for subTool in subTools {
            scan(subTool)
        }
    }

    /// Runs a scan off the main actor (NFR-PERF-001). Returns `nil` if the task was cancelled.
    @concurrent
    private nonisolated static func summarize(_ subTool: any SubTool, context: ScanContext) async -> ScanSummary? {
        var itemCount = 0
        var reclaimableBytes: Int64 = 0
        var notAccessibleCount = 0
        for await event in subTool.scan(context) {
            switch event {
            case .item(let item):
                itemCount += 1
                reclaimableBytes += item.allocatedSize
            case .notAccessible:
                notAccessibleCount += 1
            }
        }
        guard !Task.isCancelled else { return nil }
        return ScanSummary(
            finished: .now, itemCount: itemCount, reclaimableBytes: reclaimableBytes,
            notAccessibleCount: notAccessibleCount)
    }
}
