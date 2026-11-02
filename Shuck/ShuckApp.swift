import ShuckKit
import SwiftUI

@main
struct ShuckApp: App {
    private let registry: ToolRegistry
    /// Kept for the app's lifetime, so scan results survive switching between pages.
    @State private var fileCleanup: FileCleanupModel

    init() {
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment(
                arguments: CommandLine.arguments, settings: UserDefaults.standard.object(forKey:))
        } catch {
            // Debug builds only: a UI test passed a bad fixture root. Stop rather than scan the real home folder.
            fatalError(error.description)
        }
        registry = .standard(largeFiles: environment.largeFiles, oldFiles: environment.oldFiles)
        _fileCleanup = State(
            initialValue: FileCleanupModel(
                subTools: registry.subTools, context: environment.context, runPlan: environment.run))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(registry: registry, fileCleanup: fileCleanup)
        }

        // Settings opens in its own window from the app menu (⌘,), not from the sidebar (D-27).
        Settings {
            SettingsView()
        }
    }
}
