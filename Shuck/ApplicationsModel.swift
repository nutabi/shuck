import Foundation
import ShuckExecution
import ShuckKit

/// What the Applications `Table`'s column headers sort by: an ``AppSortKey`` and a direction (APP-009).
///
/// The order itself comes from ``InstalledApp/precedes(_:by:)``, so every sort breaks a tie the same way.
nonisolated struct AppSortComparator: SortComparator {
    var key: AppSortKey
    var order: SortOrder = .forward

    func compare(_ lhs: InstalledApp, _ rhs: InstalledApp) -> ComparisonResult {
        let (first, second) = order == .forward ? (lhs, rhs) : (rhs, lhs)
        if first.precedes(second, by: key) { return .orderedAscending }
        if second.precedes(first, by: key) { return .orderedDescending }
        return .orderedSame
    }
}

/// The state of the Applications page: the apps a scan found, how to sort and search them, where the scan stands, and
/// the selected app's leftovers (APP-001, APP-002 to APP-005, APP-009).
///
/// Applications is a tool of its own, not a File Cleanup sub-tool (D-186), so it has its own model. Apps stream into the
/// list as the scan finds them. Stop cancels the scan (SAF-014).
///
/// Leftovers are scanned for the selected app alone, once the app scan has finished, as each scan of another app's
/// folders can make macOS ask the user for permission. A blocked app is never scanned: nothing could be done with its
/// leftovers (APP-005).
@Observable
final class ApplicationsModel {
    /// Where the scan stands.
    nonisolated enum ScanState: Equatable {
        case notScanned
        case scanning
        /// The user stopped the scan. Opening the page again doesn't restart it; Scan does (SAF-014).
        case stopped
        case scanned
    }

    /// Starts the scan. The app passes ``AppEnvironment/applications``' scan; tests pass made-up events, so none reads
    /// the real `/Applications` (SAF-016).
    typealias AppScan = @Sendable (ScanContext) -> AsyncStream<AppInventoryEvent>

    /// Finds an app's leftovers. The app passes ``AppEnvironment/appLeftovers``, which also reads every installed app
    /// by name (R-05); tests pass made-up events.
    typealias LeftoverScan = @Sendable (InstalledApp, ScanContext) -> AsyncStream<ScanEvent>

    /// Where the selected app's leftover scan stands.
    nonisolated enum LeftoverState: Equatable {
        /// No scan: no app is selected, the app scan is not done, or the app is blocked.
        case idle
        case scanning
        case scanned
    }

    /// Where the selected app's package-receipt lookup stands (APP-008). `failed` is not `none`: an app that no package
    /// installed has no receipt, while a lookup that could not run says nothing either way.
    nonisolated enum ReceiptState: Equatable {
        /// No lookup: no app is selected, it is blocked, or the page has no reader.
        case idle
        case looking
        case none
        case found([PackageReceipt])
        case failed
    }

    private(set) var state = ScanState.notScanned
    /// The apps the scan found, in the order it found them. Use ``visibleApps`` to show them.
    private(set) var apps: [InstalledApp] = []
    /// Folders macOS did not let the scan read (SAF-012). The page tells that some were missed.
    private(set) var notAccessible: [URL] = []
    /// Folders the scan could not read for another reason, such as a disk error (SAF-011).
    private(set) var unreadable: [URL] = []
    /// What the user typed in the search field. It matches an app's name and its bundle ID (APP-009).
    var searchText = ""
    /// The column headers' sort, name first by default (APP-009).
    var sortOrder = [AppSortComparator(key: .name)]
    private(set) var context: ScanContext
    /// The app whose leftovers the page shows. Choose it with ``select(_:)``.
    private(set) var selection: InstalledApp.ID?
    /// The selected app's leftovers, in the order the scan found them.
    private(set) var leftovers: [ScanItem] = []
    private(set) var leftoverState = LeftoverState.idle
    /// What the package receipts say about the selected app (APP-008).
    private(set) var receipt = ReceiptState.idle
    /// The leftovers the uninstall will move to the Trash, by URL. Each starts as the scan selected it, and the user
    /// changes it with ``setChosen(_:for:)`` (APP-007). A disabled leftover, such as a system-wide one, is never in it.
    private(set) var chosen: Set<URL> = []
    /// Whether an uninstall plan is being built, so a second review cannot start meanwhile.
    private(set) var isPlanning = false
    /// Folders macOS did not let the leftover scan read (SAF-012). The inventory's are in ``notAccessible``.
    private(set) var leftoverNotAccessible: [URL] = []
    /// Folders the leftover scan could not read for another reason (SAF-011).
    private(set) var leftoverUnreadable: [URL] = []
    /// How many times the user's exclusions have changed. A scan that started before a change leaves out what the new
    /// list hides (SET-001).
    private var exclusionRevision = 0
    private let appScan: AppScan
    private let leftoverScan: LeftoverScan
    private let uninstall: Uninstall?
    private var scanTask: Task<Void, Never>?
    private var leftoverTask: Task<Void, Never>?
    private var receiptTask: Task<Void, Never>?
    /// Asks which package installed an app. Without one the page shows no receipt, as in previews and tests of the list
    /// alone; the app passes ``AppEnvironment/receiptReader``.
    private let receiptReader: (any PackageReceiptReader)?
    /// Counts the leftover scans started, so an event from one that was replaced never lands in the new list.
    private var leftoverGeneration = 0

    /// What an uninstall needs beyond the scans: the tool that plans it, the run and the quit request. The app passes
    /// ``AppEnvironment``'s; tests pass stubs, so none moves a file or quits an app (SAF-016).
    nonisolated struct Uninstall: Sendable {
        let applications: Applications
        let runPlan: RunPlan
        let readFreeSpace: ReadFreeSpace
        let quitApp: QuitApp

        init(
            applications: Applications, runPlan: @escaping RunPlan, readFreeSpace: @escaping ReadFreeSpace = { nil },
            quitApp: QuitApp
        ) {
            self.applications = applications
            self.runPlan = runPlan
            self.readFreeSpace = readFreeSpace
            self.quitApp = quitApp
        }
    }

    /// - Parameters:
    ///   - leftoverScan: Without one, an app has no leftovers, for a preview or a test of the list alone.
    ///   - uninstall: Without one, the page offers no uninstall, as in previews and tests of the list alone.
    ///   - receiptReader: Without one, the page looks up no package receipt.
    init(
        context: ScanContext, leftoverScan: @escaping LeftoverScan = { _, _ in AsyncStream { $0.finish() } },
        uninstall: Uninstall? = nil, receiptReader: (any PackageReceiptReader)? = nil, appScan: @escaping AppScan
    ) {
        self.context = context
        self.leftoverScan = leftoverScan
        self.uninstall = uninstall
        self.receiptReader = receiptReader
        self.appScan = appScan
    }

    /// The selected app, if it is still listed.
    var selectedApp: InstalledApp? {
        selection.flatMap { id in apps.first { $0.id == id } }
    }

    /// The apps the page lists: the ones that match the search, in the sort order.
    var visibleApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? apps : apps.filter { Self.matches($0, query) }
        return matches.sorted(using: sortOrder)
    }

    /// Whether `query` is part of the app's name or bundle ID, ignoring case and diacritics (APP-009).
    private static func matches(_ app: InstalledApp, _ query: String) -> Bool {
        app.name.localizedStandardContains(query) || app.bundleID?.localizedStandardContains(query) == true
    }

    var canScan: Bool { state != .scanning }

    /// Starts a scan, or returns `nil` if one is running. Apps stream into ``apps`` as the scan finds them. Cancelling
    /// the returned task, or ``cancelScan()``, stops the scan and leaves the list empty (SAF-014).
    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard canScan else { return nil }
        apps = []
        notAccessible = []
        unreadable = []
        select(nil)
        state = .scanning
        let (context, revision, appScan) = (context, exclusionRevision, appScan)
        let task = Task {
            for await event in await Self.start(appScan, context: context) {
                switch event {
                case .app(let app):
                    // The scan keeps the exclusions it started with, so an app they hide now is left out.
                    if revision != exclusionRevision, self.context.hides(app.url) { continue }
                    apps.append(app)
                case .notAccessible(let url): notAccessible.append(url)
                case .unreadable(let url): unreadable.append(url)
                }
            }
            scanTask = nil
            if Task.isCancelled {
                apps = []
                select(nil)
                notAccessible = []
                unreadable = []
                state = .stopped
            } else {
                state = .scanned
                // An app chosen while the scan ran gets its leftovers now. The task ends when they are in.
                await scanLeftovers()?.value
            }
        }
        scanTask = task
        return task
    }

    /// Selects the app whose leftovers the page shows, or none. Changing the selection stops the leftover scan and
    /// empties its list. The new app's scan starts once the app scan is done (APP-002). Returns that scan's task, or
    /// `nil` if none started.
    @discardableResult
    func select(_ id: InstalledApp.ID?) -> Task<Void, Never>? {
        guard id != selection else { return leftoverTask }
        selection = id
        return scanLeftovers()
    }

    /// Replaces the leftover scan with one for the selected app, or with none. Every way a scan ends bumps the
    /// generation: a cancelled one can hand over a partial map of installed apps, and only the generation keeps what it
    /// finds from landing. Only a finished app scan and a removable app start one (APP-005).
    @discardableResult
    private func scanLeftovers() -> Task<Void, Never>? {
        leftoverTask?.cancel()
        leftoverTask = nil
        receiptTask?.cancel()
        receiptTask = nil
        receipt = .idle
        leftoverGeneration += 1
        leftovers = []
        chosen = []
        leftoverNotAccessible = []
        leftoverUnreadable = []
        leftoverState = .idle
        guard state == .scanned, let app = selectedApp, app.removability == .removable else { return nil }
        leftoverState = .scanning
        let generation = leftoverGeneration
        if let receiptReader {
            // The lookup is for the selected app alone, never for each app in the list (APP-008).
            receipt = .looking
            receiptTask = Task {
                let found = await Self.lookUpReceipt(receiptReader, of: app.url)
                guard generation == leftoverGeneration else { return }
                receiptTask = nil
                receipt = found
            }
        }
        let (context, revision, leftoverScan) = (context, exclusionRevision, leftoverScan)
        leftoverTask = Task {
            for await event in await Self.start(leftoverScan, app, context) {
                guard generation == leftoverGeneration else { return }
                switch event {
                case .item(let item):
                    // The scan keeps the exclusions it started with, so an item they hide now is left out.
                    if revision != exclusionRevision, self.context.hides(item) { continue }
                    leftovers.append(item)
                    if item.selection == .selected, let url = item.url { chosen.insert(url) }
                case .notAccessible(let url): leftoverNotAccessible.append(url)
                case .unreadable(let url): leftoverUnreadable.append(url)
                }
            }
            guard generation == leftoverGeneration else { return }
            leftoverTask = nil
            leftoverState = Task.isCancelled ? .idle : .scanned
        }
        return leftoverTask
    }

    /// Chooses or drops a leftover for the uninstall. A disabled one, or one the page does not list, cannot be chosen.
    func setChosen(_ isChosen: Bool, for item: ScanItem) {
        guard let url = item.url, item.selection.isSelectable, leftovers.contains(where: { $0.url == url }) else {
            return
        }
        if isChosen { chosen.insert(url) } else { chosen.remove(url) }
    }

    /// The chosen leftovers, in the order the page lists them once the scan is over.
    var chosenLeftovers: [ScanItem] {
        ScanOrder.ordered(leftovers, scanning: false).filter { item in
            item.selection.isSelectable && item.url.map(chosen.contains) == true
        }
    }

    /// Whether Uninstall is on offer: the model can run, the app can be removed and its leftovers are all in, so the
    /// review lists everything (APP-005, APP-007).
    var canUninstall: Bool {
        guard uninstall != nil, !isPlanning, leftoverState == .scanned, let app = selectedApp else { return false }
        return app.removability == .removable
    }

    /// The review of uninstalling the selected app and the chosen leftovers (APP-007), or `nil` if none can start, or
    /// the selection changed while the plan was built. The plan is built now with the path guard of the current
    /// exclusions, and the run checks every item again just before it acts (SAF-007, SAF-008). Nothing moves until the
    /// user confirms in the review. When the run ends, what it moved leaves the page.
    /// - Throws: ``UninstallPlanError`` if the plan is refused; a plan is all or nothing.
    func reviewUninstall() async throws(UninstallPlanError) -> UninstallReview? {
        guard canUninstall, let uninstall, let app = selectedApp else { return nil }
        isPlanning = true
        defer { isPlanning = false }
        let generation = leftoverGeneration
        let plan = try await Self.plan(uninstall.applications, app, chosenLeftovers, context.protection)
        guard generation == leftoverGeneration, selection == app.id else { return nil }
        let trash = TrashReview(
            plan: plan, runPlan: uninstall.runPlan, readFreeSpace: uninstall.readFreeSpace
        ) { [weak self] report in
            self?.finishUninstall(report, of: app)
        }
        return UninstallReview(app: app, trash: trash, quitApp: uninstall.quitApp)
    }

    /// Drops what a run moved to the Trash from the page: the app, and with it the selection, or the leftovers.
    func finishUninstall(_ report: RunReport, of app: InstalledApp) {
        let trashed = Set(report.trashedURLs)
        if trashed.contains(app.url) {
            apps.removeAll { $0.id == app.id }
            select(nil)
        } else {
            leftovers.removeAll { $0.url.map(trashed.contains) == true }
            chosen.subtract(trashed)
        }
    }

    /// Stops the scan, if there is one (SAF-014). Scanning never acts on anything, so there is nothing to undo.
    func cancelScan() {
        scanTask?.cancel()
        select(nil)
    }

    /// Starts a scan if there has not been one yet, as when the user opens the page. A finished scan is kept, and a
    /// stopped one stays stopped, so a scan the user stopped doesn't start again behind their back.
    @discardableResult
    func scanIfNotScanned() -> Task<Void, Never>? {
        guard state == .notScanned else { return nil }
        return scan()
    }

    /// Gives scans the user's exclusions as they are now and drops the listed apps they hide, without a rescan
    /// (SET-001). A scan already running leaves out the same apps as they arrive.
    func protect(with protection: PathGuardConfiguration) {
        context = ScanContext(
            home: context.home, ownership: context.ownership, protection: protection,
            runningApps: context.runningApps, toolRoot: context.toolRoot)
        exclusionRevision += 1
        apps.removeAll { context.hides($0.url) }
        leftovers.removeAll { context.hides($0) }
        if selection != nil, selectedApp == nil { select(nil) }
    }

    /// Starts a scan off the main actor, in case the engine does some of its work before it returns the stream
    /// (NFR-PERF-001).
    @concurrent
    private nonisolated static func start(_ scan: AppScan, context: ScanContext) async -> AsyncStream<AppInventoryEvent>
    {
        scan(context)
    }

    /// The uninstall plan, built off the main actor: each item costs several file-system reads (NFR-PERF-001).
    @concurrent
    private nonisolated static func plan(
        _ applications: Applications, _ app: InstalledApp, _ leftovers: [ScanItem],
        _ protection: PathGuardConfiguration
    ) async throws(UninstallPlanError) -> Plan {
        try applications.uninstallPlan(for: app, leftovers: leftovers, pathGuard: PathGuard(configuration: protection))
    }

    /// Asks `reader` for the receipts of the app at `url`, off the main actor. A lookup that was stopped leaves nothing
    /// to show.
    @concurrent
    private nonisolated static func lookUpReceipt(
        _ reader: any PackageReceiptReader, of url: URL
    ) async -> ReceiptState {
        do {
            let receipts = try await reader.receipts(forAppAt: url)
            return receipts.isEmpty ? .none : .found(receipts)
        } catch {
            return error == .stopped ? .idle : .failed
        }
    }

    @concurrent
    private nonisolated static func start(
        _ scan: LeftoverScan, _ app: InstalledApp, _ context: ScanContext
    ) async -> AsyncStream<ScanEvent> {
        scan(app, context)
    }
}
