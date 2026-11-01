import ShuckKit
import SwiftUI

@main
struct ShuckApp: App {
    /// Kept for the app's lifetime, so scan results survive switching between pages.
    @State private var fileCleanup = FileCleanupModel(
        subTools: ToolRegistry.standard.subTools,
        // The ownership map compares paths with symlinks resolved (D-53).
        context: ScanContext(home: URL.homeDirectory.resolvingSymlinksInPath()))

    var body: some Scene {
        WindowGroup {
            ContentView(registry: .standard, fileCleanup: fileCleanup)
        }

        // Settings opens in its own window from the app menu (⌘,), not from the sidebar (D-27).
        Settings {
            SettingsView()
        }
    }
}
