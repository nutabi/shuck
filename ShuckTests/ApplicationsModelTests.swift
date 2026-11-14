import Foundation
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

extension InstalledApp {
    /// An app made up for a test, at `/StubHome/<path>`, so no test reads a real app (SAF-016).
    static func made(
        _ path: String, name: String? = nil, bundleID: String? = nil, size: Int64 = 1_000, lastOpened: Date? = nil
    ) -> InstalledApp {
        let url = URL(filePath: "/StubHome").appending(path: path, directoryHint: .isDirectory)
        return InstalledApp(
            url: url, name: name ?? url.deletingPathExtension().lastPathComponent, bundleID: bundleID,
            snapshot: ItemSnapshot(kind: .folder, allocatedSize: size), modified: Date(timeIntervalSince1970: 0),
            version: "1.0", lastOpened: lastOpened)
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
