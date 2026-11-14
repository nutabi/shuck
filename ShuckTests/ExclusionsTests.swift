import Foundation
import ShuckExecution
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// The stored list of excluded folders, and how a change reaches scans, plans and runs (SET-001, SET-004, D-150).
///
/// The model tests use made-up paths under `/StubHome`. The environment tests create an empty fixture root in the
/// temporary folder, as the test harness does, and only the run test writes to it.
@MainActor
final class ExclusionsTests {
    let home = URL(filePath: "/StubHome", directoryHint: .isDirectory)
    let appBundle = URL(filePath: "/Applications/Shuck.app")
    let fixture: String
    let stored = Mutex<[String]>([])

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShuckFixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fixture = folder.path(percentEncoded: false)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: fixture)
    }

    // MARK: - The stored list

    @Test func pathsAreStandardizedAndRepeatsAndRelativePathsAreDroppedSET001() {
        let list = FolderList(
            stored: [
                "/Users/someone/Work/", "/Users/someone//Work", "/Users/someone/Other/../Work", "Work", "", "/a/./b",
            ]
        ) { _ in }

        #expect(list.folders.map(\.path) == ["/Users/someone/Work", "/a/b"])
    }

    @Test func aFolderThatIsNotThereStaysListedAndSymlinksAreNotResolvedSET001() throws {
        let target = URL(filePath: fixture).appending(path: "Real")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = URL(filePath: fixture).appending(path: "Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let list = FolderList(stored: ["/Users/someone/Gone", link.path]) { _ in }

        #expect(list.folders.map(\.path) == ["/Users/someone/Gone", link.path])
    }

    @Test func eachChangeIsStoredAndRemovalComparesStandardizedPathsSET004() {
        let list = FolderList(stored: ["/a"]) { paths in self.stored.withLock { $0 = paths } }

        list.add([URL(filePath: "/b/"), URL(filePath: "/a"), URL(filePath: "/c")])
        #expect(stored.withLock { $0 } == ["/a", "/b", "/c"])

        list.remove([URL(filePath: "/b/../b/"), URL(filePath: "/never")])
        #expect(stored.withLock { $0 } == ["/a", "/c"])
        #expect(list.folders.map(\.path) == ["/a", "/c"])
    }

    @Test func theModelReportsOnlyRealChangesSET001() {
        let reported = Mutex<[[String]]>([])
        let model = FolderListModel(list: FolderList(stored: ["/a"]) { _ in }) { folders in
            reported.withLock { $0.append(folders.map(\.path)) }
        }

        model.add([URL(filePath: "/a")])
        model.add([URL(filePath: "/b")])
        model.remove([URL(filePath: "/zzz")])
        model.remove([URL(filePath: "/a")])

        #expect(reported.withLock { $0 } == [["/a", "/b"], ["/b"]])
        #expect(model.folders.map(\.path) == ["/b"])
    }

    // MARK: - The environment

    private func environment(
        _ arguments: [String] = [], debugBuild: Bool = false, settings: [String: Any] = [:]
    ) throws -> AppEnvironment {
        try AppEnvironment(
            arguments: arguments, settings: { settings[$0] }, debugBuild: debugBuild, appBundle: appBundle,
            bundleID: debugBuild ? ShuckKit.debugBundleID : ShuckKit.bundleID, home: home)
    }

    @Test func theStoredFoldersReachTheScanContextAndEveryGuardSET001() throws {
        let environment = try environment(settings: [AppEnvironment.excludedFoldersKey: ["/Users/someone/Work/", 7]])

        #expect(environment.excludedFolders.folders.map(\.path) == ["/Users/someone/Work"])
        #expect(environment.context.protection.userExclusions.map(\.path) == ["/Users/someone/Work"])
        // Plans, runs and Restore build their guard from the list as it is when they start.
        environment.excludedFolders.add([URL(filePath: "/Users/someone/Other")])
        let next = environment.makeProtection(environment.excludedFolders.folders)
        #expect(next.userExclusions.map(\.path) == ["/Users/someone/Work", "/Users/someone/Other"])
        #expect(next.protectedLocations.contains(URL(filePath: "/Users/someone/Other")))
    }

    @Test func aFixtureRootTakesItsFoldersFromTheArgumentAndNeverFromTheStoreSET001() throws {
        let arguments = ["Shuck", AppEnvironment.fixtureRootArgument, fixture]
        let settings: [String: Any] = [
            AppEnvironment.excludedFoldersKey: ["/Users/someone/Real"],
            AppEnvironment.excludedFoldersArgumentKey: "Documents/Private, /Users/someone/Real,../Outside,~/Hidden",
        ]

        let debug = try environment(arguments, debugBuild: true, settings: settings)
        let root = try #require(try AppEnvironment.fixtureRoot(in: arguments, debugBuild: true))

        #expect(debug.excludedFolders.folders.map(\.path) == [root.appending(path: "Documents/Private").path])
        // A release build reads neither the fixture argument nor a fixture root.
        let release = try environment(arguments, debugBuild: false, settings: settings)
        #expect(release.excludedFolders.folders.map(\.path) == ["/Users/someone/Real"])
    }

    /// (c): the executor's guard is built when a run starts, so an exclusion made after the plan skips its item.
    @Test func aRunSkipsAFolderExcludedAfterThePlanSET001SAF008() async throws {
        let arguments = ["Shuck", AppEnvironment.fixtureRootArgument, fixture]
        let environment = try environment(arguments, debugBuild: true)
        let root = environment.context.home
        let keep = root.appending(path: "Documents/Keep")
        let file = keep.appending(path: "report.pdf")
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: file)
        let snapshot = try #require(ItemSnapshot.read(file))
        let item = PlannedItem(
            url: file, tier: .yourData, method: .trash, snapshot: snapshot,
            modified: ModificationDate.read(at: file))
        let plan = try Plan(
            tool: .largeFiles, allowedRoots: [root], items: [item],
            pathGuard: PathGuard(configuration: environment.context.protection))

        environment.excludedFolders.add([keep])
        let report = try await environment.run(plan)

        guard case .skipped(.userExclusion) = try #require(report.outcomes.first?.result) else {
            Issue.record("Not skipped by the guard: \(report.outcomes.map(\.result))")
            return
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - File Cleanup's lists

    private func protection(excluding paths: [String]) -> PathGuardConfiguration {
        .production(home: home, appBundle: appBundle, userExclusions: paths.map { URL(filePath: $0) })
    }

    @Test func addingAFolderDropsItsRowsAtOncePlansRefuseThemAndRemovingItBringsThemBackOnTheNextScanSET001()
        async throws
    {
        let helpers = YourDataItemsTests()
        let (model, subTool) = await helpers.scannedModel([helpers.cache("a"), helpers.cache("b")])
        let results = try #require(model.results(of: subTool.id) as? ScanResults)
        results.selectAll()
        let excluded = helpers.url("b").path

        let drop = model.protect(with: protection(excluding: [excluded]))

        // The guard has the new list before the rows are gone.
        await #expect(throws: PlanError.self) { try await model.confirmRebuildable(subTool.id) }
        await drop.value
        #expect(results.items.compactMap(\.url) == [helpers.url("a")])
        #expect(try await model.confirmRebuildable(subTool.id)?.plan.items.map(\.url) == [helpers.url("a")])
        guard case .scanned(let summary) = model.state(of: subTool.id) else { return }
        #expect(summary.itemCount == 1)

        await model.protect(with: protection(excluding: [])).value
        #expect(results.items.compactMap(\.url) == [helpers.url("a")])
        await model.scan(subTool.id)?.value
        #expect(results.items.compactMap(\.url).sorted { $0.path < $1.path } == [helpers.url("a"), helpers.url("b")])
    }

    @Test func aScanThatStartedBeforeTheChangeLeavesOutWhatTheNewListHidesSET001() async throws {
        let helpers = YourDataItemsTests()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        let subTool = ManualSubTool(stream: stream)
        let model = FileCleanupModel(subTools: [subTool], context: helpers.context)

        let scan = try #require(model.scan(subTool.id))
        await model.protect(with: protection(excluding: [helpers.url("b").path])).value
        continuation.yield(.item(helpers.cache("a")))
        continuation.yield(.item(helpers.cache("b")))
        continuation.finish()
        await scan.value

        let results = try #require(model.results(of: subTool.id) as? ScanResults)
        #expect(results.items.compactMap(\.url) == [helpers.url("a")])
    }

    @Test func addingAFolderDropsItsAppsFromApplicationsAndAScanInFlightSET001() async throws {
        let apps = [InstalledApp.made("Applications/Alpha.app"), InstalledApp.made("Applications/Private/Beta.app")]
        let hidden = protection(excluding: [home.appending(path: "Applications/Private").path])
        let context = ScanContext(home: home)

        let finished = ApplicationsModel(context: context) { _ in
            AsyncStream { continuation in
                for app in apps {
                    continuation.yield(.app(app))
                }
                continuation.finish()
            }
        }
        await finished.scan()?.value
        #expect(finished.apps == apps)
        finished.protect(with: hidden)
        #expect(finished.apps == [apps[0]])

        // A scan that started before the change leaves out what the new list hides.
        let (stream, continuation) = AsyncStream.makeStream(of: AppInventoryEvent.self)
        let running = ApplicationsModel(context: context) { _ in stream }
        let scan = try #require(running.scan())
        running.protect(with: hidden)
        for app in apps {
            continuation.yield(.app(app))
        }
        continuation.finish()
        await scan.value
        #expect(running.apps == [apps[0]])
    }

    @Test func addingAFolderDropsItsFilesFromBothPersonalFilesListsAndAScanInFlightSET001() async throws {
        func file(_ path: String) -> PersonalFile {
            PersonalFile(
                url: home.appending(path: path), snapshot: ItemSnapshot(kind: .file, allocatedSize: 5_000),
                modified: nil, lastOpened: nil)
        }
        let files = [file("Documents/Private/a.mov"), file("Documents/ok.mov"), file("Movies/b.mov")]
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let model = FileCleanupModel(subTools: [largeFiles], context: ScanContext(home: home)) { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                continuation.finish()
            }
        }
        await model.scan(largeFiles.id)?.value

        await model.protect(with: protection(excluding: [home.appending(path: "Documents/Private").path])).value

        #expect(Set(model.personalFiles.items.keys.map(\.lastPathComponent)) == ["ok.mov", "b.mov"])
        #expect(Set(model.personalFilesResults[largeFiles.id]?.rows.map(\.name) ?? []) == ["ok.mov", "b.mov"])
        guard case .scanned(let summary) = model.state(of: largeFiles.id) else { return }
        #expect(summary.itemCount == 2)
    }
}

/// A sub-tool whose scan reports what the test sends through its stream.
private struct ManualSubTool: SubTool {
    let info = ToolInfo(
        id: StubRebuildable.id, name: "Manual", summary: "Reports what a test sends.", symbolName: "testtube.2",
        availability: .available)
    let tiers: Set<Tier> = [.rebuildable]
    let stream: AsyncStream<ScanEvent>

    func allowedRoots(home: URL) -> [URL] { [home.appending(path: "Library/Caches")] }
    func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> { stream }
}
