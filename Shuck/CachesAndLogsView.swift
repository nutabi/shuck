import ShuckKit
import SwiftUI

/// Caches & Logs: "Which caches and logs can go?" One section per app, the biggest first, each with its caches, its logs
/// and its sandbox's caches (CAC-001, CAC-002). A cache or log nothing has changed for a while starts selected (CAC-005);
/// a row whose app is running shows a note instead of a checkbox (CAC-003).
///
/// Choosing rows only marks them. "Delete…" opens the summary confirmation, with the totals per category (Caches, Logs,
/// App Container Caches) and the full list on demand, and nothing is deleted before the user confirms there (CAC-006,
/// SAF-003). A cache or log folder keeps its place and loses what is inside it (CAC-004). ``SubToolPage`` gives the page
/// the toolbar, the scan, the messages and the sheet.
struct CachesAndLogsView: View {
    let subTool: CachesAndLogs
    let model: FileCleanupModel
    @Bindable var results: ScanResults

    var body: some View {
        SubToolPage(
            subTool: subTool, model: model, subtitle: Text("What apps can create again"),
            notScanned: Text("Scan to list the caches and logs your apps keep. Scanning never removes anything."),
            nothingFound: Text("No caches or logs to clear"),
            scanHelp: Text("Look for caches and logs. Scanning never removes anything.")
        ) { actions in
            List {
                ForEach(AppGroup.groups(of: results.items)) { group in
                    Section {
                        ForEach(group.items) { item in
                            CacheRow(item: item, home: model.home, isSelected: isSelected(item))
                        }
                    } header: {
                        GroupHeader(group: group)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Notes(notAccessible: results.notAccessibleCount > 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RebuildableFooter(
                    results: results, action: actions.confirmRebuildable,
                    help: Text("Review the totals before deleting the selected caches and logs."))
            }
        }
    }

    private func isSelected(_ item: ScanItem) -> Binding<Bool> {
        Binding {
            results.selection.contains(item.target)
        } set: { chosen in
            if chosen { results.selection.insert(item.target) } else { results.selection.remove(item.target) }
        }
    }
}

/// What the page tells before its list: macOS clears caches too, so the space may come back (CAC-007, [S5]), and, if
/// macOS kept the scan out of some folders, how to let it in (SAF-012, ONB-002).
private struct Notes: View {
    let notAccessible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(
                    "macOS also clears caches and logs that are safe to delete when it needs space, so the space you free here may not last."
                )
            } icon: {
                Image(systemName: "info.circle")
            }
            if notAccessible {
                Label {
                    Text(
                        "Not accessible: macOS kept Shuck out of some folders, such as sandboxed apps' caches. Allow Full Disk Access for Shuck in System Settings, then scan again to list them."
                    )
                } icon: {
                    Image(systemName: "lock")
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// An app's name and the size of everything listed for it.
private struct GroupHeader: View {
    let group: AppGroup

    var body: some View {
        HStack {
            Text(verbatim: group.name)
            Spacer()
            Text(group.totalSize, format: .byteCount(style: .file))
                .monospacedDigit()
        }
    }
}

/// One cache, log or container's caches: a checkbox or the reason it has none, what it is, where it is, why it is listed
/// and its size.
private struct CacheRow: View {
    let item: ScanItem
    let home: URL
    let isSelected: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            SelectionMark(
                item: item, name: "\(String(localized: item.category.name)), \(path)", identifier: "cache-\(path)",
                isSelected: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.category.name)
                Text(verbatim: path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// Where the item is, from the home folder: `~/Library/Caches/com.example.Notes`.
    private var path: String {
        guard let url = item.url else { return "" }
        return ResultRow.folder(of: url, home: home) + "/" + url.lastPathComponent
    }
}
