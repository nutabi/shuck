import ShuckKit
import SwiftUI

/// The layout of every run's sheet, so Move to Trash, Restore and the summary confirmation cannot drift apart (TD-06):
///
/// - while the run waits, the review or question each run gives;
/// - while it runs, a title, a progress indicator and Stop on Escape;
/// - when it ends, the run's summary and a Done button, with the run's own buttons before it;
/// - if the history log could not be opened, why nothing ran (SAF-005).
///
/// The sheet stays until the user has seen the report (SAF-011).
struct RunSheet<Report: Equatable & Sendable, Waiting: View, Summary: View, Actions: View>: View {
    let run: RunModel<Report>
    /// The title while the run goes, such as "Moving 3 items to the Trash…".
    let runningTitle: Text
    /// What Stop does to items already acted on, as its help tag.
    let stopHelp: Text
    /// The title when the log could not be opened, such as "Nothing was moved".
    let failureTitle: Text
    /// Why that matters.
    let failureMessage: Text
    private let waiting: Waiting
    private let summary: (Report) -> Summary
    private let summaryActions: (Report) -> Actions

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - waiting: The review or question shown until the run starts.
    ///   - summary: What the report says.
    ///   - summaryActions: Buttons before Done in the summary, such as Show in History.
    init(
        run: RunModel<Report>, runningTitle: Text, stopHelp: Text, failureTitle: Text, failureMessage: Text,
        @ViewBuilder waiting: () -> Waiting, @ViewBuilder summary: @escaping (Report) -> Summary,
        @ViewBuilder summaryActions: @escaping (Report) -> Actions
    ) {
        self.run = run
        self.runningTitle = runningTitle
        self.stopHelp = stopHelp
        self.failureTitle = failureTitle
        self.failureMessage = failureMessage
        self.waiting = waiting()
        self.summary = summary
        self.summaryActions = summaryActions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch run.phase {
            case .waiting:
                waiting
            case .running:
                running
            case .finished(let report):
                summary(report)
                HStack {
                    summaryActions(report)
                    Spacer()
                    doneButton
                }
            case .failed(let error):
                failure(error)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 440)
        .interactiveDismissDisabled(run.phase == .running)
    }

    private var running: some View {
        Group {
            runningTitle
                .font(.title2.bold())
            Spacer()
            ProgressView()
                .frame(maxWidth: .infinity)
            Spacer()
            HStack {
                Spacer()
                Button("Stop") { run.stop() }
                    .keyboardShortcut(.cancelAction)
                    .help(stopHelp)
            }
        }
    }

    private func failure(_ error: HistoryError) -> some View {
        Group {
            failureTitle
                .font(.title2.bold())
            // Every action is logged before it runs, so without the log nothing runs (SAF-005).
            failureMessage
            HistoryErrorText(error: error)
            Spacer()
            HStack {
                Spacer()
                doneButton
            }
        }
    }

    private var doneButton: some View {
        Button("Done") { dismiss() }
            .keyboardShortcut(.defaultAction)
    }
}

extension RunSheet where Actions == EmptyView {
    /// A sheet whose summary has no button of its own.
    init(
        run: RunModel<Report>, runningTitle: Text, stopHelp: Text, failureTitle: Text, failureMessage: Text,
        @ViewBuilder waiting: () -> Waiting, @ViewBuilder summary: @escaping (Report) -> Summary
    ) {
        self.init(
            run: run, runningTitle: runningTitle, stopHelp: stopHelp, failureTitle: failureTitle,
            failureMessage: failureMessage, waiting: waiting, summary: summary, summaryActions: { _ in EmptyView() })
    }
}
