import ShuckKit
import SwiftUI

/// Old Files: "What haven't I opened in a long time?" Personal files not opened for at least the period and at least
/// the minimum size (OLD-001), the longest unopened first (OLD-003). The Last Opened column marks the rows where it
/// shows the modified date instead (OLD-002).
///
/// ``SubToolPage`` gives it the toolbar, the scan, the messages and the review sheet.
struct OldFilesView: View {
    let subTool: OldFiles
    let model: FileCleanupModel
    let results: PersonalFilesResults
    let registry: ToolRegistry

    var body: some View {
        SubToolPage(
            subTool: subTool, model: model, subtitle: criteria,
            notScanned: Text(
                "Scan to list files you haven't opened in \(subTool.period). Scanning never removes anything."),
            nothingFound: Text("No files left unopened for \(subTool.period)"),
            scanHelp: Text("Look for files you haven't opened in a long time. Scanning never removes anything.")
        ) { actions in
            PersonalFilesTable(results: results, registry: registry, moveToTrash: actions.moveToTrash)
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
}
