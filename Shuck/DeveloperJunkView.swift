import ShuckKit
import SwiftUI

/// Developer Junk: "What can developer tools rebuild?" So far it lists Xcode's DerivedData, one row per project (DEV-R01,
/// DEV-008), its device support files, one row per version of a platform (DEV-R02), and the simulators' caches, one row
/// for each (DEV-R04), the biggest first. Stale projects, those whose project is gone, every version but the newest and
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
            subTool: subTool, model: model, subtitle: Text("What Xcode and the simulators can build again"),
            notScanned: Text("Scan to list what Xcode can build again. Scanning never removes anything."),
            nothingFound: Text("Nothing Xcode or the simulators can build again"),
            scanHelp: Text("Look for what developer tools can rebuild. Scanning never removes anything.")
        ) { actions in
            List {
                ForEach(rows) { item in
                    ProjectRow(item: item, home: model.home, isSelected: isSelected(item))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer(actions.confirmRebuildable)
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

    private func footer(_ action: ConfirmRebuildable?) -> some View {
        HStack {
            if results.selectedItems.isEmpty {
                Text("No items selected")
            } else {
                Text(
                    "^[\(results.selectedItems.count) item](inflect: true) selected, \(results.selectedBytes, format: .byteCount(style: .file))"
                )
            }
            Spacer()
            if let action {
                Button("Delete…") { action.review() }
                    .disabled(results.selectedItems.isEmpty)
                    .help("Review the totals before deleting the selected build folders.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// One project: a checkbox or the reason it has none, the project's name, why it is listed and its size.
private struct ProjectRow: View {
    let item: ScanItem
    let home: URL
    let isSelected: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            if let reason = item.selection.disabledReason {
                // A symbol and words, not color alone, say why the row cannot be chosen (NFR-A11Y-001).
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .help(Text(reason))
                    .accessibilityHidden(true)
            } else {
                Toggle(isOn: isSelected) {
                    Text(verbatim: name)
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityIdentifier("project-\(name)")
            }
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
            }
            Spacer()
            Text(item.allocatedSize, format: .byteCount(style: .file))
                .monospacedDigit()
        }
    }

    /// A project's name without Xcode's hash, or a device support version with its platform.
    private var name: String {
        guard let url = item.url else { return "" }
        let device = DeviceSupportVersion.name(ofFolder: url)
        return device == url.lastPathComponent ? DerivedDataProject.name(ofFolder: device) : device
    }
}
