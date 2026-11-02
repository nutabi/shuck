import ShuckKit
import SwiftUI

/// Large Files: "What is taking the most space?" Personal files at or above the minimum size, largest first (LRG-001,
/// LRG-002), grouped by top-level folder unless the user turns grouping off (LRG-003).
///
/// The page scans when it opens if Large Files has not scanned yet, and shows the table only when it has rows (D-61).
struct LargeFilesView: View {
    let subTool: LargeFiles
    let model: FileCleanupModel
    let results: PersonalFilesResults
    let registry: ToolRegistry

    /// On at every launch. Not stored, so UI tests that turn it off write nothing to the real preferences.
    @State private var grouped = true

    var body: some View {
        Group {
            if results.rows.isEmpty {
                emptyState
            } else {
                PersonalFilesTable(
                    results: results, registry: registry, grouped: grouped, moveToTrash: moveToTrash)
            }
        }
        .navigationTitle(Text(subTool.info.name))
        .navigationSubtitle(Text("Files of at least \(minimumSize)"))
        .toolbar {
            if model.state(of: subTool.id) == .scanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Scanning")
            }
            Toggle("Group by Folder", systemImage: "folder", isOn: $grouped)
                .help("Group files by their top-level folder, such as Downloads or Movies.")
            Button("Scan", systemImage: "magnifyingglass") {
                model.scan(subTool)
            }
            .disabled(!model.canScan(subTool))
            .help("Look for large files. Scanning never removes anything.")
        }
        .onAppear {
            model.scanIfNotScanned(subTool)
        }
    }

    private var minimumSize: String {
        subTool.minimumSize.formatted(.byteCount(style: .file))
    }

    /// "Move to Trash" for the table, or `nil` when the model cannot move anything, as in previews.
    private var moveToTrash: MoveToTrash? {
        model.canMoveToTrash ? MoveToTrash(model: model, subTool: subTool) : nil
    }

    /// What the page shows while there are no rows.
    @ViewBuilder private var emptyState: some View {
        switch model.state(of: subTool.id) {
        case .notScanned:
            ContentUnavailableView {
                Label("Not scanned yet", systemImage: subTool.info.symbolName)
            } description: {
                Text("Scan to list files of at least \(minimumSize). Scanning never removes anything.")
            }
        case .scanning:
            ProgressView("Scanning…")
        case .scanned:
            ContentUnavailableView("No files of at least \(minimumSize)", systemImage: "checkmark.circle")
        }
    }
}
