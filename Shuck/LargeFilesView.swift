import ShuckKit
import SwiftUI

/// Large Files: "What is taking the most space?" Personal files at or above the minimum size, largest first (LRG-001,
/// LRG-002), grouped by top-level folder unless the user turns grouping off (LRG-003).
///
/// ``SubToolPage`` gives it the toolbar, the scan, the messages and the review sheet.
struct LargeFilesView: View {
    let subTool: LargeFiles
    let model: FileCleanupModel
    let results: PersonalFilesResults
    let registry: ToolRegistry

    /// On until the user turns it off, and remembered in the build's own preferences (SET-004, D-87). UI tests start
    /// with it on: a debug build launched on a fixture root clears its preferences first (D-70).
    @AppStorage("LargeFilesGroupByFolder") private var grouped = true

    var body: some View {
        SubToolPage(
            subTool: subTool, model: model, subtitle: Text("Files of at least \(minimumSize)"),
            notScanned: Text("Scan to list files of at least \(minimumSize). Scanning never removes anything."),
            nothingFound: Text("No files of at least \(minimumSize)"),
            scanHelp: Text("Look for large files. Scanning never removes anything.")
        ) { moveToTrash in
            PersonalFilesTable(results: results, registry: registry, grouped: grouped, moveToTrash: moveToTrash)
        } controls: {
            Toggle("Group by Folder", systemImage: "folder", isOn: $grouped)
                .help("Group files by their top-level folder, such as Downloads or Movies.")
        }
    }

    private var minimumSize: String {
        subTool.minimumSize.formatted(.byteCount(style: .file))
    }
}
