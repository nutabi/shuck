import Foundation
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

extension InstalledApp {
    /// An app made up for a test, at `/StubHome/<path>`, so no test reads a real app (SAF-016).
    static func made(
        _ path: String, name: String? = nil, bundleID: String? = nil, size: Int64 = 1_000, lastOpened: Date? = nil,
        removability: AppRemovability = .removable
    ) -> InstalledApp {
        let url = URL(filePath: "/StubHome").appending(path: path, directoryHint: .isDirectory)
        return InstalledApp(
            url: url, name: name ?? url.deletingPathExtension().lastPathComponent, bundleID: bundleID,
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), modified: Date(timeIntervalSince1970: 0),
            version: "1.0", lastOpened: lastOpened, removability: removability)
    }
}

/// How often a made-up scan started.
final class ScanCount: Sendable {
    private let started = Mutex(0)
    var value: Int { started.withLock { $0 } }

    func increment() {
        started.withLock { $0 += 1 }
    }
}

/// The Applications page's state: the scan, Stop, the sort and the search (APP-001, APP-009, SAF-014).
///
/// The scan is replaced by made-up events, so these tests never read the real `/Applications` (SAF-016).
@MainActor
struct ApplicationsModelTests {
    let context = ScanContext(home: URL(filePath: "/StubHome", directoryHint: .isDirectory))

    /// By name: alpha, Café, Mid, Zeta. By size: Zeta, Mid, alpha, Café. By last opened: Café and Zeta, never opened,
    /// then Mid, then alpha.
    static let apps = [
        InstalledApp.made("Applications/Zeta.app", bundleID: "com.last.zeta", size: 100),
        InstalledApp.made(
            "Applications/alpha.app", bundleID: "com.first.alpha", size: 300,
            lastOpened: Date(timeIntervalSince1970: 2_000)),
        InstalledApp.made(
            "Applications/Mid.app", bundleID: "org.mid.tool", size: 200, lastOpened: Date(timeIntervalSince1970: 1_000)),
        InstalledApp.made("Applications/Cafe.app", name: "Café", bundleID: "com.example.coffee", size: 400),
    ]

    /// A model whose scan finds `events`, and a count of how often the scan started.
    func model(finding events: [AppInventoryEvent] = ApplicationsModelTests.apps.map { .app($0) }) -> (
        ApplicationsModel, ScanCount
    ) {
        let scans = ScanCount()
        let model = ApplicationsModel(context: context) { _ in
            scans.increment()
            return AsyncStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
        return (model, scans)
    }

    @Test func appsAndUnreadableFoldersStreamIntoTheModelAPP001() async {
        let locked = URL(filePath: "/StubHome/Applications/Locked")
        let broken = URL(filePath: "/StubHome/Applications/Broken")
        let events: [AppInventoryEvent] = [
            .app(Self.apps[0]), .notAccessible(locked), .unreadable(broken), .app(Self.apps[1]),
        ]
        let (model, _) = model(finding: events)
        #expect(model.state == .notScanned)

        let scan = model.scan()
        #expect(model.state == .scanning)
        // A scan is not started while one runs.
        #expect(model.scan() == nil)
        await scan?.value

        #expect(model.state == .scanned)
        #expect(model.apps == [Self.apps[0], Self.apps[1]])
        #expect(model.notAccessible == [locked])
        #expect(model.unreadable == [broken])
        // A new scan starts from an empty list.
        let again = model.scan()
        #expect(model.apps.isEmpty)
        await again?.value
        #expect(model.apps.count == 2)
    }

    @Test func stopLeavesTheScanStoppedAndTheListEmptyAndScanStartsAgainSAF014() async throws {
        // The first scan never ends by itself; the next one finds one app.
        let (stream, continuation) = AsyncStream.makeStream(of: AppInventoryEvent.self)
        let streams = Mutex([
            stream,
            AsyncStream {
                $0.yield(.app(Self.apps[0]))
                $0.finish()
            },
        ])
        let model = ApplicationsModel(context: context) { _ in streams.withLock { $0.removeFirst() } }

        let scan = try #require(model.scan())
        continuation.yield(.app(Self.apps[0]))
        continuation.yield(.notAccessible(URL(filePath: "/StubHome/Applications/Locked")))
        model.cancelScan()
        await scan.value

        #expect(model.state == .stopped)
        #expect(model.apps.isEmpty && model.notAccessible.isEmpty)
        #expect(model.canScan)

        await model.scan()?.value
        #expect(model.state == .scanned)
        #expect(model.apps == [Self.apps[0]])
    }

    @Test(arguments: [ApplicationsModel.ScanState.notScanned, .scanned, .stopped])
    func openingThePageScansOnlyAPageThatHasNotScannedYetSAF014(from state: ApplicationsModel.ScanState) async {
        let (model, scans) = self.model()
        if state != .notScanned {
            let scan = model.scan()
            if state == .stopped { model.cancelScan() }
            await scan?.value
        }
        #expect(model.state == state)
        let before = scans.value

        await model.scanIfNotScanned()?.value

        #expect(scans.value - before == (state == .notScanned ? 1 : 0))
    }

    @Test(arguments: [
        (AppSortKey.name, SortOrder.forward, ["alpha", "Café", "Mid", "Zeta"]),
        (.name, .reverse, ["Zeta", "Mid", "Café", "alpha"]),
        (.size, .forward, ["Zeta", "Mid", "alpha", "Café"]),
        (.size, .reverse, ["Café", "alpha", "Mid", "Zeta"]),
        // An app never opened comes first in increasing order, and ties are broken by name (APP-009).
        (.lastOpened, .forward, ["Café", "Zeta", "Mid", "alpha"]),
        (.lastOpened, .reverse, ["alpha", "Mid", "Zeta", "Café"]),
    ])
    func theListSortsByNameSizeAndLastOpenedInBothDirectionsAPP009(
        key: AppSortKey, order: SortOrder, names: [String]
    ) async {
        let (model, _) = self.model()
        await model.scan()?.value
        // The default is by name, increasing.
        #expect(model.visibleApps.map(\.name) == ["alpha", "Café", "Mid", "Zeta"])

        model.sortOrder = [AppSortComparator(key: key, order: order)]

        #expect(model.visibleApps.map(\.name) == names)
    }

    @Test(arguments: [
        ("", ["alpha", "Café", "Mid", "Zeta"]),
        // The name, ignoring case.
        ("ZETA", ["Zeta"]),
        // The name, ignoring diacritics.
        ("cafe", ["Café"]),
        // The bundle ID alone.
        ("org.mid", ["Mid"]),
        ("example.coffee", ["Café"]),
        ("nothing like this", []),
    ])
    func searchMatchesTheNameAndTheBundleIDAPP009(query: String, names: [String]) async {
        let (model, _) = self.model()
        await model.scan()?.value

        model.searchText = query

        #expect(model.visibleApps.map(\.name) == names)
    }
}

extension ScanItem {
    /// A leftover made up for a test, at `/StubHome/Library/<name>`.
    fileprivate static func leftover(_ name: String, confidence: Confidence = .high) -> ScanItem {
        ScanItem(
            url: URL(filePath: "/StubHome/Library/\(name)"), snapshot: ItemSnapshot(kind: .folder, allocatedSize: 10),
            tier: .yourData, method: .trash, reason: "Stub", source: .applications, confidence: confidence)
    }
}

/// The leftover scans a made-up scan was asked to run.
final class LeftoverCalls: Sendable {
    private let calls = Mutex<[(app: InstalledApp, installed: AppsByName)]>([])
    var apps: [InstalledApp] { calls.withLock { $0.map(\.app) } }
    var firstInstalled: AppsByName? { calls.withLock { $0.first?.installed } }

    func record(_ app: InstalledApp, _ installed: AppsByName) {
        calls.withLock { $0.append((app, installed)) }
    }
}

/// The selected app's leftovers: when they are scanned, for which app, and what the scan is given (APP-002 to APP-005,
/// R-05).
///
/// Each app's leftover scan is a stream the test holds, so no test reads a real `Library` folder (SAF-016).
@MainActor
struct ApplicationsLeftoversModelTests {
    let context = ScanContext(home: URL(filePath: "/StubHome", directoryHint: .isDirectory))
    let alpha = InstalledApp.made("Applications/Alpha.app", bundleID: "com.example.alpha")
    let beta = InstalledApp.made("Applications/Beta.app", bundleID: "com.example.beta")

    /// A model that finds `apps`, and one held leftover stream for each of them. `calls` has the arguments of each
    /// leftover scan, in the order they started.
    final class Harness {
        let model: ApplicationsModel
        let streams: [URL: AsyncStream<ScanEvent>.Continuation]
        let calls: LeftoverCalls

        init(model: ApplicationsModel, streams: [URL: AsyncStream<ScanEvent>.Continuation], calls: LeftoverCalls) {
            self.model = model
            self.streams = streams
            self.calls = calls
        }
    }

    func harness(apps: [InstalledApp]) -> Harness {
        var continuations: [URL: AsyncStream<ScanEvent>.Continuation] = [:]
        var held: [URL: AsyncStream<ScanEvent>] = [:]
        for app in apps {
            let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
            held[app.id] = stream
            continuations[app.id] = continuation
        }
        let calls = LeftoverCalls()
        let streams = held
        let leftoverScan: ApplicationsModel.LeftoverScan = { app, installed, _ in
            calls.record(app, installed)
            return streams[app.id] ?? AsyncStream { $0.finish() }
        }
        let model = ApplicationsModel(context: context, leftoverScan: leftoverScan) { _ in
            AsyncStream { continuation in
                for app in apps { continuation.yield(.app(app)) }
                continuation.finish()
            }
        }
        return Harness(model: model, streams: continuations, calls: calls)
    }

    private func exclusions(_ paths: [String]) -> PathGuardConfiguration {
        .production(
            home: context.home, appBundle: URL(filePath: "/Applications/Shuck.app"),
            userExclusions: paths.map { URL(filePath: $0) })
    }

    @Test func leftoversStreamInForTheSelectedAppAndItsUnreadableFoldersStayApartAPP002() async throws {
        let harness = harness(apps: [alpha, beta])
        let model = harness.model
        await model.scan()?.value
        let (high, medium) = (ScanItem.leftover("com.example.alpha"), ScanItem.leftover("Alpha", confidence: .medium))
        let locked = URL(filePath: "/StubHome/Library/Containers")
        let broken = URL(filePath: "/StubHome/Library/Logs")

        // Nothing is scanned until an app is selected, and then only that app.
        #expect(harness.calls.apps.isEmpty && model.leftoverState == .idle)
        let task = try #require(model.select(alpha.id))
        #expect(model.leftoverState == .scanning)
        let events: [ScanEvent] = [.item(high), .notAccessible(locked), .item(medium), .unreadable(broken)]
        for event in events { harness.streams[alpha.id]?.yield(event) }
        harness.streams[alpha.id]?.finish()
        await task.value

        #expect(model.leftoverState == .scanned)
        #expect(model.leftovers == [high, medium])
        #expect(model.leftoverNotAccessible == [locked] && model.leftoverUnreadable == [broken])
        #expect(model.notAccessible.isEmpty && model.unreadable.isEmpty)
        #expect(harness.calls.apps == [alpha])
    }

    @Test func anAppChosenWhileTheScanRunsGetsItsLeftoversWhenTheScanEndsAPP002() async throws {
        let (appStream, appEvents) = AsyncStream.makeStream(of: AppInventoryEvent.self)
        let calls = ScanCount()
        let leftoverScan: ApplicationsModel.LeftoverScan = { _, _, _ in
            calls.increment()
            return AsyncStream { $0.finish() }
        }
        let model = ApplicationsModel(context: context, leftoverScan: leftoverScan) { _ in appStream }
        let scan = try #require(model.scan())
        // The app is chosen before the scan has finished, so its leftovers wait.
        model.select(alpha.id)
        appEvents.yield(.app(alpha))
        #expect(calls.value == 0 && model.leftoverState == .idle)

        appEvents.finish()
        await scan.value

        #expect(calls.value == 1 && model.leftoverState == .scanned)
    }

    @Test(arguments: AppRemovability.Reason.allCases)
    func aBlockedAppIsListedButItsLeftoversAreNotScannedAPP005(reason: AppRemovability.Reason) async {
        let locked = InstalledApp.made(
            "Applications/Locked.app", bundleID: "com.example.locked", removability: .blocked(reason))
        let harness = harness(apps: [locked])
        await harness.model.scan()?.value

        harness.model.select(locked.id)

        #expect(harness.model.apps == [locked] && harness.model.selectedApp == locked)
        #expect(harness.calls.apps.isEmpty && harness.model.leftoverState == .idle)
    }

    @Test func changingTheSelectionCancelsAndClearsAndALateEventDoesNotLandAPP002() async throws {
        let harness = harness(apps: [alpha, beta])
        let model = harness.model
        await model.scan()?.value
        let stale = ScanItem.leftover("com.example.alpha")
        let fresh = ScanItem.leftover("com.example.beta")

        let first = model.select(alpha.id)
        harness.streams[alpha.id]?.yield(.item(stale))
        harness.streams[alpha.id]?.yield(.notAccessible(URL(filePath: "/StubHome/Library/Containers")))
        let second = try #require(model.select(beta.id))
        #expect(model.leftovers.isEmpty && model.leftoverNotAccessible.isEmpty)
        // The old scan still has things to say, and says them before it ends.
        harness.streams[alpha.id]?.yield(.item(stale))
        harness.streams[alpha.id]?.finish()
        await first?.value
        harness.streams[beta.id]?.yield(.item(fresh))
        harness.streams[beta.id]?.finish()
        await second.value

        #expect(model.leftovers == [fresh] && model.leftoverNotAccessible.isEmpty)
        #expect(model.leftoverState == .scanned)

        model.select(nil)
        #expect(model.leftovers.isEmpty && model.leftoverState == .idle)
    }

    @Test func theLeftoverScanGetsEveryInstalledAppEvenAfterTheExclusionsDropOneR05() async throws {
        let hidden = InstalledApp.made("Applications/Private/Hidden.app", bundleID: "com.example.hidden")
        let harness = harness(apps: [alpha, hidden])
        let model = harness.model
        await model.scan()?.value
        model.searchText = "alpha"
        model.protect(with: exclusions(["/StubHome/Applications/Private"]))
        #expect(model.apps == [alpha])

        harness.streams[alpha.id]?.finish()
        await model.select(alpha.id)?.value

        // The hidden app is still installed, and the search does not narrow the names.
        #expect(harness.calls.firstInstalled == AppsByName(apps: [alpha, hidden]))
    }

    @Test func anExclusionDropsTheSelectedAppAndHiddenLeftoversAndAScanStartedBeforeItSET001() async throws {
        let harness = harness(apps: [alpha, beta])
        let model = harness.model
        await model.scan()?.value
        let kept = ScanItem.leftover("keep")
        let hidden = ScanItem.leftover("Private/hide")
        let task = try #require(model.select(alpha.id))

        // The scan started before the change, and nothing has landed yet, so it leaves out what the new list hides.
        model.protect(with: exclusions(["/StubHome/Library/Private"]))
        harness.streams[alpha.id]?.yield(.item(hidden))
        harness.streams[alpha.id]?.yield(.item(kept))
        harness.streams[alpha.id]?.finish()
        await task.value
        #expect(model.leftovers == [kept])

        // An item already listed goes at once.
        model.protect(with: exclusions(["/StubHome/Library/keep"]))
        #expect(model.leftovers.isEmpty)

        // The selected app leaves the list, and the selection with it.
        model.protect(with: exclusions(["/StubHome/Applications/Alpha.app"]))
        #expect(model.apps == [beta] && model.selection == nil && model.leftoverState == .idle)
    }

    @Test func aNewScanClearsTheSelectedAppsLeftoversSAF014() async throws {
        let harness = harness(apps: [alpha])
        let model = harness.model
        await model.scan()?.value
        let task = try #require(model.select(alpha.id))
        harness.streams[alpha.id]?.yield(.item(.leftover("one")))
        harness.streams[alpha.id]?.finish()
        await task.value
        #expect(model.leftovers.count == 1)

        await model.scan()?.value

        #expect(model.selection == nil && model.leftovers.isEmpty && model.leftoverState == .idle)
    }
}
