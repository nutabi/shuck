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

/// The state of the Applications page: the apps a scan found, how to sort and search them, and where the scan stands
/// (APP-001, APP-009).
///
/// Applications is a tool of its own, not a File Cleanup sub-tool (D-186), so it has its own model. Apps stream into the
/// list as the scan finds them. Stop cancels the scan (SAF-014).
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

    private(set) var state = ScanState.notScanned
    /// The apps the scan found, in the order it found them. Use ``visibleApps`` to show them.
    private(set) var apps: [InstalledApp] = []
    /// Folders macOS did not let the scan read (SAF-012). Listing them is a later page's job.
    private(set) var notAccessible: [URL] = []
    /// Folders the scan could not read for another reason, such as a disk error (SAF-011).
    private(set) var unreadable: [URL] = []
    /// What the user typed in the search field. It matches an app's name and its bundle ID (APP-009).
    var searchText = ""
    /// The column headers' sort, name first by default (APP-009).
    var sortOrder = [AppSortComparator(key: .name)]
    private(set) var context: ScanContext
    /// How many times the user's exclusions have changed. A scan that started before a change leaves out what the new
    /// list hides (SET-001).
    private var exclusionRevision = 0
    private let appScan: AppScan
    private var scanTask: Task<Void, Never>?

    init(context: ScanContext, appScan: @escaping AppScan) {
        self.context = context
        self.appScan = appScan
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
                notAccessible = []
                unreadable = []
                state = .stopped
            } else {
                state = .scanned
            }
        }
        scanTask = task
        return task
    }

    /// Stops the scan, if there is one (SAF-014). Scanning never acts on anything, so there is nothing to undo.
    func cancelScan() {
        scanTask?.cancel()
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
    }

    /// Starts a scan off the main actor, in case the engine does some of its work before it returns the stream
    /// (NFR-PERF-001).
    @concurrent
    private nonisolated static func start(_ scan: AppScan, context: ScanContext) async -> AsyncStream<AppInventoryEvent>
    {
        scan(context)
    }
}
