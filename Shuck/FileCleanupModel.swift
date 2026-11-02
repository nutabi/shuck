import Foundation
import ShuckKit

/// The state of File Cleanup's scans, one per sub-tool, for the landing page (FCL-004).
///
/// Each scan runs in its own task and writes only its own sub-tool's state, so scanning, stalling or failing one never
/// blocks or changes another (FCL-002). The exception is the personal-files sub-tools, Large Files and Old Files: they
/// share one scan and its item state, and each shows its own list of it (FCL-006).
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
    /// The list each available personal-files sub-tool shows (FCL-012).
    let results: [ToolID: PersonalFilesResults]
    /// The files the personal-files sub-tools list, from their shared scan (FCL-006).
    private(set) var personalFiles = PersonalFilesState()
    private let context: ScanContext
    private let personalFilesScan: PersonalFilesScan
    private var states: [ToolID: ScanState] = [:]

    /// Starts a personal-files scan that looks up last-opened dates with the reader, if there is one (OLD-002). Tests
    /// pass made-up events.
    typealias PersonalFilesScan = @Sendable (ScanContext, LastOpenedReader?) -> AsyncStream<PersonalFilesEvent>

    init(
        subTools: [any SubTool], context: ScanContext,
        personalFilesScan: @escaping PersonalFilesScan = { PersonalFilesScanner(context: $0, lastOpened: $1).scan() }
    ) {
        self.subTools = subTools
        self.context = context
        self.personalFilesScan = personalFilesScan
        var results: [ToolID: PersonalFilesResults] = [:]
        for case let subTool as any PersonalFilesSubTool in subTools where subTool.info.availability == .available {
            results[subTool.id] = PersonalFilesResults(
                home: context.home, sortOrder: Self.defaultSortOrder(subTool.id),
                dateColumn: Self.dateColumn(subTool.id), includes: subTool.includes)
        }
        self.results = results
    }

    /// Large Files lists the largest first (LRG-002), Old Files the longest unopened first (OLD-003).
    static func defaultSortOrder(_ id: ToolID) -> [KeyPathComparator<ResultRow>] {
        id == .oldFiles ? [KeyPathComparator(\.sortDate)] : [KeyPathComparator(\.size, order: .reverse)]
    }

    /// Old Files shows when each file was last opened, Large Files when it last changed (OLD-002).
    static func dateColumn(_ id: ToolID) -> DateColumn {
        id == .oldFiles ? .lastOpened : .modified
    }

    private var personalSubTools: [any PersonalFilesSubTool] {
        subTools.compactMap { $0 as? any PersonalFilesSubTool }.filter { results[$0.id] != nil }
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
        if subTool is any PersonalFilesSubTool { return scanPersonalFiles() }
        let id = subTool.id
        let previous = state(of: id)
        states[id] = .scanning
        let context = context
        return Task {
            let summary = await Self.summarize(subTool, context: context)
            states[id] = summary.map(ScanState.scanned) ?? previous
        }
    }

    /// Starts `subTool`'s scan if it has not scanned yet, as when the user opens its page. A finished scan is kept, so
    /// going back to a page shows the same results and selection; the page's Scan button starts a new one.
    @discardableResult
    func scanIfNotScanned(_ subTool: any SubTool) -> Task<Void, Never>? {
        guard state(of: subTool.id) == .notScanned else { return nil }
        return scan(subTool)
    }

    /// Starts the scan of every sub-tool that can scan now. Scanning never acts on anything (FCL-004).
    func scanAll() {
        for subTool in subTools {
            scan(subTool)
        }
    }

    /// Runs the personal-files scan once for every personal-files sub-tool (FCL-006). Rows stream into each list as
    /// the scan finds them (FCL-012). Cancelling the task empties the lists.
    private func scanPersonalFiles() -> Task<Void, Never> {
        let ids = personalSubTools.map(\.id)
        for id in ids {
            states[id] = .scanning
            results[id]?.removeAll()
        }
        personalFiles = PersonalFilesState()
        // Old Files needs last-opened dates. If several sub-tools did, the smallest minimum size would cover them all.
        let reader = personalSubTools.compactMap(\.lastOpenedReader).min { $0.minimumSize < $1.minimumSize }
        let events = personalFilesScan(context, reader)
        return Task {
            // Each event is a batch of files, so the main actor takes a few thousand events for a large home folder.
            for await event in events {
                apply(event)
            }
            let finished = Date.now
            for id in ids {
                if Task.isCancelled {
                    results[id]?.removeAll()
                    states[id] = .notScanned
                } else {
                    states[id] = .scanned(summary(of: id, finished: finished))
                }
            }
        }
    }

    /// Keeps only the files some sub-tool lists, so a home folder of a million files does not stay in memory.
    private func apply(_ event: PersonalFilesEvent) {
        guard case .files(let files) = event else {
            personalFiles.apply(event)
            return
        }
        let subTools = personalSubTools
        let listed = files.filter { file in subTools.contains { $0.includes(file) } }
        guard !listed.isEmpty else { return }
        personalFiles.apply(.files(listed))
        for list in results.values {
            list.apply(.files(listed))
        }
    }

    /// The reclaimable estimate leaves out read-only items (FCL-011).
    private func summary(of id: ToolID, finished: Date) -> ScanSummary {
        let rows = results[id]?.rows.filter { $0.readOnly == nil } ?? []
        return ScanSummary(
            finished: finished, itemCount: rows.count, reclaimableBytes: rows.reduce(0) { $0 + $1.size },
            notAccessibleCount: personalFiles.notAccessible.count)
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
