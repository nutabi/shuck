import ShuckExecution
import ShuckKit
import SwiftUI

/// The sheet for one summary confirmation: the totals per category and the way to the full list, then progress, then the
/// summary (SAF-003, SAF-011).
///
/// Nothing is deleted until the user presses "Delete" in the confirmation, whose title states the count and total size.
/// That button is not the default, so Return alone never deletes anything. The sheet says that deleting cannot be
/// undone (SAF-004), since the items do not go to the Trash.
struct SummaryConfirmationSheet: View {
    let confirmation: SummaryConfirmation
    /// The scanned home folder, shown as `~` in folder paths.
    let home: URL

    @Environment(\.dismiss) private var dismiss
    /// `nil` in previews, which then offer no link to History.
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    /// Whether the full item list is open under the totals (SAF-003).
    @State private var showsItems = false
    /// Whether the second confirmation for oversized items is on screen (SAF-015).
    @State private var asksAboutOversized = false

    var body: some View {
        RunSheet(
            run: confirmation.run,
            runningTitle: runsTools
                ? Text("Cleaning up ^[\(confirmation.plan.items.count) item](inflect: true)…")
                : Text("Deleting ^[\(confirmation.plan.items.count) item](inflect: true)…"),
            stopHelp: runsTools
                ? Text("Stop before the next item. Items already cleaned up stay that way.")
                : Text("Stop before the next item. Items already deleted stay deleted."),
            failureTitle: runsTools ? Text("Nothing was cleaned up") : Text("Nothing was deleted"),
            failureMessage: Text(
                "Shuck never changes anything without recording it first, and it couldn't record this run."),
            waiting: { confirming },
            summary: { summary($0) },
            summaryActions: { report in
                if let navigation {
                    // Where every item's outcome stays (HIS-002).
                    Button("Show in History") {
                        navigation.showHistory(revealing: report.run)
                        dismiss()
                    }
                }
            })
    }

    private var runsTools: Bool { confirmation.runsTools }

    @ViewBuilder private var confirming: some View {
        let count = confirmation.plan.items.count
        let size = confirmation.totalBytes
        if runsTools {
            // Without an estimate for any item, there is no size to state.
            if size > 0 {
                Text("Clean up ^[\(count) item](inflect: true), up to \(size, format: .byteCount(style: .file))?")
                    .font(.title2.bold())
            } else {
                Text("Clean up ^[\(count) item](inflect: true)?")
                    .font(.title2.bold())
            }
            Text(
                "Tools can rebuild these. Items that are deleted don't go to the Trash, and a tool removes its own data with its own command, so Shuck can't put either back. A tool's size is an estimate."
            )
            .foregroundStyle(.secondary)
        } else {
            Text("Delete ^[\(count) item](inflect: true), \(size, format: .byteCount(style: .file)), permanently?")
                .font(.title2.bold())
            Text("Tools can rebuild these. They don't go to the Trash, so Shuck can't put them back.")
                .foregroundStyle(.secondary)
        }
        List(confirmation.categoryTotals) { total in
            HStack {
                Text(total.category.name)
                Spacer()
                Text("^[\(total.count) item](inflect: true)")
                    .foregroundStyle(.secondary)
                Text(total.bytes, format: .byteCount(style: .file))
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .listStyle(.bordered)
        .frame(maxHeight: showsItems ? 120 : nil)
        Button(showsItems ? "Hide All Items" : "Show All Items") { showsItems.toggle() }
            .accessibilityIdentifier("toggle-item-list")
        if showsItems {
            List(confirmation.plan.items) { item in
                ItemRow(target: item.target, home: home) {
                    SizeText(target: item.target, bytes: item.allocatedSize, snapshot: item.snapshot)
                }
            }
            .listStyle(.bordered)
        }
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(runsTools ? "Clean Up" : "Delete", role: .destructive) {
                if confirmation.needsSecondConfirmation {
                    asksAboutOversized = true
                } else {
                    confirmation.start()
                }
            }
            .disabled(confirmation.plan.items.isEmpty)
        }
        .alert(oversizedTitle, isPresented: $asksAboutOversized) {
            Button("Cancel", role: .cancel) {}
            Button(runsTools ? "Clean Up Anyway" : "Delete Anyway", role: .destructive) {
                confirmation.confirmedOversized = true
                confirmation.start()
            }
        } message: {
            oversizedMessage
        }
    }

    /// The second confirmation's title, which names how many items are oversized (SAF-015).
    private var oversizedTitle: Text {
        let count = confirmation.oversized.count
        return runsTools
            ? Text("Clean up ^[\(count) very large item](inflect: true)?")
            : Text("Delete ^[\(count) very large item](inflect: true)?")
    }

    /// Which items are oversized and why that matters: each is more than a quarter of the space in use on this Mac, an
    /// unusual size for something rebuildable (SAF-015, D-144).
    private var oversizedMessage: Text {
        let names = confirmation.oversized.map { name(of: $0.target) }.formatted(.list(type: .and))
        let threshold = confirmation.threshold?.bytes ?? 0
        if confirmation.oversized.count == 1 {
            return Text(
                "\(names) is more than a quarter of the space in use on this Mac, \(threshold, format: .byteCount(style: .file)). Check that you meant to include it: Shuck can't put it back."
            )
        }
        return Text(
            "Each of these is more than a quarter of the space in use on this Mac, \(threshold, format: .byteCount(style: .file)): \(names). Check that you meant to include them: Shuck can't put them back."
        )
    }

    /// An item as the second confirmation names it: a file by its path from the home folder, a tool by its command.
    private func name(of target: ItemTarget) -> String {
        switch target {
        case .path(let url): ResultRow.folder(of: url, home: home) + "/" + url.lastPathComponent
        case .command(let command): command.commandLine
        }
    }

    @ViewBuilder private func summary(_ report: RunReport) -> some View {
        let deleted = report.outcomes.filter { if case .done = $0.result { true } else { false } }
        let notDeleted = report.outcomes.filter { if case .done = $0.result { false } else { true } }
        // A tool item's folder is measured around its run, so its removal is no estimate (D-184).
        let bytes = deleted.reduce(0) { $0 + ($1.removedBytes ?? $1.item.allocatedSize) }
        let measured = !deleted.isEmpty && deleted.allSatisfy { $0.removedBytes != nil }
        if runsTools {
            if notDeleted.isEmpty {
                Text("Cleaned up ^[\(deleted.count) item](inflect: true)")
                    .font(.title2.bold())
            } else {
                Text("Cleaned up \(deleted.count) of ^[\(report.outcomes.count) item](inflect: true)")
                    .font(.title2.bold())
            }
            if measured && bytes > 0 {
                Text(
                    "\(bytes, format: .byteCount(style: .file)) was removed from the tool's cache. It is not in the Trash."
                )
                .foregroundStyle(.secondary)
            } else if measured {
                Text("Nothing was removed from the tool's cache.")
                    .foregroundStyle(.secondary)
            } else if bytes > 0 {
                Text("Up to \(bytes, format: .byteCount(style: .file)) was removed. It is not in the Trash.")
                    .foregroundStyle(.secondary)
            } else {
                Text("What the tool removed is not in the Trash.")
                    .foregroundStyle(.secondary)
            }
        } else {
            if notDeleted.isEmpty {
                Text("Deleted ^[\(deleted.count) item](inflect: true)")
                    .font(.title2.bold())
            } else {
                Text("Deleted \(deleted.count) of ^[\(report.outcomes.count) item](inflect: true)")
                    .font(.title2.bold())
            }
            // The size is the scan's estimate; the measured change follows it (SAF-013).
            Text("About \(bytes, format: .byteCount(style: .file)) was deleted permanently. It is not in the Trash.")
                .foregroundStyle(.secondary)
        }
        if let change = confirmation.freeSpace {
            FreeSpaceText(change: change)
        }
        if !notDeleted.isEmpty {
            OutcomeList(
                title: runsTools ? Text("Not cleaned up") : Text("Not deleted"), outcomes: notDeleted, home: home)
        } else {
            Spacer()
        }
    }
}
