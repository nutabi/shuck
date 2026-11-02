import ShuckKit
import SwiftUI

/// Old Files: "What haven't I opened in a long time?" Personal files not opened for at least the period and at least
/// the minimum size (OLD-001), the longest unopened first (OLD-003). The Last Opened column marks the rows where it
/// shows the modified date instead (OLD-002).
///
/// The page scans when it opens if Old Files has not scanned yet, and shows the table only when it has rows (D-61).
struct OldFilesView: View {
    let subTool: OldFiles
    let model: FileCleanupModel
    let results: PersonalFilesResults
    let registry: ToolRegistry

    var body: some View {
        Group {
            if results.rows.isEmpty {
                emptyState
            } else {
                PersonalFilesTable(results: results, registry: registry, moveToTrash: moveToTrash)
            }
        }
        .navigationTitle(Text(subTool.info.name))
        .navigationSubtitle(criteria)
        .toolbar {
            if model.state(of: subTool.id) == .scanning {
                // On its own, without the glass capsule the toolbar would otherwise share with the buttons next to it.
                ToolbarItem {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup {
                Button("Scan", systemImage: "magnifyingglass") {
                    model.scan(subTool)
                }
                .disabled(!model.canScan(subTool))
                .help("Look for files you haven't opened in a long time. Scanning never removes anything.")
            }
        }
        .onAppear {
            model.scanIfNotScanned(subTool)
        }
    }

    /// Which files the page lists. A minimum of 0 lists files of any size (OLD-001).
    private var criteria: Text {
        if subTool.minimumSize == 0 {
            Text("Not opened in \(subTool.period)")
        } else {
            Text("Not opened in \(subTool.period), at least \(subTool.minimumSize.formatted(.byteCount(style: .file)))")
        }
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
                Text("Scan to list files you haven't opened in \(subTool.period). Scanning never removes anything.")
            }
        case .scanning:
            ProgressView("Scanning…")
        case .scanned:
            ContentUnavailableView("No files left unopened for \(subTool.period)", systemImage: "checkmark.circle")
        }
    }
}
