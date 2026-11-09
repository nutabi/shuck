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

    var body: some View {
        RunSheet(
            run: confirmation.run,
            runningTitle: Text("Deleting ^[\(confirmation.plan.items.count) item](inflect: true)…"),
            stopHelp: Text("Stop before the next item. Items already deleted stay deleted."),
            failureTitle: Text("Nothing was deleted"),
            failureMessage: Text(
                "Shuck never deletes anything without recording it first, and it couldn't record this run."),
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

    @ViewBuilder private var confirming: some View {
        let count = confirmation.plan.items.count
        Text(
            "Delete ^[\(count) item](inflect: true), \(confirmation.totalBytes, format: .byteCount(style: .file)), permanently?"
        )
        .font(.title2.bold())
        Text("Tools can rebuild these. They don't go to the Trash, so Shuck can't put them back.")
            .foregroundStyle(.secondary)
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
                    Text(item.allocatedSize, format: .byteCount(style: .file))
                        .monospacedDigit()
                }
            }
            .listStyle(.bordered)
        }
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Delete", role: .destructive) { confirmation.start() }
                .disabled(confirmation.plan.items.isEmpty)
        }
    }

    @ViewBuilder private func summary(_ report: RunReport) -> some View {
        let deleted = report.outcomes.filter { if case .done = $0.result { true } else { false } }
        let notDeleted = report.outcomes.filter { if case .done = $0.result { false } else { true } }
        let bytes = deleted.reduce(0) { $0 + $1.item.allocatedSize }
        if notDeleted.isEmpty {
            Text("Deleted ^[\(deleted.count) item](inflect: true)")
                .font(.title2.bold())
        } else {
            Text("Deleted \(deleted.count) of ^[\(report.outcomes.count) item](inflect: true)")
                .font(.title2.bold())
        }
        // The size is the scan's estimate: the measured change in free space comes with M2-T07 (SAF-013).
        Text("About \(bytes, format: .byteCount(style: .file)) was deleted permanently. It is not in the Trash.")
            .foregroundStyle(.secondary)
        if !notDeleted.isEmpty {
            OutcomeList(title: Text("Not deleted"), outcomes: notDeleted, home: home)
        } else {
            Spacer()
        }
    }
}
