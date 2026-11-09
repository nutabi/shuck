import ShuckKit
import SwiftUI

/// Developer Junk: "What can developer tools rebuild?" So far it lists Xcode's DerivedData, one row per project, the
/// biggest first (DEV-R01, DEV-008). Stale projects and those whose project is gone start selected; a row whose app is
/// running shows a note instead of a checkbox (SAF-009, CAC-003).
///
/// Choosing rows only marks them. Deleting them comes with the summary confirmation (M2-T06), so this page has no
/// action button yet (D-113). ``SubToolPage`` gives it the toolbar, the scan and the messages.
struct DeveloperJunkView: View {
    let subTool: DeveloperJunk
    let model: FileCleanupModel
    @Bindable var results: ScanResults

    var body: some View {
        SubToolPage(
            subTool: subTool, model: model, subtitle: Text("Xcode build folders, one for each project"),
            notScanned: Text("Scan to list what Xcode can build again. Scanning never removes anything."),
            nothingFound: Text("No Xcode build folders found"),
            scanHelp: Text("Look for what developer tools can rebuild. Scanning never removes anything.")
        ) { _ in
            List {
                ForEach(rows) { item in
                    ProjectRow(item: item, home: model.home, isSelected: isSelected(item))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
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

    private var footer: some View {
        HStack {
            if results.selectedItems.isEmpty {
                Text("No items selected")
            } else {
                Text(
                    "^[\(results.selectedItems.count) item](inflect: true) selected, \(results.selectedBytes, format: .byteCount(style: .file))"
                )
            }
            Spacer()
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

    private var name: String {
        DerivedDataProject.name(ofFolder: item.url?.lastPathComponent ?? "")
    }
}
