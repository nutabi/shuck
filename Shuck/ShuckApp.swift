import ShuckKit
import SwiftUI
import os

@main
struct ShuckApp: App {
    private let registry: ToolRegistry
    private let pages: SubToolPages
    /// Kept for the app's lifetime, so scan results survive switching between pages.
    @State private var fileCleanup: FileCleanupModel
    @State private var history: HistoryModel
    @State private var navigation = AppNavigation()

    init() {
        let arguments = CommandLine.arguments
        // A UI test starts from default preferences (D-70). Only the debug build's own domain is ever cleared.
        let bundleID = Bundle.main.bundleIdentifier
        if let domain = AppEnvironment.preferencesToClear(arguments: arguments, bundleID: bundleID) {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment(
                arguments: arguments, settings: UserDefaults.standard.object(forKey:), bundleID: bundleID,
                home: .homeDirectory)
        } catch {
            // A UI test passed a bad fixture root, or the build has the wrong bundle ID. Stop rather than scan the real
            // home folder or share another build's data.
            Logger.app.fault("Cannot launch: \(error.description, privacy: .private)")
            fatalError(error.description)
        }
        registry = .standard(largeFiles: environment.largeFiles, oldFiles: environment.oldFiles)
        pages = SubToolPages(largeFiles: environment.largeFiles, oldFiles: environment.oldFiles)
        _fileCleanup = State(
            initialValue: FileCleanupModel(
                subTools: registry.subTools, context: environment.context,
                personalFilesScan: environment.personalFilesScan, runPlan: environment.run))
        _history = State(
            initialValue: HistoryModel(
                home: environment.context.home, load: environment.loadHistory, runRestore: environment.restore))
    }

    var body: some Scene {
        // One main window: a `WindowGroup` would let File > New Window (⌘N) open a second one that shares the
        // navigation and the selection (TD-13). The Window menu reopens it after it is closed.
        Window(Text(verbatim: "Shuck"), id: "main") {
            ContentView(registry: registry, pages: pages, fileCleanup: fileCleanup, history: history)
                .environment(navigation)
        }

        // Settings opens in its own window from the app menu (⌘,), not from the sidebar (D-27).
        Settings {
            SettingsView()
        }
    }
}
