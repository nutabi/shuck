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
        VStack(alignment: .leading, spacing: 12) {
            switch review.phase {
            case .reviewing:
                reviewing
            case .running:
                running
            case .finished(let report):
                summary(report)
            case .failed(let error):
                failure(error)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 440)
        // A run ends with a report; the sheet stays until the user has seen it (SAF-011).
        .interactiveDismissDisabled(review.phase == .running)
    }

    @ViewBuilder private var reviewing: some View {
        let count = review.plan.items.count
        Text(
            "Move ^[\(count) item](inflect: true), \(review.totalBytes, format: .byteCount(style: .file)), to the Trash?"
        )
        .font(.title2.bold())
        Text("Shuck records where each item goes, so it can put it back.")
            .foregroundStyle(.secondary)
        List(review.plan.items, id: \.url) { item in
            ItemRow(url: item.url, home: home) {
                Text(item.snapshot.allocatedSize, format: .byteCount(style: .file))
                    .monospacedDigit()
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

    @ViewBuilder private var running: some View {
        Text("Moving ^[\(review.plan.items.count) item](inflect: true) to the Trash…")
            .font(.title2.bold())
        Spacer()
        ProgressView()
            .frame(maxWidth: .infinity)
        Spacer()
        HStack {
            Spacer()
            Button("Stop") { review.stop() }
                .keyboardShortcut(.cancelAction)
                .help("Stop before the next item. Items already moved stay in the Trash.")
        }
    }

    @ViewBuilder private func summary(_ report: RunReport) -> some View {
        let moved = report.outcomes.filter { if case .done = $0.result { true } else { false } }
        let notMoved = report.outcomes.filter { if case .done = $0.result { false } else { true } }
        let bytes = moved.reduce(0) { $0 + $1.item.snapshot.allocatedSize }
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
        if !notMoved.isEmpty {
            Text("Not moved")
                .font(.headline)
            List(notMoved, id: \.item.url) { outcome in
                ItemRow(url: outcome.item.url, home: home) {
                    Text(Self.reason(outcome))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.bordered)
        } else {
            Spacer()
        }
        HStack {
            if let navigation {
                // Where every item's outcome stays, and where Restore puts things back (HIS-002).
                Button("Show in History") {
                    navigation.showHistory(revealing: report.run)
                    dismiss()
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private func failure(_ error: HistoryError) -> some View {
        Text("Nothing was moved")
            .font(.title2.bold())
        // Every action is logged before it runs, so without the log nothing runs (SAF-005).
        Text("Shuck never moves anything without recording it first, and it couldn't record this run.")
        HistoryErrorText(error: error)
        Spacer()
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Why an item was not moved, in words (SAF-011).
    static func reason(_ outcome: ItemOutcome) -> LocalizedStringResource {
        let operation = HistoryRecord.Operation(outcome.item.method)
        return switch outcome.result {
        case .done: OutcomeWording.method(operation)
        case .skipped(let reason): OutcomeWording.skipped(reason.code, operation: operation)
        case .failed(let error): OutcomeWording.failed(error)
        }
    }
}

/// An item's name and folder, with a trailing detail such as its size. The Restore sheet uses it too.
struct ItemRow<Detail: View>: View {
    let url: URL
    let home: URL
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: url.lastPathComponent)
                Text(verbatim: ResultRow.folder(of: url, home: home))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            detail
        }
    }
}
