import ShuckKit
import SwiftUI

/// Large Files: "What is taking the most space?" Personal files at or above the minimum size, largest first (LRG-001,
/// LRG-002), grouped by top-level folder unless the user turns grouping off (LRG-003).
///
/// The page scans when it opens if Large Files has not scanned yet, and shows the table only when it has rows (D-61).
/// Move to Trash's review sheet belongs to the page, so its summary stays when a run empties the list (D-77).
struct LargeFilesView: View {
    let subTool: LargeFiles
    let model: FileCleanupModel
    let results: PersonalFilesResults
    let registry: ToolRegistry

    /// On until the user turns it off, and remembered in the build's own preferences (SET-004, D-87). UI tests start
    /// with it on: a debug build launched on a fixture root clears its preferences first (D-70).
    @AppStorage("LargeFilesGroupByFolder") private var grouped = true
    /// The open Move to Trash review, from the table's selection until the user closes the summary.
    @State private var review: TrashReview?

    var body: some View {
        // A ZStack, not a Group: a Group passes its modifiers on to the view inside it, so the sheet would belong to
        // the table and close with it. The ZStack stays while the table gives way to the message.
        ZStack {
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
                // On its own, without the glass capsule the toolbar would otherwise share with the buttons next to it.
                ToolbarItem {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup {
                Toggle("Group by Folder", systemImage: "folder", isOn: $grouped)
                    .help("Group files by their top-level folder, such as Downloads or Movies.")
                Button("Scan", systemImage: "magnifyingglass") {
                    model.scan(subTool)
                }
                .disabled(!model.canScan(subTool))
                .help("Look for large files. Scanning never removes anything.")
            }
        }
        .onAppear {
            model.scanIfNotScanned(subTool)
        }
        .sheet(item: $review) { review in
            TrashReviewSheet(review: review, home: results.home)
        }
    }

    private var minimumSize: String {
        subTool.minimumSize.formatted(.byteCount(style: .file))
    }

    /// "Move to Trash" for the table, or `nil` when the model cannot move anything, as in previews.
    private var moveToTrash: MoveToTrash? {
        model.canMoveToTrash ? MoveToTrash(model: model, subTool: subTool, review: $review) : nil
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
