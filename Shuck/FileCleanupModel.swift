import Foundation
import ShuckKit

/// The state of File Cleanup's scans and results, one per sub-tool, for the landing page (FCL-004) and each sub-tool's
/// page.
///
/// Each scan runs in its own task and writes only its own sub-tool's state, so scanning, stalling or failing one never
/// blocks or changes another (FCL-002). The exception is the personal-files sub-tools, Large Files and Old Files: they
/// share one scan and its item state, and each shows its own list of it (FCL-006). Stop cancels a scan (SAF-014).
@Observable
final class FileCleanupModel {
    /// Where one sub-tool's scan stands.
    nonisolated enum ScanState: Equatable {
        case notScanned
        case scanning
        /// The user stopped the scan. Opening the page again doesn't restart it; Scan does (SAF-014).
        case stopped
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
    let personalFilesResults: [ToolID: PersonalFilesResults]
    /// The list each other available sub-tool shows, such as Developer Junk.
    let scanResults: [ToolID: ScanResults]
    /// The files the personal-files sub-tools list, from their shared scan (FCL-006).
    private(set) var personalFiles = PersonalFilesState()
    private let context: ScanContext
    private let personalFilesScan: PersonalFilesScan
    /// Moves a plan's items to the Trash, or `nil` in tests and previews, which then cannot move anything.
    private let runPlan: RunPlan?
    /// Reads the free space before and after each run, so its summary can show the measured change (SAF-013).
    private let readFreeSpace: ReadFreeSpace
    /// Reads the used space when a summary confirmation opens, for its oversize threshold (SAF-015).
    private let readUsedSpace: ReadUsedSpace
    private var states: [ToolID: ScanState] = [:]
    /// The task of each running scan, so Stop can cancel it. The personal-files sub-tools share one.
    private var scans: [ToolID: Task<Void, Never>] = [:]

    /// Starts a personal-files scan that looks up last-opened dates with the reader, if there is one (OLD-002). Tests
    /// pass made-up events.
    typealias PersonalFilesScan = @Sendable (ScanContext, LastOpenedReader?) -> AsyncStream<PersonalFilesEvent>

    /// - Parameters:
    ///   - runPlan: The app passes ``AppEnvironment/run(_:)``.
    ///   - readFreeSpace: The app passes ``AppEnvironment/availableSpace()``. Tests that leave it out measure nothing.
    ///   - readUsedSpace: The app passes ``AppEnvironment/usedSpace()``. Tests that leave it out have no threshold.
    init(
        subTools: [any SubTool], context: ScanContext,
        personalFilesScan: @escaping PersonalFilesScan = { PersonalFilesScanner(context: $0, lastOpened: $1).scan() },
        runPlan: RunPlan? = nil, readFreeSpace: @escaping ReadFreeSpace = { nil },
        readUsedSpace: @escaping ReadUsedSpace = { nil }
    ) {
        self.subTools = subTools
        self.context = context
        self.runPlan = runPlan
        self.readFreeSpace = readFreeSpace
        self.readUsedSpace = readUsedSpace
        self.personalFilesScan = personalFilesScan
        var personalFilesResults: [ToolID: PersonalFilesResults] = [:]
        var scanResults: [ToolID: ScanResults] = [:]
        for subTool in subTools where subTool.info.availability == .available {
            if let subTool = subTool as? any PersonalFilesSubTool {
                personalFilesResults[subTool.id] = PersonalFilesResults(
                    home: context.home, sortOrder: Self.defaultSortOrder(subTool.id),
                    dateColumn: Self.dateColumn(subTool.id), includes: subTool.includes)
            } else {
                scanResults[subTool.id] = ScanResults()
            }
        }
        self.personalFilesResults = personalFilesResults
        self.scanResults = scanResults
    }

    /// The scanned home folder, shown as `~` in folder paths.
    var home: URL { context.home }

    /// The results of the available sub-tool with `id`, or `nil` for a planned one.
    func results(of id: ToolID) -> (any SubToolResults)? {
        personalFilesResults[id] ?? scanResults[id]
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
        subTools.compactMap { $0 as? any PersonalFilesSubTool }.filter { personalFilesResults[$0.id] != nil }
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

    /// Starts `subTool`'s scan, or returns `nil` if it cannot scan now. Items stream into the sub-tool's list as the
    /// scan finds them (FCL-012). Cancelling the returned task, or ``cancelScan(_:)``, stops the scan and leaves the
    /// sub-tool stopped, with an empty list.
    @discardableResult
    func scan(_ subTool: any SubTool) -> Task<Void, Never>? {
        guard canScan(subTool) else { return nil }
        if subTool is any PersonalFilesSubTool { return scanPersonalFiles() }
        let id = subTool.id
        guard let list = scanResults[id] else { return nil }
        list.removeAll()
        states[id] = .scanning
        let context = context
        let task = Task {
            // Each event is one item. A sub-tool lists few enough of them for the main actor (NFR-PERF-001).
            for await event in await Self.start(subTool, context: context) {
                list.apply(event)
            }
            scans[id] = nil
            if Task.isCancelled {
                list.removeAll()
                states[id] = .stopped
            } else {
                states[id] = .scanned(list.summary(finished: .now))
            }
        }
        scans[id] = task
        return task
    }

    /// Stops `subTool`'s scan, if it is scanning (SAF-014). Scanning never acts on anything, so there is nothing to
    /// undo. For Large Files or Old Files, this stops the scan both share (FCL-006).
    func cancelScan(_ subTool: any SubTool) {
        scans[subTool.id]?.cancel()
    }

    /// Starts `subTool`'s scan if it has not scanned yet, as when the user opens its page. A finished scan is kept, so
    /// going back to a page shows the same results and selection, and a stopped one stays stopped, so a long scan the
    /// user stopped doesn't start again behind their back; the page's Scan button starts a new one.
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
            personalFilesResults[id]?.removeAll()
        }
        personalFiles = PersonalFilesState()
        // Old Files needs last-opened dates. If several sub-tools did, the smallest minimum size would cover them all.
        let reader = personalSubTools.compactMap(\.lastOpenedReader).min { $0.minimumSize < $1.minimumSize }
        let events = personalFilesScan(context, reader)
        let task = Task {
            // Each event is a batch of files, so the main actor takes a few thousand events for a large home folder.
            // Each list builds its rows off the main actor and merges them in (NFR-PERF-001).
            for await event in events {
                await apply(event)
            }
            let finished = Date.now
            for id in ids {
                scans[id] = nil
                if Task.isCancelled {
                    personalFilesResults[id]?.removeAll()
                    states[id] = .stopped
                } else {
                    states[id] = .scanned(summary(of: id, finished: finished))
                }
            }
        }
        for id in ids {
            scans[id] = task
        }
        return task
    }

    /// The items `subTool` acts on for the rows at `urls`, in that order. Read-only rows and rows the sub-tool no longer
    /// lists are left out (FCL-011).
    func scanItems(_ subTool: any SubTool, urls: [URL]) -> [ScanItem] {
        guard let subTool = subTool as? any PersonalFilesSubTool else {
            return scanResults[subTool.id]?.items(at: urls) ?? []
        }
        return urls.compactMap { personalFiles.items[$0] }.compactMap(subTool.scanItem(for:))
    }

    /// Whether the model can run a plan. Pages leave their actions out when it cannot, as in previews.
    var canRun: Bool { runPlan != nil }

    /// The summary confirmation for deleting the selected "Rebuildable" items of `subTool` (SAF-003), or `nil` if the
    /// model cannot run anything. Only that tier is in the plan: "Your data" items need the itemized Trash review
    /// (SAF-002). Every item passes the path guard now, and again just before it is deleted (SAF-007, SAF-008). When
    /// the run ends, the deleted items leave the list.
    /// - Throws: ``PlanError`` if any item is refused; a plan is all or nothing.
    func confirmRebuildable(_ subTool: any SubTool) throws(PlanError) -> SummaryConfirmation? {
        guard let runPlan, let results = scanResults[subTool.id] else { return nil }
        let plan = try Plan(
            subTool: subTool, items: results.selectedItems(in: .rebuildable),
            pathGuard: PathGuard(configuration: context.protection))
        return SummaryConfirmation(
            plan: plan, threshold: OversizeThreshold(usedSpace: readUsedSpace()), runPlan: runPlan,
            readFreeSpace: readFreeSpace
        ) { [weak self] report in
            self?.remove(report.deletedURLs)
            self?.remove(commands: report.cleanedCommands)
        }
    }

    /// A review of moving the rows at `urls` to the Trash (SAF-002), or `nil` if the model cannot run anything. Every
    /// item passes the path guard now, and again just before it moves (SAF-007, SAF-008). The review knows which items
    /// iCloud syncs, so it can warn about them (D-129). When the run ends, the moved items leave every list. Only
    /// "Your data" items are in the plan: a run never mixes tiers, and the others have their own confirmation (D-147).
    /// - Throws: ``PlanError`` if any item is refused; a plan is all or nothing.
    func reviewMoveToTrash(_ subTool: any SubTool, urls: [URL]) throws(PlanError) -> TrashReview? {
        guard let runPlan else { return nil }
        let plan = try Plan(
            subTool: subTool, items: scanItems(subTool, urls: urls).filter { $0.tier == .yourData },
            pathGuard: PathGuard(configuration: context.protection))
        let synced = Set(plan.items.compactMap(\.url).filter { personalFiles.items[$0]?.isSynced == true })
        return TrashReview(plan: plan, synced: synced, runPlan: runPlan, readFreeSpace: readFreeSpace) {
            [weak self] report in
            self?.remove(report.trashedURLs)
        }
    }

    /// Removes items that are gone, such as those a run moved to the Trash, from the shared state and from every list,
    /// so they leave Large Files and Old Files together (FCL-006). Each landing-page estimate is updated to match.
    func remove(_ urls: [URL]) {
        personalFiles.remove(urls)
        for id in subTools.map(\.id) {
            results(of: id)?.remove(urls)
        }
        refreshSummaries()
    }

    /// Removes the items for tool commands that a run has run, from every list that has them (DEV-R03 onwards).
    func remove(commands: [ToolCommand]) {
        for list in scanResults.values {
            list.remove(commands: commands)
        }
        refreshSummaries()
    }

    /// Updates each landing-page estimate to match its list.
    private func refreshSummaries() {
        for id in subTools.map(\.id) {
            if results(of: id) != nil, case .scanned(let summary) = states[id] {
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
            if personalFilesResults[subTool.id] != nil {
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
        personalFilesResults[id]?.rows.compactMap { personalFiles.items[$0.id] } ?? []
    }

    /// Keeps only the files some sub-tool lists, so a home folder of a million files does not stay in memory.
    private func apply(_ event: PersonalFilesEvent) async {
        guard case .files(let files) = event else {
            personalFiles.apply(event)
            return
        }
        let subTools = personalSubTools
        let listed = files.filter { file in subTools.contains { $0.includes(file) } }
        guard !listed.isEmpty else { return }
        personalFiles.apply(.files(listed))
        for list in personalFilesResults.values {
            await list.apply(.files(listed))
        }
    }

    /// Starts a scan off the main actor, in case a sub-tool does some of its work before it returns the stream
    /// (NFR-PERF-001).
    @concurrent
    private nonisolated static func start(_ subTool: any SubTool, context: ScanContext) async -> AsyncStream<ScanEvent>
    {
        subTool.scan(context)
    }

    /// The reclaimable estimate leaves out read-only items (FCL-011) and counts each file once (FCL-007).
    private func summary(of id: ToolID, finished: Date) -> ScanSummary {
        if let list = scanResults[id] { return list.summary(finished: finished) }
        let total = ReclaimableTotal(listedFiles(id))
        return ScanSummary(
            finished: finished, itemCount: total.count, reclaimableBytes: total.bytes,
            notAccessibleCount: personalFiles.notAccessible.count, unreadableCount: personalFiles.unreadable.count)
    }
}
