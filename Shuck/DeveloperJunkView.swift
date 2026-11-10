import ShuckKit
import SwiftUI

/// Developer Junk: "What can developer tools rebuild?" So far it lists Xcode's DerivedData, one row per project (DEV-R01,
/// DEV-008), its device support files, one row per version of a platform (DEV-R02), and the simulators' caches, one row
/// for each (DEV-R04), the biggest first. A tool's rule, such as unavailable simulators (DEV-R03) or npm's cache
/// (DEV-R07), is one row with its exact command and a size estimate. Stale projects, those whose project is gone, every version but the newest and
/// every cache start selected; a row whose app is running shows a note instead of a checkbox (SAF-009, CAC-003).
///
/// Choosing rows only marks them. "Delete…" opens the summary confirmation for the selected rows, with the totals per
/// category and the full list on demand, and nothing is deleted before the user confirms there (SAF-003). ``SubToolPage``
/// gives the page the toolbar, the scan, the messages and the sheet.
struct DeveloperJunkView: View {
    let subTool: DeveloperJunk
    let model: FileCleanupModel
    @Bindable var results: ScanResults

    var body: some View {
        SubToolPage(
            subTool: subTool, model: model,
            subtitle: Text("What Xcode, the simulators and package managers can build again"),
            notScanned: Text("Scan to list what developer tools can build again. Scanning never removes anything."),
            nothingFound: Text("Nothing developer tools can build again"),
            scanHelp: Text("Look for what developer tools can rebuild. Scanning never removes anything.")
        ) { actions in
            List {
                ForEach(rows) { item in
                    ProjectRow(item: item, home: model.home, isSelected: isSelected(item))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RebuildableFooter(
                    results: results, action: actions.confirmRebuildable,
                    help: Text("Review the totals before cleaning up the selected items."))
            }
        }
    }

    /// The biggest first, as Large Files lists its files.
    private var rows: [ScanItem] {
        results.items.sorted { $0.allocatedSize > $1.allocatedSize }
    }

    private func isSelected(_ item: ScanItem) -> Binding<Bool> {
        Binding {
            results.selection.contains(item.target)
        } set: { chosen in
            if chosen { results.selection.insert(item.target) } else { results.selection.remove(item.target) }
        }
    }
}

/// One row: a checkbox or the reason it has none, the name of a project or tool rule, why it is listed and its size.
/// A tool rule's row also shows the exact command that cleaning would run.
private struct ProjectRow: View {
    let item: ScanItem
    let home: URL
    let isSelected: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            SelectionMark(item: item, name: name, identifier: "project-\(name)", isSelected: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                if let reason = item.selection.disabledReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .command(let command) = item.target {
                    // The exact command, as the review shows it (SAF-002).
                    Text(verbatim: command.display)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            SizeText(target: item.target, bytes: item.allocatedSize)
        }
    }

    /// A project's name without Xcode's hash, a device support version with its platform, or a tool rule's name.
    private var name: String {
        guard let url = item.url else { return item.ruleMatch.map { String(localized: $0.rule.name) } ?? "" }
        let device = DeviceSupportVersion.name(ofFolder: url)
        return device == url.lastPathComponent ? DerivedDataProject.name(ofFolder: device) : device
    }
}
