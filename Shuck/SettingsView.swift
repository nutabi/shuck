import SwiftUI
import UniformTypeIdentifiers
import os

/// The Settings window, opened from the app menu (⌘,).
///
/// For now it holds the developer project folders (SET-003) and the list of excluded folders (SET-001). Thresholds, the
/// rest of the project-folder settings and Clear History follow in M5 (SET-002, SET-007).
struct SettingsView: View {
    let exclusions: FolderListModel
    let projectFolders: FolderListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FolderListSection(
                model: projectFolders, heading: "Project folders",
                explanation:
                    "Shuck looks for node_modules folders in these folders, up to four levels down, and lists those of projects you haven't changed for 30 days. A project folder must be inside your home folder. A change applies from the next scan on.",
                emptyText: "No project folders.", name: "project-folders",
                addHint: "Chooses folders that hold your projects.",
                removeHint: "Takes the selected folders out of the list.",
                refusal: { names in
                    Text("Not added: \(names). A project folder must be inside your home folder.")
                })
            FolderListSection(
                model: exclusions, heading: "Excluded folders",
                explanation:
                    "Shuck never lists, moves or deletes anything inside these folders, or a folder that holds one, in any tool. A folder you remove is scanned again from the next scan on.",
                emptyText: "No folders are excluded.", name: "excluded-folders",
                addHint: "Chooses folders to exclude.", removeHint: "Takes the selected folders out of the list.")
            Text("Thresholds are planned for milestone M5.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520, height: 600)
    }
}

/// One list of folders in Settings: a heading, a sentence, the folders, and Add… and Remove (SET-001, SET-003).
///
/// Both lists use it, so they look and work alike. `name` tells the two apart in the accessibility tree: each control's
/// identifier starts with it, since two buttons called "Add…" would otherwise be one query.
private struct FolderListSection: View {
    let model: FolderListModel
    let heading: LocalizedStringKey
    let explanation: LocalizedStringKey
    let emptyText: LocalizedStringKey
    let name: String
    let addHint: LocalizedStringKey
    let removeHint: LocalizedStringKey
    /// What to say about folders that were not added, given their names, or `nil` if the list adds anything.
    var refusal: ((String) -> Text)?

    @State private var selection: Set<URL> = []
    @State private var isChoosingFolders = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.headline)
            Text(explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(model.folders, id: \.self, selection: $selection) { folder in
                Label(folder.path, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder.path)
            }
            .accessibilityLabel(heading)
            .accessibilityIdentifier("\(name)-list")
            .overlay {
                if model.folders.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }
            }
            // The Delete key removes the selected folders, so the list works from the keyboard.
            .onDeleteCommand(perform: removeSelection)

            if let refusal, !model.refused.isEmpty {
                // A symbol and words, not color alone (NFR-A11Y-001).
                Label {
                    refusal(model.refused.map(\.lastPathComponent).joined(separator: ", "))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.callout)
                .accessibilityIdentifier("\(name)-refusal")
            }

            HStack {
                Button("Add…") { isChoosingFolders = true }
                    .accessibilityHint(addHint)
                    .accessibilityIdentifier("\(name)-add")
                Button("Remove", action: removeSelection)
                    .disabled(selection.isEmpty)
                    .accessibilityHint(removeHint)
                    .accessibilityIdentifier("\(name)-remove")
                Spacer()
            }
        }
        .fileImporter(
            isPresented: $isChoosingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let folders): model.add(folders)
            case .failure(let error):
                Logger.app.error("Cannot choose folders: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func removeSelection() {
        model.remove(Array(selection))
        selection = []
    }
}

#Preview {
    SettingsView(
        exclusions: FolderListModel(
            list: FolderList(stored: ["/Users/someone/Projects/Secret"]) { _ in }, didChange: { _ in }),
        projectFolders: FolderListModel(
            list: FolderList(stored: ["/Users/someone/Developer"]) { _ in }, didChange: { _ in }))
}
