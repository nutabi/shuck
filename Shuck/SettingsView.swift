import SwiftUI
import UniformTypeIdentifiers
import os

/// The Settings window, opened from the app menu (⌘,).
///
/// For now it holds the list of excluded folders (SET-001). Thresholds and project folders follow in M5 (SET-002,
/// SET-003).
struct SettingsView: View {
    let exclusions: ExclusionsModel
    @State private var selection: Set<URL> = []
    @State private var isChoosingFolders = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Excluded folders")
                .font(.headline)
            Text(
                "Shuck never lists, moves or deletes anything inside these folders, or a folder that holds one, in any tool. A folder you remove is scanned again from the next scan on."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            List(exclusions.folders, id: \.self, selection: $selection) { folder in
                Label(folder.path, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder.path)
            }
            .accessibilityLabel("Excluded folders")
            .overlay {
                if exclusions.folders.isEmpty {
                    Text("No folders are excluded.")
                        .foregroundStyle(.secondary)
                }
            }
            // The Delete key removes the selected folders, so the list works from the keyboard.
            .onDeleteCommand(perform: removeSelection)

            HStack {
                Button("Add…") { isChoosingFolders = true }
                    .accessibilityHint("Chooses folders to exclude.")
                Button("Remove", action: removeSelection)
                    .disabled(selection.isEmpty)
                    .accessibilityHint("Takes the selected folders out of the list.")
                Spacer()
            }

            Text("Thresholds and project folders are planned for milestone M5.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 480, height: 380)
        .fileImporter(
            isPresented: $isChoosingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let folders): exclusions.add(folders)
            case .failure(let error):
                Logger.app.error("Cannot choose folders: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func removeSelection() {
        exclusions.remove(Array(selection))
        selection = []
    }
}

#Preview {
    SettingsView(
        exclusions: ExclusionsModel(
            list: ExcludedFolders(stored: ["/Users/someone/Projects/Secret"]) { _ in }, didChange: { _ in }))
}
