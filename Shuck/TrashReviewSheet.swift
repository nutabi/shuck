import ShuckExecution
import ShuckKit
import SwiftUI

/// The sheet for one "Move to Trash": the itemized review and its confirmation, then progress, then the summary
/// (SAF-002, SAF-011).
///
/// Nothing moves until the user presses "Move to Trash" in the review, whose title states the count and total size.
/// That button is not the default, so Return alone never moves anything.
struct TrashReviewSheet: View {
    let review: TrashReview
    /// The scanned home folder, shown as `~` in folder paths.
    let home: URL

    @Environment(\.dismiss) private var dismiss
    /// `nil` in previews, which then offer no link to History.
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    var body: some View {
        RunSheet(
            run: review.run,
            runningTitle: Text("Moving ^[\(review.plan.items.count) item](inflect: true) to the Trash…"),
            stopHelp: Text("Stop before the next item. Items already moved stay in the Trash."),
            failureTitle: Text("Nothing was moved"),
            failureMessage: Text(
                "Shuck never moves anything without recording it first, and it couldn't record this run."),
            waiting: { reviewing },
            summary: { summary($0) },
            summaryActions: { report in
                if let navigation {
                    // Where every item's outcome stays, and where Restore puts things back (HIS-002).
                    Button("Show in History") {
                        navigation.showHistory(revealing: report.run)
                        dismiss()
                    }
                }
            })
    }

    @ViewBuilder private var reviewing: some View {
        let count = review.plan.items.count
        Text(
            "Move ^[\(count) item](inflect: true), \(review.totalBytes, format: .byteCount(style: .file)), to the Trash?"
        )
        .font(.title2.bold())
        Text("Shuck records where each item goes, so it can put it back.")
            .foregroundStyle(.secondary)
        if !review.synced.isEmpty {
            // The Trash keeps the item restorable on this Mac, but iCloud removes it from the user's other devices
            // (D-129). The rows say which items are synced.
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "exclamationmark.icloud")
                    .accessibilityHidden(true)
                syncedWarning
            }
        }
        List(review.plan.items) { item in
            ItemRow(target: item.target, home: home) {
                if let url = item.url, review.synced.contains(url) { SyncedMark() }
                SizeText(target: item.target, bytes: item.allocatedSize, snapshot: item.snapshot)
            }
        }
        .listStyle(.bordered)
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Move to Trash", role: .destructive) { review.start() }
                .disabled(review.plan.items.isEmpty)
        }
    }

    private var syncedWarning: Text {
        let count = review.synced.count
        return count == 1
            ? Text("1 item is synced with iCloud. Moving it to the Trash also removes it from your other devices.")
            : Text(
                """
                \(count) items are synced with iCloud. Moving them to the Trash also removes them from your other \
                devices.
                """)
    }

    @ViewBuilder private func summary(_ report: RunReport) -> some View {
        let moved = report.outcomes.filter { if case .done = $0.result { true } else { false } }
        let notMoved = report.outcomes.filter { if case .done = $0.result { false } else { true } }
        let bytes = moved.reduce(0) { $0 + $1.item.allocatedSize }
        if notMoved.isEmpty {
            Text("Moved ^[\(moved.count) item](inflect: true) to the Trash")
                .font(.title2.bold())
        } else {
            Text("Moved \(moved.count) of ^[\(report.outcomes.count) item](inflect: true) to the Trash")
                .font(.title2.bold())
        }
        // Moving to the Trash frees nothing yet (SAF-013).
        Text("\(bytes, format: .byteCount(style: .file)) is in the Trash. The space is freed when you empty the Trash.")
            .foregroundStyle(.secondary)
        if let change = review.freeSpace {
            FreeSpaceText(change: change)
        }
        if !notMoved.isEmpty {
            OutcomeList(title: Text("Not moved"), outcomes: notMoved, home: home)
        } else {
            Spacer()
        }
    }
}
