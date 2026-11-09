import ShuckKit
import SwiftUI
import os

/// The layout every File Cleanup sub-tool page shares, so a page gives only what differs (FCL-003):
///
/// - the sub-tool's name as the title, and the page's subtitle;
/// - the toolbar: while scanning, a progress indicator with Stop next to it (SAF-014); then the page's own controls
///   and Scan;
/// - a scan when the page opens, if the sub-tool has not scanned yet (D-61);
/// - while there is nothing to list, only a message: not scanned yet, scanning, or nothing found (D-61);
/// - the sheets of Move to Trash's review and the summary confirmation, which belong to the page so a summary stays
///   when a run empties the list (D-77).
///
/// The page's list gets ``PageActions`` to open them, or `nil` for an action when the model cannot run anything, as in
/// previews.
struct SubToolPage<Results: View, Controls: View>: View {
    let subTool: any SubTool
    let model: FileCleanupModel
    /// Which items the page lists, under the title.
    let subtitle: Text
    /// What a scan would list, under "Not scanned yet".
    let notScanned: Text
    /// What the page says when a finished scan found nothing.
    let nothingFound: Text
    /// The Scan button's help tag.
    let scanHelp: Text
    /// The list, shown from its first row on.
    @ViewBuilder let results: (PageActions) -> Results
    /// The page's own toolbar controls, before Scan, such as Group by Folder.
    @ViewBuilder let controls: Controls

    /// The open Move to Trash review, from the list's selection until the user closes the summary.
    @State private var review: TrashReview?
    /// The open summary confirmation, from the list's button until the user closes the summary (SAF-003).
    @State private var confirmation: SummaryConfirmation?
    /// A plan the path guard refused when the list asked for a confirmation; nothing is deleted (SAF-007).
    @State private var refusal: PlanError?

    var body: some View {
        // A ZStack, not a Group: a Group passes its modifiers on to the view inside it, so the sheet would belong to
        // the list and close with it. The ZStack stays while the list gives way to the message.
        ZStack {
            if model.results(of: subTool.id)?.isEmpty ?? true {
                emptyState
            } else {
                results(actions)
            }
        }
        .navigationTitle(Text(subTool.info.name))
        .navigationSubtitle(subtitle)
        .toolbar {
            if isScanning {
                // On its own, without the glass capsule the toolbar would otherwise share with the buttons next to it.
                ToolbarItem {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning")
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem {
                    Button("Stop Scanning", systemImage: "stop.fill") {
                        model.cancelScan(subTool)
                    }
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop scanning (⌘.). Scanning never removes anything.")
                }
            }
            ToolbarItemGroup {
                controls
                Button("Scan", systemImage: "magnifyingglass") {
                    model.scan(subTool)
                }
                .disabled(!model.canScan(subTool))
                .help(scanHelp)
            }
        }
        .onAppear {
            model.scanIfNotScanned(subTool)
        }
        .sheet(item: $review) { review in
            TrashReviewSheet(review: review, home: model.home)
        }
        .sheet(item: $confirmation) { confirmation in
            SummaryConfirmationSheet(confirmation: confirmation, home: model.home)
        }
        .alert("Nothing was deleted", isPresented: isRefused, presenting: refusal) { _ in
            Button("OK") {}
        } message: { refusal in
            Text(
                "“\(URL(filePath: refusal.path).lastPathComponent)” didn't pass Shuck's safety checks, so Shuck deleted nothing."
            )
        }
    }

    private var isScanning: Bool { model.state(of: subTool.id) == .scanning }

    /// What the list can open: each action is `nil` when the model cannot run anything, as in previews.
    private var actions: PageActions {
        PageActions(
            moveToTrash: model.canRun ? MoveToTrash(model: model, subTool: subTool, review: $review) : nil,
            confirmRebuildable: model.canRun
                ? ConfirmRebuildable(model: model, subTool: subTool, confirmation: $confirmation, refusal: $refusal)
                : nil)
    }

    private var isRefused: Binding<Bool> {
        Binding {
            refusal != nil
        } set: {
            if !$0 { refusal = nil }
        }
    }

    /// What the page shows while there is nothing to list.
    @ViewBuilder private var emptyState: some View {
        switch model.state(of: subTool.id) {
        case .notScanned:
            ContentUnavailableView {
                Label("Not scanned yet", systemImage: subTool.info.symbolName)
            } description: {
                notScanned
            }
        case .scanning:
            ProgressView("Scanning…")
        case .stopped:
            ContentUnavailableView {
                Label("Scan stopped", systemImage: "stop.circle")
            } description: {
                Text("Click Scan to scan again.")
            }
        case .scanned:
            ContentUnavailableView {
                Label {
                    nothingFound
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }
    }
}

extension SubToolPage where Controls == EmptyView {
    /// A page without toolbar controls of its own.
    init(
        subTool: any SubTool, model: FileCleanupModel, subtitle: Text, notScanned: Text, nothingFound: Text,
        scanHelp: Text, @ViewBuilder results: @escaping (PageActions) -> Results
    ) {
        self.init(
            subTool: subTool, model: model, subtitle: subtitle, notScanned: notScanned, nothingFound: nothingFound,
            scanHelp: scanHelp, results: results, controls: { EmptyView() })
    }
}

/// What a sub-tool's list can open from its own buttons. ``SubToolPage`` makes it, and owns the sheets they show.
struct PageActions {
    /// The itemized review for "Your data" (SAF-002).
    let moveToTrash: MoveToTrash?
    /// The summary confirmation for "Rebuildable" items (SAF-003).
    let confirmRebuildable: ConfirmRebuildable?
}

/// What a list needs to offer the summary confirmation for one sub-tool.
struct ConfirmRebuildable {
    let model: FileCleanupModel
    let subTool: any SubTool
    /// Where the list puts the confirmation it opens. The page owns it and shows the sheet.
    let confirmation: Binding<SummaryConfirmation?>
    /// Where the page learns the guard refused the plan.
    let refusal: Binding<PlanError?>

    /// Opens the confirmation for the selection. Nothing is deleted until the user confirms in it (SAF-003).
    func review() {
        do throws(PlanError) {
            confirmation.wrappedValue = try model.confirmRebuildable(subTool)
        } catch {
            // Private: the error names the item the plan stopped at (NFR-SEC-006).
            Logger.app.error("Refused a plan: \(String(describing: error), privacy: .private)")
            refusal.wrappedValue = error
        }
    }
}
