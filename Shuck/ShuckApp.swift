import SwiftUI

@main
struct ShuckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        // Settings opens in its own window from the app menu (⌘,), not from the sidebar (D-27).
        Settings {
            SettingsView()
        }
    }
}
