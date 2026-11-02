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
        /// The allocated size of everything found, each file counted once, in bytes (SAF-013, FCL-007).
        let reclaimableBytes: Int64
        /// Folders macOS did not let the scan read (SAF-012).
        let notAccessibleCount: Int
        /// Folders the scan could not read for another reason, such as a disk error (SAF-011).
        let unreadableCount: Int
    }

    /// What the landing page shows about every finished scan together (FCL-007).
    nonisolated struct CombinedTotal: Equatable {
        /// The allocated size of everything found, each file counted once, in bytes (SAF-013).
        let reclaimableBytes: Int64
        let scannedCount: Int
        /// How many sub-tools can scan now. Planned ones are left out.
        let availableCount: Int
    }

    let subTools: [any SubTool]
    /// The list each available personal-files sub-tool shows (FCL-012).
    let results: [ToolID: PersonalFilesResults]
    /// The files the personal-files sub-tools list, from their shared scan (FCL-006).
    private(set) var personalFiles = PersonalFilesState()
    private let context: ScanContext
    private let personalFilesScan: PersonalFilesScan
    /// Moves a plan's items to the Trash, or `nil` in tests and previews, which then cannot move anything.
    private let runPlan: TrashReview.RunPlan?
    private var states: [ToolID: ScanState] = [:]

    /// Starts a personal-files scan that looks up last-opened dates with the reader, if there is one (OLD-002). Tests
    /// pass made-up events.
    typealias PersonalFilesScan = @Sendable (ScanContext, LastOpenedReader?) -> AsyncStream<PersonalFilesEvent>

    /// - Parameter runPlan: The app passes ``AppEnvironment/run(_:)``.
    init(
        subTools: [any SubTool], context: ScanContext,
        personalFilesScan: @escaping PersonalFilesScan = { PersonalFilesScanner(context: $0, lastOpened: $1).scan() },
        runPlan: TrashReview.RunPlan? = nil
    ) {
        self.subTools = subTools
        self.context = context
        self.runPlan = runPlan
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

    /// The items `subTool` acts on for the rows at `urls`, in that order. Read-only rows and rows the sub-tool no longer
    /// lists are left out (FCL-011).
    func scanItems(_ subTool: any PersonalFilesSubTool, urls: [URL]) -> [ScanItem] {
        urls.compactMap { personalFiles.items[$0] }.compactMap(subTool.scanItem(for:))
    }

    /// Whether the model can move items to the Trash. Pages leave the action out when it cannot.
    var canMoveToTrash: Bool { runPlan != nil }

    /// A review of moving the rows at `urls` to the Trash (SAF-002), or `nil` if the model cannot move anything. Every
    /// item passes the path guard now, and again just before it moves (SAF-007, SAF-008). When the run ends, the moved
    /// items leave every list.
    /// - Throws: ``PlanError`` if any item is refused; a plan is all or nothing.
    func reviewMoveToTrash(_ subTool: any PersonalFilesSubTool, urls: [URL]) throws(PlanError) -> TrashReview? {
        guard let runPlan else { return nil }
        let plan = try Plan(
            subTool: subTool, items: scanItems(subTool, urls: urls),
            pathGuard: PathGuard(configuration: context.protection))
        return TrashReview(plan: plan, runPlan: runPlan) { [weak self] report in
            self?.remove(report.trashedURLs)
        }
    }

    /// Removes items that are gone, such as those a run moved to the Trash, from the shared state and from every list,
    /// so they leave Large Files and Old Files together (FCL-006). Each landing-page estimate is updated to match.
    func remove(_ urls: [URL]) {
        personalFiles.remove(urls)
        for (id, list) in results {
            list.remove(urls)
            if case .scanned(let summary) = states[id] {
                states[id] = .scanned(self.summary(of: id, finished: summary.finished))
            }
        }
    }

    /// The reclaimable estimate of every finished scan together, or `nil` before any scan finishes (FCL-007).
    ///
    /// A file that Large Files and Old Files both list counts once, and so does a file several paths lead to. Other
    /// sub-tools never share a location (FCL-005), so their estimates are added as they are.
    var combinedTotal: CombinedTotal? {
        let available = subTools.filter { $0.info.availability == .available }
        var personal = ReclaimableTotal()
        var otherBytes: Int64 = 0
        var scannedCount = 0
        for subTool in available {
            guard case .scanned(let summary) = state(of: subTool.id) else { continue }
            scannedCount += 1
            if results[subTool.id] != nil {
                personal.add(contentsOf: listedFiles(subTool.id))
            } else {
                otherBytes += summary.reclaimableBytes
            }
        }
        guard scannedCount > 0 else { return nil }
        return CombinedTotal(
            reclaimableBytes: personal.bytes + otherBytes, scannedCount: scannedCount, availableCount: available.count)
    }

    /// The files a personal-files sub-tool lists, read-only ones included.
    private func listedFiles(_ id: ToolID) -> [PersonalFile] {
        results[id]?.rows.compactMap { personalFiles.items[$0.id] } ?? []
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

    /// The reclaimable estimate leaves out read-only items (FCL-011) and counts each file once (FCL-007).
    private func summary(of id: ToolID, finished: Date) -> ScanSummary {
        let total = ReclaimableTotal(listedFiles(id))
        return ScanSummary(
            finished: finished, itemCount: total.count, reclaimableBytes: total.bytes,
            notAccessibleCount: personalFiles.notAccessible.count, unreadableCount: personalFiles.unreadable.count)
    }

    /// Runs a scan off the main actor (NFR-PERF-001). Returns `nil` if the task was cancelled.
    @concurrent
    private nonisolated static func summarize(_ subTool: any SubTool, context: ScanContext) async -> ScanSummary? {
        var itemCount = 0
        var reclaimableBytes: Int64 = 0
        var notAccessibleCount = 0
        var unreadableCount = 0
        for await event in subTool.scan(context) {
            switch event {
            case .item(let item):
                itemCount += 1
                reclaimableBytes += item.allocatedSize
            case .notAccessible:
                notAccessibleCount += 1
            case .unreadable:
                unreadableCount += 1
            }
        }
        guard !Task.isCancelled else { return nil }
        return ScanSummary(
            finished: .now, itemCount: itemCount, reclaimableBytes: reclaimableBytes,
            notAccessibleCount: notAccessibleCount, unreadableCount: unreadableCount)
    }
}
