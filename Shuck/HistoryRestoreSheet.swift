import ShuckExecution
import ShuckKit
import SwiftUI

/// The sheet for one Restore from History: the question when some original paths are taken, then progress, then the
/// summary (HIS-003, SAF-011).
///
/// Without a taken path the restore has already started when the sheet opens (D-68). Nothing is ever replaced: Keep
/// Both puts an item back under a " (restored)" name, and Skip leaves it in the Trash.
struct HistoryRestoreSheet: View {
    let restore: HistoryRestore
    /// The home folder, shown as `~` in folder paths.
    let home: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch restore.phase {
            case .askingAboutTakenPaths:
                question
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
        .interactiveDismissDisabled(restore.phase == .running)
    }

    /// One answer for every taken path (D-68). Cancel moves nothing.
    @ViewBuilder private var question: some View {
        let taken = restore.takenItems
        Text("The original place of ^[\(taken.count) item](inflect: true) is taken")
            .font(.title2.bold())
        Text(
            """
            Keep Both puts each one back next to what is there now, with “(restored)” added to its name. \
            Skip leaves each one in the Trash. Nothing is replaced.
            """
        )
        .foregroundStyle(.secondary)
        if taken.count < restore.items.count {
            Text("Items whose original place is free are restored either way.")
                .foregroundStyle(.secondary)
        }
        List(taken, id: \.trashedURL) { item in
            ItemRow(url: item.originalURL, home: home) {
                if let bytes = item.bytes {
                    Text(bytes, format: .byteCount(style: .file))
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.bordered)
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Skip") { restore.start(ifTaken: .skip) }
            Button("Keep Both") { restore.start(ifTaken: .keepBoth) }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var running: some View {
        Text("Restoring ^[\(restore.items.count) item](inflect: true)…")
            .font(.title2.bold())
        Spacer()
        ProgressView()
            .frame(maxWidth: .infinity)
        Spacer()
        HStack {
            Spacer()
            Button("Stop") { restore.stop() }
                .keyboardShortcut(.cancelAction)
                .help("Stop before the next item. Items already restored stay where they are.")
        }
    }

    /// Every item with its outcome, so a skipped or failed one is visible (SAF-011).
    @ViewBuilder private func summary(_ report: RestoreReport) -> some View {
        let restored = report.outcomes.filter { if case .done = $0.result { true } else { false } }.count
        if restored == report.outcomes.count {
            Text("Restored ^[\(restored) item](inflect: true)")
                .font(.title2.bold())
        } else {
            Text("Restored \(restored) of ^[\(report.outcomes.count) item](inflect: true)")
                .font(.title2.bold())
        }
        List(report.outcomes, id: \.request.item.trashedURL) { outcome in
            ItemRow(url: outcome.request.item.originalURL, home: home) {
                Text(Self.outcome(outcome))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.bordered)
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private func failure(_ error: HistoryError) -> some View {
        Text("Nothing was restored")
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

    /// What happened to an item, in words (SAF-011).
    static func outcome(_ outcome: RestoreOutcome) -> LocalizedStringResource {
        switch outcome.result {
        case .done(let url?) where url != outcome.request.item.originalURL:
            "Restored as “\(url.lastPathComponent)”"
        case .done:
            "Restored"
        case .skipped(let reason):
            OutcomeWording.skipped(reason.code, operation: .restore)
        case .failed(let error):
            OutcomeWording.failed(error)
        }
    }
}
