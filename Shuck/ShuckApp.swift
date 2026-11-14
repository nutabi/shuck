import ShuckKit
import SwiftUI
import os

@main
struct ShuckApp: App {
    /// Asks before quitting during a run (SAF-005, SAF-014).
    @NSApplicationDelegateAdaptor(ShuckAppDelegate.self) private var appDelegate
    private let registry: ToolRegistry
    private let pages: SubToolPages
    /// Kept for the app's lifetime, so scan results survive switching between pages.
    @State private var fileCleanup: FileCleanupModel
    @State private var applications: ApplicationsModel
    @State private var history: HistoryModel
    /// The excluded folders Settings lists (SET-001). Changing them rebuilds File Cleanup's guard and drops rows.
    @State private var exclusions: FolderListModel
    /// The project folders Settings lists (SET-003). Changing them rebuilds File Cleanup's ownership map and Developer
    /// Junk (D-154).
    @State private var projectFolders: FolderListModel
    @State private var navigation = AppNavigation()

    init() {
        let arguments = CommandLine.arguments
        // A UI test starts from default preferences (D-70). Only the debug build's own domain is ever cleared.
        let bundleID = Bundle.main.bundleIdentifier
        // A second launch of this build hands over to the first one before anything is built (SAF-018).
        SingleInstance.yieldToRunningInstance(arguments: arguments, bundleID: bundleID)
        if let domain = AppEnvironment.preferencesToClear(arguments: arguments, bundleID: bundleID) {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment(
                arguments: arguments, settings: UserDefaults.standard.object(forKey:),
                saveExcludedFolders: { UserDefaults.standard.set($0, forKey: AppEnvironment.excludedFoldersKey) },
                saveProjectFolders: { UserDefaults.standard.set($0, forKey: AppEnvironment.projectFoldersKey) },
                bundleID: bundleID, home: .homeDirectory)
        } catch {
            // A UI test passed a bad fixture root, or the build has the wrong bundle ID. Stop rather than scan the real
            // home folder or share another build's data.
            Logger.app.fault("Cannot launch: \(error.description, privacy: .private)")
            fatalError(error.description)
        }
        registry = .standard(
            largeFiles: environment.largeFiles, oldFiles: environment.oldFiles,
            developerJunk: environment.developerJunk, cachesAndLogs: environment.cachesAndLogs)
        pages = SubToolPages(
            largeFiles: environment.largeFiles, oldFiles: environment.oldFiles,
            developerJunk: environment.developerJunk, cachesAndLogs: environment.cachesAndLogs)
        let fileCleanup = FileCleanupModel(
            subTools: registry.subTools, context: environment.context,
            personalFilesScan: environment.personalFilesScan, runPlan: environment.run,
            readFreeSpace: environment.availableSpace, readUsedSpace: environment.usedSpace)
        _fileCleanup = State(initialValue: fileCleanup)
        // Both scans come from the one `Applications`, so a fixture root never reads the real `/Library` (SAF-016).
        let applications = ApplicationsModel(
            context: environment.context, leftoverScan: environment.appLeftovers,
            uninstall: .init(
                applications: environment.applications, runPlan: environment.run,
                readFreeSpace: environment.availableSpace, quitApp: environment.quitApp),
            receiptReader: environment.receiptReader, appScan: environment.applications.scan)
        _applications = State(initialValue: applications)
        _exclusions = State(
            initialValue: FolderListModel(list: environment.excludedFolders) { folders in
                let protection = environment.makeProtection(folders)
                fileCleanup.protect(with: protection)
                applications.protect(with: protection)
            })
        let home = environment.context.home
        _projectFolders = State(
            initialValue: FolderListModel(
                list: environment.projectFolders, accepts: { ProjectFolders.isInsideHome($0, home: home) }
            ) { folders in
                let scope = environment.makeProjectScope(folders)
                fileCleanup.useProjectFolders(scope.developerJunk, ownership: scope.ownership)
            })
        _history = State(
            initialValue: HistoryModel(
                home: environment.context.home, load: environment.loadHistory, runRestore: environment.restore))
    }

    var body: some Scene {
        // One main window: a `WindowGroup` would let File > New Window (⌘N) open a second one that shares the
        // navigation and the selection (TD-13). As the app's first scene, a `Window` quits the app when it is closed
        // (D-99).
        Window(Text(verbatim: "Shuck"), id: "main") {
            ContentView(
                registry: registry, pages: pages, fileCleanup: fileCleanup, applications: applications, history: history
            )
            .environment(navigation)
        }

        // Settings opens in its own window from the app menu (⌘,), not from the sidebar (D-27).
        Settings {
            SettingsView(exclusions: exclusions, projectFolders: projectFolders)
        }
    }
}
