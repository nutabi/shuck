import Foundation
import ShuckExecution
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// An app that is running until something quits it. It takes or refuses a quit request as the test says, so no test
/// reaches this Mac's apps (SAF-016).
final class StubApps: RunningApps, AppQuitter {
    private let running: Mutex<Set<String>>
    private let accepting: Bool
    /// Whether a quit request makes the app exit. An app that ignores the request keeps running.
    private let exits: Bool
    let requests = Mutex(0)

    init(running: Set<String>, accepting: Bool = true, exits: Bool = true) {
        self.running = Mutex(running)
        self.accepting = accepting
        self.exits = exits
    }

    func bundleIDs() -> Set<String> { running.withLock { $0 } }
    func name(of bundleID: String) -> String? { nil }

    func start(_ bundleID: String) { running.withLock { _ = $0.insert(bundleID) } }
    func stop(_ bundleID: String) { running.withLock { _ = $0.remove(bundleID) } }

    func requestQuit(bundleID: String) -> Int {
        requests.withLock { $0 += 1 }
        guard accepting else { return 0 }
        if exits { stop(bundleID) }
        return 1
    }
}

/// The uninstall on the Applications page: what is chosen, the plan, Quit and the run (APP-005 to APP-007, APP-011).
///
/// The app, its leftovers and the plan are real files in a fixture root, since a plan reads each item. The run is a stub
/// that moves nothing, and the pause never sleeps (SAF-016).
@MainActor
final class UninstallReviewTests {
    let root: URL
    let bundle: URL
    let cache: URL
    let support: URL
    let agent: URL
    let system: URL
    let bundleID = "com.example.fixture"

    init() throws {
        // A folder in the temporary folder, as the test harness makes one, with its path resolved (SAF-016, D-41).
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShuckFixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let resolved = try #require(realpath(folder.path, nil))
        defer { free(resolved) }
        let root = URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
        self.root = root
        func make(_ path: String, bytes: Int = 10) throws -> URL {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)
            return url
        }
        bundle = root.appending(path: "Applications/Fixture.app", directoryHint: .isDirectory)
        _ = try make("Applications/Fixture.app/Contents/MacOS/Fixture")
        cache = root.appending(path: "Library/Caches/com.example.Fixture", directoryHint: .isDirectory)
        _ = try make("Library/Caches/com.example.Fixture/data", bytes: 100)
        support = root.appending(path: "Library/Application Support/Fixture", directoryHint: .isDirectory)
        _ = try make("Library/Application Support/Fixture/data", bytes: 50)
        agent = try make("Library/LaunchAgents/com.example.Fixture.helper.plist")
        system = try make("SystemLibrary/Preferences/com.example.Fixture.plist")
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// The path guard's configuration for the fixture root as home, without the `/private` prefix (D-41).
    var protection: PathGuardConfiguration {
        PathGuardConfiguration(
            home: root, systemLocations: PathGuardConfiguration.systemLocations.filter { $0 != "/private" },
            appBundle: URL(filePath: "/Applications/Shuck.app"), userExclusions: [])
    }

    func app(removability: AppRemovability = .removable) throws -> InstalledApp {
        InstalledApp(
            url: bundle, name: "Fixture", bundleID: "com.example.Fixture",
            snapshot: try #require(ItemSnapshot.read(bundle)),
            modified: try #require(ModificationDate.read(at: bundle)),
            removability: removability)
    }

    /// The scan's leftovers: the cache and the agent start selected, the support folder does not, and the system-wide
    /// preferences are disabled.
    func leftovers() throws -> [ScanItem] {
        try [
            (cache, ItemSelection.selected), (support, .unselected), (agent, .selected),
            (system, .disabled("Needs admin")),
        ].map { url, selection in
            ScanItem(
                url: url, snapshot: try #require(ItemSnapshot.read(url)), tier: .yourData, method: .trash,
                reason: "Fixture", source: .applications, modified: ModificationDate.read(at: url),
                confidence: .high, selection: selection)
        }
    }

    /// A run that moves every Trash item to a made-up place, except those named in `skipping`, and unloads agents.
    func run(skipping: Set<URL> = []) -> RunPlan {
        { (plan: Plan) async throws(HistoryError) -> RunReport in
            let outcomes = plan.items.map { item in
                if let url = item.url, item.method == .trash, skipping.contains(url) {
                    return ItemOutcome(item: item, result: .skipped(.cancelled))
                }
                return ItemOutcome(item: item, result: .done(item.method == .trash ? item.url : nil))
            }
            return RunReport(run: plan.run, outcomes: outcomes)
        }
    }

    /// A model that scanned the fixture app and its leftovers, and selected the app. `pause` is the wait between two
    /// looks at the running apps.
    func scannedModel(
        app: InstalledApp? = nil, apps: StubApps, runPlan: RunPlan? = nil,
        pause: @escaping @Sendable () async throws -> Void = {}
    ) async throws -> ApplicationsModel {
        let app = try app ?? self.app()
        let items = try leftovers()
        let model = ApplicationsModel(
            context: ScanContext(home: root, protection: protection, runningApps: apps),
            leftoverScan: { _, _ in
                AsyncStream { continuation in
                    for item in items { continuation.yield(.item(item)) }
                    continuation.finish()
                }
            },
            uninstall: .init(
                applications: Applications(appFolders: [
                    root.appending(path: "Applications", directoryHint: .isDirectory)
                ]),
                runPlan: runPlan ?? run(),
                quitApp: QuitApp(runningApps: apps, quitter: apps, pause: pause)),
            appScan: { _ in
                AsyncStream { continuation in
                    continuation.yield(.app(app))
                    continuation.finish()
                }
            })
        await model.scan()?.value
        await model.select(app.id)?.value
        return model
    }

    // MARK: - Choosing and planning

    @Test func leftoversStartAsTheScanSelectedThemAndADisabledOneCannotBeChosenAPP007() async throws {
        let model = try await scannedModel(apps: StubApps(running: []))

        #expect(model.chosen == [cache, agent])
        model.setChosen(true, for: try #require(model.leftovers.first { $0.url == support }))
        model.setChosen(false, for: try #require(model.leftovers.first { $0.url == cache }))
        model.setChosen(true, for: try #require(model.leftovers.first { $0.url == system }))
        #expect(Set(model.chosenLeftovers.compactMap(\.url)) == [support, agent])
        #expect(model.chosen.contains(system) == false)
    }

    @Test func theReviewListsTheBundleFirstThenTheChosenLeftoversAndStopsAgentsAPP005APP007APP011() async throws {
        let model = try await scannedModel(apps: StubApps(running: []))

        let review = try #require(try await model.reviewUninstall())

        // The agent has a Trash item and an unload step, so the plan has one item more than the review lists, and the
        // bundle comes first.
        #expect(review.trash.plan.items.count == 4)
        #expect(review.trashItems.count == 3)
        #expect(review.trashItems.first?.url == bundle)
        #expect(Set(review.trashItems.compactMap(\.url)) == [bundle, cache, agent])
        #expect(review.agents == [agent])
        #expect(review.totalBytes == review.trashItems.reduce(0) { $0 + $1.allocatedSize })
        #expect(review.trash.plan.tool == .applications)
        #expect(review.quit == .notRunning && review.canMove)
        // Choosing the agent away leaves nothing to unload.
        model.setChosen(false, for: try #require(model.leftovers.first { $0.url == agent }))
        let without = try #require(try await model.reviewUninstall())
        #expect(without.agents.isEmpty)
        #expect(Set(without.trashItems.compactMap(\.url)) == [bundle, cache])
    }

    @Test func aBlockedAppAnAppWithoutItsLeftoversAndAModelWithoutARunOfferNoUninstallAPP005() async throws {
        let blocked = try await scannedModel(
            app: try app(removability: .blocked(.bundleNotWritable)), apps: StubApps(running: []))
        #expect(!blocked.canUninstall)
        #expect(try await blocked.reviewUninstall() == nil)

        let ready = try await scannedModel(apps: StubApps(running: []))
        #expect(ready.canUninstall)
        ready.select(nil)
        #expect(!ready.canUninstall)

        let none = ApplicationsModel(context: ScanContext(home: root)) { _ in AsyncStream { $0.finish() } }
        #expect(!none.canUninstall)
    }

    // MARK: - Quit, then run

    @Test func quitEnablesMoveToTrashOnlyAfterTheAppHasGoneAndTheRunDropsWhatItMovedAPP006APP007() async throws {
        let apps = StubApps(running: [bundleID])
        let model = try await scannedModel(apps: apps)
        let review = try #require(try await model.reviewUninstall())

        #expect(review.quit == .running)
        #expect(!review.canMove)
        // A running app is never moved, and nothing is asked to quit until the user presses Quit.
        #expect(review.start() == nil)
        #expect(apps.requests.withLock { $0 } == 0)

        let quitting = review.quitTheApp()
        #expect(review.quit == .waiting)
        await quitting?.value

        #expect(review.quit == .notRunning)
        #expect(review.canMove)
        await review.start()?.value
        guard case .finished(let report) = review.trash.phase else {
            Issue.record("Not finished: \(review.trash.phase)")
            return
        }
        #expect(Set(report.trashedURLs) == [bundle, cache, agent])
        // The app, and so its selection and leftovers, left the page.
        #expect(model.apps.isEmpty)
        #expect(model.selection == nil && model.leftovers.isEmpty)
    }

    @Test func aRequestTheAppDoesNotTakeTellsTheUserToQuitItAndCheckAgainContinuesAPP006() async throws {
        let apps = StubApps(running: [bundleID], accepting: false)
        let review = try #require(try await scannedModel(apps: apps).reviewUninstall())

        await review.quitTheApp()?.value
        #expect(review.quit == .notSent)
        #expect(!review.canMove)
        review.refresh()
        #expect(review.quit == .notSent)

        apps.stop(bundleID)
        review.refresh()
        #expect(review.quit == .notRunning && review.canMove)
    }

    @Test func stopWaitingCancelsTheWaitAndNeverForcesTheAppAPP006() async throws {
        let apps = StubApps(running: [bundleID], exits: false)
        let pauses = Mutex(0)
        let review = try #require(
            try await scannedModel(
                apps: apps,
                pause: {
                    pauses.withLock { $0 += 1 }
                    try Task.checkCancellation()
                }
            ).reviewUninstall())

        let waiting = review.quitTheApp()
        #expect(review.quit == .waiting)
        // A second press while waiting sends nothing more.
        #expect(review.quitTheApp() == nil)
        review.cancelQuit()
        await waiting?.value

        #expect(review.quit == .running)
        #expect(!review.canMove)
        #expect(apps.requests.withLock { $0 } == 1)
        #expect(apps.bundleIDs() == [bundleID])
    }

    @Test func theRunningAppsAreReadAgainJustBeforeTheRunAPP006SAF009() async throws {
        let apps = StubApps(running: [])
        let review = try #require(try await scannedModel(apps: apps).reviewUninstall())
        #expect(review.canMove)

        // The user opened the app again while the review was on screen.
        apps.start(bundleID)

        #expect(review.start() == nil)
        #expect(review.quit == .running)
        #expect(review.trash.phase == .waiting)
    }

    @Test func aSkippedBundleLeavesTheAppListedAndOnlyDropsTheLeftoversThatMovedAPP007SAF011() async throws {
        let model = try await scannedModel(apps: StubApps(running: []), runPlan: run(skipping: [bundle, agent]))
        let review = try #require(try await model.reviewUninstall())

        await review.start()?.value

        guard case .finished(let report) = review.trash.phase else {
            Issue.record("Not finished: \(review.trash.phase)")
            return
        }
        #expect(report.trashedURLs == [cache])
        #expect(model.apps.map(\.url) == [bundle])
        #expect(Set(model.leftovers.compactMap(\.url)) == [support, agent, system])
    }
}
