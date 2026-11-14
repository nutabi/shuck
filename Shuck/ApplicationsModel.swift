import Foundation
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
    /// Folders macOS did not let the leftover scan read (SAF-012). The inventory's are in ``notAccessible``.
    private(set) var leftoverNotAccessible: [URL] = []
    /// Folders the leftover scan could not read for another reason (SAF-011).
    private(set) var leftoverUnreadable: [URL] = []
    /// How many times the user's exclusions have changed. A scan that started before a change leaves out what the new
    /// list hides (SET-001).
    private var exclusionRevision = 0
    private let appScan: AppScan
    private let leftoverScan: LeftoverScan
    private var scanTask: Task<Void, Never>?
    private var leftoverTask: Task<Void, Never>?
    /// Counts the leftover scans started, so an event from one that was replaced never lands in the new list.
    private var leftoverGeneration = 0

    /// - Parameter leftoverScan: Without one, an app has no leftovers, for a preview or a test of the list alone.
    init(
        context: ScanContext, leftoverScan: @escaping LeftoverScan = { _, _ in AsyncStream { $0.finish() } },
        appScan: @escaping AppScan
    ) {
        self.context = context
        self.leftoverScan = leftoverScan
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
        leftoverGeneration += 1
        leftovers = []
        leftoverNotAccessible = []
        leftoverUnreadable = []
        leftoverState = .idle
        guard state == .scanned, let app = selectedApp, app.removability == .removable else { return nil }
        leftoverState = .scanning
        let generation = leftoverGeneration
        let (context, revision, leftoverScan) = (context, exclusionRevision, leftoverScan)
        leftoverTask = Task {
            for await event in await Self.start(leftoverScan, app, context) {
                guard generation == leftoverGeneration else { return }
                switch event {
                case .item(let item):
                    // The scan keeps the exclusions it started with, so an item they hide now is left out.
                    if revision != exclusionRevision, self.context.hides(item) { continue }
                    leftovers.append(item)
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

    @concurrent
    private nonisolated static func start(
        _ scan: LeftoverScan, _ app: InstalledApp, _ context: ScanContext
    ) async -> AsyncStream<ScanEvent> {
        scan(app, context)
    }
}
