import ShuckExecution
import ShuckKit
import SwiftUI

/// The sheet for one uninstall: the itemized review with Quit if the app is running, then progress, then the summary
/// (APP-006, APP-007, SAF-002, SAF-011). It uses ``RunSheet``, as Move to Trash does.
///
/// Nothing moves until the user presses "Move to Trash", which stays off while the app runs and is not the default
/// button, so Return alone never moves anything.
struct UninstallReviewSheet: View {
    let review: UninstallReview
    /// The scanned home folder, shown as `~` in folder paths.
    let home: URL

    @Environment(\.dismiss) private var dismiss
    /// `nil` in previews, which then offer no link to History.
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    var body: some View {
        RunSheet(
            run: review.trash.run,
            runningTitle: Text("Uninstalling \(review.app.name)…"),
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
            }
        )
        // Closing the sheet stops waiting for the app, which is never forced (APP-006).
        .onDisappear { review.cancelQuit() }
    }

    @ViewBuilder private var reviewing: some View {
        let items = review.trashItems
        Text(
            "Move ^[\(items.count) item](inflect: true), \(review.totalBytes, format: .byteCount(style: .file)), to the Trash?"
        )
        .font(.title2.bold())
        Text("Shuck records where each item goes, so it can put it back.")
            .foregroundStyle(.secondary)
        if review.stopsAgents {
            Label("Launch agents are stopped before their files are moved.", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("uninstall-stops-agents")
        }
        quit
        List(items) { item in
            ItemRow(target: item.target, home: home) {
                SizeText(target: item.target, bytes: item.allocatedSize, snapshot: item.snapshot)
            }
        }
        .listStyle(.bordered)
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Move to Trash", role: .destructive) { review.start() }
                .disabled(!review.canMove)
        }
    }

    /// What the review says and offers while the app runs (APP-006).
    @ViewBuilder private var quit: some View {
        let name = review.app.name
        switch review.quit {
        case .notRunning:
            EmptyView()
        case .running:
            HStack(alignment: .firstTextBaseline) {
                Label("\(name) is running. Quit it to continue.", systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Quit \(name)") { review.quitTheApp() }
                    .help("Asks \(name) to quit, as ⌘Q does. Shuck never forces an app to quit.")
            }
        case .waiting:
            HStack {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Waiting for \(name) to quit…")
                Spacer()
                Button("Stop Waiting") { review.cancelQuit() }
            }
        case .notSent:
            HStack(alignment: .firstTextBaseline) {
                Label(
                    "\(name) didn't take the request to quit. Quit it yourself.",
                    systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Check Again") { review.refresh() }
            }
        }
    }

    @ViewBuilder private func summary(_ report: RunReport) -> some View {
        // An agent's unload step is an outcome too, but only what reached the Trash counts as moved.
        let trashed = report.outcomes.filter { $0.item.method == .trash }
        let moved = trashed.filter { if case .done = $0.result { true } else { false } }
        let notDone = report.outcomes.filter { if case .done = $0.result { false } else { true } }
        let bytes = moved.reduce(0) { $0 + $1.item.allocatedSize }
        if moved.count == trashed.count {
            Text("Moved ^[\(moved.count) item](inflect: true) to the Trash")
                .font(.title2.bold())
        } else {
            Text("Moved \(moved.count) of ^[\(trashed.count) item](inflect: true) to the Trash")
                .font(.title2.bold())
        }
        // Moving to the Trash frees nothing yet (SAF-013).
        Text("\(bytes, format: .byteCount(style: .file)) is in the Trash. The space is freed when you empty the Trash.")
            .foregroundStyle(.secondary)
        if let change = review.trash.freeSpace {
            FreeSpaceText(change: change)
        }
        if !notDone.isEmpty {
            OutcomeList(title: Text("Not moved"), outcomes: notDone, home: home)
        } else {
            Spacer()
        }
    }
}
