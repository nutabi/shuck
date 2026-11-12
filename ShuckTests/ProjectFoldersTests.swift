import Foundation
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// The developer project folders (SET-003, SET-004): the defaults, what may be added, how the stored list reaches the
/// engine, and how a change reaches File Cleanup (DEV-R06, D-152, D-154).
///
/// Every test uses made-up folders under `/StubHome`, and a stub for "does this folder exist", so none reads the real
/// home folder (SAF-016).
@MainActor
struct ProjectFoldersTests {
    let home = URL(filePath: "/StubHome", directoryHint: .isDirectory)
    let appBundle = URL(filePath: "/Applications/Shuck.app")

    private func url(_ path: String) -> URL { home.appending(path: path) }

    // MARK: - Defaults and the stored list

    @Test func theDefaultsAreTheCommonFoldersThatExistInTheirOrderSET003() {
        let existing: Set<String> = ["/StubHome/repos", "/StubHome/Developer", "/StubHome/Documents"]

        let defaults = ProjectFolders.defaults(home: home) { existing.contains($0.path) }

        #expect(defaults == ["/StubHome/Developer", "/StubHome/repos"])
        #expect(ProjectFolders.defaults(home: home) { _ in false }.isEmpty)
    }

    private func environment(
        _ settings: [String: Any] = [:], existing: Set<String> = ["/StubHome/Developer", "/StubHome/src"],
        arguments: [String] = [], debugBuild: Bool = false
    ) throws -> AppEnvironment {
        try AppEnvironment(
            arguments: arguments, settings: { settings[$0] }, isFolder: { existing.contains($0.path) },
            debugBuild: debugBuild, appBundle: appBundle,
            bundleID: debugBuild ? ShuckKit.debugBundleID : ShuckKit.bundleID, home: home)
    }

    @Test func withoutAStoredListTheDefaultsAreUsedAndAnEmptyStoredListIsNotSET003SET004() throws {
        let fresh = try environment()
        #expect(fresh.projectFolders.folders.map(\.path) == ["/StubHome/Developer", "/StubHome/src"])

        let cleared = try environment([AppEnvironment.projectFoldersKey: [String]()])
        #expect(cleared.projectFolders.folders.isEmpty)
        #expect(cleared.developerJunk.projectFolders.isEmpty)

        let chosen = try environment([AppEnvironment.projectFoldersKey: ["/StubHome/Work/", "/elsewhere", 7]])
        #expect(chosen.projectFolders.folders.map(\.path) == ["/StubHome/Work", "/elsewhere"])
    }

    @Test func theDefaultsAreNotStoredUntilTheUserChangesTheListSET004() throws {
        let stored = Mutex<[[String]]>([])
        let environment = try AppEnvironment(
            arguments: [], settings: { _ in nil },
            saveProjectFolders: { paths in stored.withLock { $0.append(paths) } },
            isFolder: { $0.path == "/StubHome/Developer" }, debugBuild: false, appBundle: appBundle,
            bundleID: ShuckKit.bundleID,
            home: home)

        #expect(stored.withLock { $0 }.isEmpty)
        environment.projectFolders.remove([url("Developer")])
        #expect(stored.withLock { $0 } == [[]])
    }

    @Test func onlyFoldersInsideTheHomeFolderReachTheEngineSET003() throws {
        let environment = try environment([
            AppEnvironment.projectFoldersKey: [
                "/StubHome/Developer", "/StubHome", "/Users/someone/Elsewhere", "/StubHome/developer", "/StubHome/Code",
            ]
        ])

        let scope = environment.makeProjectScope(environment.projectFolders.folders)

        #expect(scope.developerJunk.projectFolders.map(\.path) == ["/StubHome/Developer", "/StubHome/Code"])
        #expect(scope.ownership.projectFolders == scope.developerJunk.projectFolders)
        // The first scan and the first plan already have them.
        #expect(environment.context.ownership.projectFolders.map(\.path) == ["/StubHome/Developer", "/StubHome/Code"])
        #expect(environment.developerJunk.projectFolders == scope.developerJunk.projectFolders)
    }

    @Test func aFixtureRootTakesItsProjectFoldersFromTheArgumentOnlyAndNeverTheDefaultsSET003() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShuckFixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let arguments = ["Shuck", AppEnvironment.fixtureRootArgument, folder.path(percentEncoded: false)]
        let settings: [String: Any] = [
            AppEnvironment.projectFoldersKey: ["/StubHome/Real"],
            AppEnvironment.projectFoldersArgumentKey: "Developer, /StubHome/Real,../Outside,~/Hidden",
        ]

        let debug = try environment(
            settings, existing: [folder.appending(path: "Developer").path], arguments: arguments, debugBuild: true)
        let root = try #require(try AppEnvironment.fixtureRoot(in: arguments, debugBuild: true))
        let none = try environment(
            [:], existing: [root.appending(path: "Developer").path], arguments: arguments, debugBuild: true)

        #expect(debug.projectFolders.folders.map(\.path) == [root.appending(path: "Developer").path])
        #expect(debug.context.ownership.projectFolders.map(\.path) == [root.appending(path: "Developer").path])
        #expect(none.projectFolders.folders.isEmpty)
    }

    // MARK: - What may be added

    @Test func aFolderOutsideTheHomeFolderOrTheHomeFolderItselfIsRefusedWithoutBeingStoredSET003() {
        let stored = Mutex<[[String]]>([])
        let changes = Mutex<Int>(0)
        let model = FolderListModel(
            list: FolderList(stored: []) { paths in stored.withLock { $0.append(paths) } },
            accepts: { ProjectFolders.isInsideHome($0, home: self.home) },
            didChange: { _ in changes.withLock { $0 += 1 } })

        model.add([URL(filePath: "/Users/someone/Elsewhere"), home, url("Work")])
        #expect(model.folders.map(\.path) == ["/StubHome/Work"])
        #expect(model.refused.map(\.path) == ["/Users/someone/Elsewhere", "/StubHome"])

        model.add([url("Other/../..")])
        #expect(model.refused.count == 1 && model.folders.count == 1)
        #expect(stored.withLock { $0 } == [["/StubHome/Work"]] && changes.withLock { $0 } == 1)
        model.add([url("Fine")])
        #expect(model.refused.isEmpty)
        model.remove([url("Fine")])
        #expect(model.folders.map(\.path) == ["/StubHome/Work"])
    }

    // MARK: - A change reaches File Cleanup

    private let longAgo = Date.distantPast

    private func nodeItem(_ project: String) throws -> ScanItem {
        let modules = url(project).appending(path: "node_modules")
        let folder = url(project.split(separator: "/").first.map(String.init) ?? project)
        let rule = try CleanupRule(
            id: "DEV-R06", name: "Stale node_modules", description: "Stub", category: DeveloperJunk.nodeProjects,
            detection: .folder(folder),
            action: .paths([RulePath(root: folder, pattern: "*/node_modules")], method: .delete),
            tier: .rebuildable, selection: .always, explanation: "Stub",
            documentation: try #require(URL(string: "https://example.test/stub")))
        return ScanItem(
            url: modules, snapshot: ItemSnapshot(kind: .folder, allocatedSize: 1_000), tier: .rebuildable,
            method: .delete, reason: "Stub", source: .developerJunk, modified: longAgo, category: rule.category,
            ruleMatch: RuleMatch(rule: rule, modified: longAgo), project: url(project))
    }

    @Test func aChangedListReplacesDeveloperJunkAndDropsTheRowsItLeavesOutAtOnceSET003() async throws {
        let files = [
            PersonalFile(
                url: url("Developer/new/node_modules/dep/index.js"),
                snapshot: ItemSnapshot(kind: .file, allocatedSize: 5_000), modified: nil, lastOpened: nil),
            PersonalFile(
                url: url("Developer/new/src/main.js"), snapshot: ItemSnapshot(kind: .file, allocatedSize: 5_000),
                modified: nil, lastOpened: nil),
        ]
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let before = OwnershipMap(home: home, projectFolders: [url("Code")])
        let model = FileCleanupModel(
            subTools: [DeveloperJunk(projectFolders: [url("Code")]), largeFiles],
            context: ScanContext(home: home, ownership: before)
        ) { _, _ in
            AsyncStream { continuation in
                continuation.yield(.files(files))
                continuation.finish()
            }
        }
        await model.scan(largeFiles)?.value
        let results = try #require(model.results(of: .developerJunk) as? ScanResults)
        results.apply(.item(try nodeItem("Code/old")))
        results.apply(.item(try nodeItem("Developer/kept")))
        #expect(model.personalFiles.items.count == 2)

        let junk = DeveloperJunk(projectFolders: [url("Developer")])
        let ownership = before.withProjectFolders([url("Developer")])
        await model.useProjectFolders(junk, ownership: ownership).value

        #expect((model.subTool(.developerJunk) as? DeveloperJunk)?.projectFolders == [url("Developer")])
        #expect(model.subTool(largeFiles.id) != nil && model.subTools.count == 2)
        // The folder that is no longer a project folder loses its row; the one that still is keeps it.
        #expect(results.items.compactMap { $0.project?.lastPathComponent } == ["kept"])
        // A file inside the new project folder's node_modules is Developer Junk's now.
        #expect(model.personalFiles.items.keys.map(\.lastPathComponent) == ["main.js"])
        #expect(Set(model.personalFilesResults[largeFiles.id]?.rows.map(\.name) ?? []) == ["main.js"])
    }

    /// The model plans with its own Developer Junk, so a page's older copy cannot plan with old roots (R-17, SAF-007).
    @Test func aPlanUsesTheModelsCurrentSubToolNotAStaleCopyHandedInSAF007() async throws {
        let stale = DeveloperJunk()
        let model = FileCleanupModel(
            subTools: [stale], context: ScanContext(home: home), runPlan: YourDataItemsTests().runAll)
        let results = try #require(model.results(of: .developerJunk) as? ScanResults)
        results.apply(.item(try nodeItem("Developer/kept")))
        results.selectAll()
        let ownership = OwnershipMap(home: home).withProjectFolders([url("Developer")])
        await model.useProjectFolders(DeveloperJunk(projectFolders: [url("Developer")]), ownership: ownership).value
        #expect(results.items.count == 1)

        let confirmation = try #require(try await model.confirmRebuildable(stale))

        #expect(confirmation.plan.allowedRoots.contains(url("Developer")))
        #expect(confirmation.plan.items.compactMap(\.url) == [url("Developer/kept/node_modules")])
        #expect(!model.isPlanning)
    }

    /// Both settings rebuild the model's context, so neither change may undo the other, in either order.
    @Test(arguments: [true, false])
    func exclusionsAndProjectFoldersBothSurviveInEitherOrderSET001SET003(exclusionsFirst: Bool) async throws {
        let model = FileCleanupModel(subTools: [DeveloperJunk()], context: ScanContext(home: home))
        let protection = PathGuardConfiguration.production(
            home: home, appBundle: appBundle, userExclusions: [url("Secret")])
        let scope = AppEnvironment.projectScope([url("Developer")], home: home)

        if exclusionsFirst {
            await model.protect(with: protection).value
            await model.useProjectFolders(scope.developerJunk, ownership: scope.ownership).value
        } else {
            await model.useProjectFolders(scope.developerJunk, ownership: scope.ownership).value
            await model.protect(with: protection).value
        }

        let context = model.context
        #expect(context.protection.userExclusions.map(\.path) == ["/StubHome/Secret"])
        #expect(context.ownership.projectFolders.map(\.path) == ["/StubHome/Developer"])
        #expect(
            (model.subTool(.developerJunk) as? DeveloperJunk)?.projectFolders.map(\.path) == ["/StubHome/Developer"])
    }

    /// A scan that started before the change leaves out the `node_modules` rows of a folder that is no longer a project
    /// folder, since a plan for them would be refused as a whole (SET-003, D-154).
    @Test func aDeveloperJunkScanInFlightLeavesOutRowsOfARemovedProjectFolderSET003() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        let running = ManualDeveloperJunk(stream: stream)
        let model = FileCleanupModel(
            subTools: [running],
            context: ScanContext(home: home, ownership: OwnershipMap(home: home, projectFolders: [url("Code")])))

        let scan = try #require(model.scan(running))
        let ownership = OwnershipMap(home: home).withProjectFolders([url("Developer")])
        await model.useProjectFolders(DeveloperJunk(projectFolders: [url("Developer")]), ownership: ownership).value
        continuation.yield(.item(try nodeItem("Code/old")))
        continuation.yield(.item(try nodeItem("Developer/kept")))
        continuation.finish()
        await scan.value

        let results = try #require(model.results(of: .developerJunk) as? ScanResults)
        #expect(results.items.compactMap { $0.project?.lastPathComponent } == ["kept"])
    }

    /// The mirror case: a folder added during a personal-files scan takes its `node_modules` from Large Files
    /// (FCL-005, SET-003).
    @Test func aPersonalFilesScanInFlightLeavesOutFilesInANodeModulesDeveloperJunkNowOwnsSET003() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: PersonalFilesEvent.self)
        let largeFiles = LargeFiles(minimumSize: 1_000)
        let model = FileCleanupModel(subTools: [largeFiles], context: ScanContext(home: home)) { _, _ in stream }
        func file(_ path: String) -> PersonalFile {
            PersonalFile(
                url: url(path), snapshot: ItemSnapshot(kind: .file, allocatedSize: 5_000), modified: nil,
                lastOpened: nil)
        }

        let scan = try #require(model.scan(largeFiles))
        let ownership = OwnershipMap(home: home).withProjectFolders([url("Developer")])
        await model.useProjectFolders(DeveloperJunk(projectFolders: [url("Developer")]), ownership: ownership).value
        continuation.yield(.files([file("Developer/app/node_modules/dep/index.js"), file("Developer/app/main.js")]))
        continuation.finish()
        await scan.value

        #expect(model.personalFiles.items.keys.map(\.lastPathComponent) == ["main.js"])
        #expect(Set(model.personalFilesResults[largeFiles.id]?.rows.map(\.name) ?? []) == ["main.js"])
    }
}

/// A Developer Junk whose scan reports what the test sends through its stream.
private struct ManualDeveloperJunk: SubTool {
    let info = ToolInfo(
        id: .developerJunk, name: "Manual", summary: "Reports what a test sends.", symbolName: "testtube.2",
        availability: .available)
    let tiers: Set<Tier> = [.rebuildable]
    let stream: AsyncStream<ScanEvent>

    func allowedRoots(home: URL) -> [URL] { [] }
    func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> { stream }
}
