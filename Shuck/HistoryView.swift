import ShuckKit
import SwiftUI

/// The History page: every run Shuck logged, newest first, each expanding to its items (HIS-002).
///
/// A run shows its date, area, item count, size, method and status; each item shows what happened to it and whether
/// Restore can put it back (HIS-004). Restore acts on the selected items, or on a run's with "Restore All" (HIS-003,
/// D-68); only items still in the Trash can be selected.
struct HistoryView: View {
    let model: HistoryModel
    let registry: ToolRegistry

    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @State private var expanded: Set<UUID> = []
    /// The trashed paths of the selected items.
    @State private var selection: Set<URL> = []

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
            .sheet(item: restoreSheet) { restore in
                HistoryRestoreSheet(restore: restore, home: model.home)
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
                HistoryErrorText(error: error)
            }
        case .loaded(let history) where history.runs.isEmpty && history.unreadableLineCount == 0:
            ContentUnavailableView(
                "No history yet", systemImage: "clock.arrow.circlepath",
                description: Text(
                    "Everything Shuck removes is listed here. Items moved to the Trash can be put back; deleted ones can't."
                ))
        case .loaded(let history):
            List(selection: $selection) {
                if history.unreadableLineCount > 0 {
                    // No silent failures (SAF-011): lines cut short by a crash are skipped, but not hidden.
                    Label(
                        "^[\(history.unreadableLineCount) line](inflect: true) of the history log couldn't be read.",
                        systemImage: "exclamationmark.triangle")
                }
                ForEach(history.runs) { run in
                    DisclosureGroup(isExpanded: isExpanded(run.id)) {
                        ForEach(run.items.indices, id: \.self) { index in
                            let item = run.items[index]
                            // Only a row with a tag can be selected.
                            if let trashed = item.restorableItem {
                                HistoryItemRow(item: item, home: model.home)
                                    .tag(trashed.trashedURL)
                            } else {
                                HistoryItemRow(item: item, home: model.home)
                            }
                        }
                        // A row of its own: in the run's row, the list would read the button as part of its label.
                        if model.canRestore, !run.restorableItems.isEmpty {
                            HStack {
                                Spacer()
                                Button("Restore All") { restore(run.restorableItems) }
                                    .disabled(model.isRestoring)
                            }
                        }
                    } label: {
                        HistoryRunRow(run: run, area: Self.area(of: run, in: registry))
                    }
                }
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                if model.canRestore {
                    Button("Restore") { restore(Self.items(urls, in: history)) }
                        .disabled(model.isRestoring || Self.items(urls, in: history).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.canRestore {
                    footer(Self.items(selection, in: history))
                }
            }
        }
    }

    /// The selection's total, and Restore for keyboard and VoiceOver users.
    private func footer(_ selected: [TrashedItem]) -> some View {
        HStack(spacing: 12) {
            if selected.isEmpty {
                Text("No items selected")
            } else {
                let bytes = selected.reduce(0) { $0 + ($1.bytes ?? 0) }
                Text("^[\(selected.count) item](inflect: true) selected, \(bytes, format: .byteCount(style: .file))")
            }
            Spacer()
            Button("Restore") { restore(selected) }
                .disabled(selected.isEmpty || model.isRestoring)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func restore(_ items: [TrashedItem]) {
        // Restored items leave the Trash, so their rows can no longer be selected.
        if model.restore(items) != nil { selection.removeAll() }
    }

    /// Shows the restore while it waits, runs and reports; closing the sheet ends it.
    private var restoreSheet: Binding<HistoryRestore?> {
        Binding {
            model.restore
        } set: { restore in
            if restore == nil { model.dismissRestore() }
        }
    }

    /// The items still in the Trash whose trashed paths are in `selection`, in the page's order.
    static func items(_ selection: Set<URL>, in history: HistoryModel.History) -> [TrashedItem] {
        history.runs.flatMap(\.restorableItems).filter { selection.contains($0.trashedURL) }
    }

    private func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding {
            expanded.contains(id)
        } set: { isExpanded in
            if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
        }
    }

    /// The sub-tool or tool that ran, by name. A restore's area is Restore (D-68).
    static func area(of run: HistoryRun, in registry: ToolRegistry) -> String {
        if run.tool == .history { return String(localized: "Restore") }
        if let info = registry.info(run.tool) { return String(localized: info.name) }
        return run.tool.rawValue
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
            OutcomeWording.skipped(detail: detail, operation: item.operation)
        case .failed(let detail):
            OutcomeWording.failed(detail: detail)
        case .interrupted:
            "Interrupted before its outcome was recorded"
        }
    }
}

/// A run's area and method, item count and size, date and status.
private struct HistoryRunRow: View {
    let run: HistoryRun
    let area: String

    var body: some View {
        let status = HistoryView.status(of: run)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(verbatim: area)) · \(OutcomeWording.method(of: run))")
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

/// An item's name and folder, what was done to it, its outcome and its size.
private struct HistoryItemRow: View {
    let item: HistoryRun.Item
    let home: URL

    var body: some View {
        let url = URL(filePath: item.path)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: url.lastPathComponent)
                // Each item says what was done to it: a run may mix methods (HIS-002).
                Text("\(ResultRow.folder(of: url, home: home)) · \(Text(OutcomeWording.method(item.operation)))")
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
