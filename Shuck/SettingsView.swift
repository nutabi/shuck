import SwiftUI

/// The Settings window, opened from the app menu (⌘,).
///
/// Placeholder until M5 adds exclusions, thresholds and project folders (SET-001 to SET-003).
struct SettingsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Settings", systemImage: "gearshape")
        } description: {
            Text("Exclusions, thresholds and project folders.")
        } actions: {
            Text("Planned for milestone M5.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 260)
    }
}

#Preview {
    SettingsView()
}
