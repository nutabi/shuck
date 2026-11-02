import ShuckKit
import SwiftUI

/// The History page: every run Shuck logged, newest first, each expanding to its items (HIS-002).
///
/// A run shows its date, area, item count, size, method and status; each item shows what happened to it and whether
/// Restore can put it back (HIS-004). Restore itself comes in the next pull request.
struct HistoryView: View {
    let model: HistoryModel
    let registry: ToolRegistry

    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @State private var expanded: Set<UUID> = []

    var body: some View {
        content
            .navigationTitle("History")
            .task {
                // A run the summary asked to show is the newest, so it is at the top.
                if let run = navigation?.revealedRun {
                    expanded.insert(run)
                    navigation?.revealedRun = nil
                }
                await model.reload()
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed(let error):
            ContentUnavailableView {
                Label("Can't read the history log", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: String(describing: error))
            }
        case .loaded(let history) where history.runs.isEmpty && history.unreadableLineCount == 0:
            ContentUnavailableView(
                "No history yet", systemImage: "clock.arrow.circlepath",
                description: Text("Everything Shuck moves to the Trash is listed here, with a way to put it back."))
        case .loaded(let history):
            List {
                if history.unreadableLineCount > 0 {
                    // No silent failures (SAF-011): lines cut short by a crash are skipped, but not hidden.
                    Label(
                        "^[\(history.unreadableLineCount) line](inflect: true) of the history log couldn't be read.",
                        systemImage: "exclamationmark.triangle")
                }
                ForEach(history.runs) { run in
                    DisclosureGroup(isExpanded: isExpanded(run.id)) {
                        ForEach(run.items.indices, id: \.self) { index in
                            HistoryItemRow(item: run.items[index], home: model.home)
                        }
                    } label: {
                        HistoryRunRow(run: run, area: Self.area(of: run, in: registry))
                    }
                }
            }
        }
    }

    private func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding {
            expanded.contains(id)
        } set: { isExpanded in
            if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
        }
    }

    /// The sub-tool or tool that ran, by name. A restore's area is Restore (D-68).
    static func area(of run: HistoryRun, in registry: ToolRegistry) -> LocalizedStringResource {
        if run.tool == .history { return "Restore" }
        return registry.info(run.tool)?.name ?? "\(run.tool.rawValue)"
    }

    static func method(_ operation: HistoryRecord.Operation) -> LocalizedStringResource {
        switch operation {
        case .trash: "Moved to the Trash"
        case .delete: "Deleted permanently"
        case .tool: "Cleaned by its tool"
        case .launchctl: "Changed with launchctl"
        case .restore: "Moved back from the Trash"
        }
    }

    /// How a run ended, in words and with a symbol, never by color alone (NFR-A11Y-001).
    static func status(of run: HistoryRun) -> (text: LocalizedStringResource, symbol: String) {
        if run.items.contains(where: { $0.outcome == .interrupted }) {
            ("Interrupted", "exclamationmark.triangle")
        } else if run.succeededCount == run.items.count {
            ("Completed", "checkmark.circle")
        } else {
            ("\(run.succeededCount) of \(run.items.count) done", "exclamationmark.circle")
        }
    }

    /// What happened to an item and, if it changed, whether Restore can put it back (SAF-011, HIS-004).
    static func status(of item: HistoryRun.Item) -> LocalizedStringResource {
        switch item.outcome {
        case .succeeded:
            switch item.restorability {
            case .restorable?: "In the Trash"
            case .trashEmptied?: "Not restorable (Trash emptied)"
            case .notAccessible?: "Not accessible"
            case .unknownLocation?: "Not restorable (location unknown)"
            case .restored?: "Restored"
            case .permanent?: "Not restorable"
            case .reversedByOppositeAction?: "Reversed by the opposite action"
            // A restore: the item is back.
            case nil: "Moved back"
            }
        case .skipped(let detail):
            "Skipped: \(skipReason(detail))"
        case .failed(let detail?):
            "Failed: \(detail)"
        case .failed(nil):
            "Failed"
        case .interrupted:
            "Interrupted before its outcome was recorded"
        }
    }

    /// A logged skip reason in words. The executors log the reason's case name, followed by its values in brackets.
    static func skipReason(_ detail: String?) -> LocalizedStringResource {
        switch detail?.prefix(while: { $0 != "(" }) {
        case "missing": "no longer there"
        case "changed": "changed since the scan"
        case "rejected": "failed a safety check"
        case "cancelled": "stopped before it was acted on"
        case "historyUnavailable": "the history log stopped working"
        case "unsupportedMethod": "method not supported"
        case "originalTaken": "its original place is taken"
        case "notInTrash": "not in the Trash"
        default: "\(detail ?? "")"
        }
    }
}

/// A run's area and method, item count and size, date and status.
private struct HistoryRunRow: View {
    let run: HistoryRun
    let area: LocalizedStringResource

    var body: some View {
        let status = HistoryView.status(of: run)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(area)) · \(Text(HistoryView.method(run.operation)))")
                    .font(.headline)
                // The size of what changed: a skipped item changed nothing (SAF-013).
                Text(
                    "^[\(run.items.count) item](inflect: true), \(run.succeededBytes, format: .byteCount(style: .file))"
                )
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(run.started, format: .dateTime)
                Label {
                    Text(status.text)
                } icon: {
                    Image(systemName: status.symbol)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// An item's name and folder, its outcome and its size.
private struct HistoryItemRow: View {
    let item: HistoryRun.Item
    let home: URL

    var body: some View {
        let url = URL(filePath: item.path)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: url.lastPathComponent)
                Text(verbatim: ResultRow.folder(of: url, home: home))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(HistoryView.status(of: item))
                .foregroundStyle(.secondary)
            if let bytes = item.bytes {
                Text(bytes, format: .byteCount(style: .file))
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
    }
}

#Preview {
    HistoryView(
        model: HistoryModel(home: .temporaryDirectory) { .init(runs: [], unreadableLineCount: 0) },
        registry: .standard)
}
