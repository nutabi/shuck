import ShuckKit
import SwiftUI

/// The layout every File Cleanup sub-tool page shares, so a page gives only what differs (FCL-003):
///
/// - the sub-tool's name as the title, and the page's subtitle;
/// - the toolbar: while scanning, a progress indicator with Stop next to it (SAF-014); then the page's own controls
///   and Scan;
/// - a scan when the page opens, if the sub-tool has not scanned yet (D-61);
/// - while there is nothing to list, only a message: not scanned yet, scanning, or nothing found (D-61);
/// - Move to Trash's review sheet, which belongs to the page so its summary stays when a run empties the list (D-77).
///
/// The page's list gets ``MoveToTrash`` for the review, or `nil` when the model cannot move anything, as in previews.
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
    @ViewBuilder let results: (MoveToTrash?) -> Results
    /// The page's own toolbar controls, before Scan, such as Group by Folder.
    @ViewBuilder let controls: Controls

    /// The open Move to Trash review, from the list's selection until the user closes the summary.
    @State private var review: TrashReview?

    var body: some View {
        // A ZStack, not a Group: a Group passes its modifiers on to the view inside it, so the sheet would belong to
        // the list and close with it. The ZStack stays while the list gives way to the message.
        ZStack {
            if model.results(of: subTool.id)?.isEmpty ?? true {
                emptyState
            } else {
                results(moveToTrash)
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
    }

    private var isScanning: Bool { model.state(of: subTool.id) == .scanning }

    /// "Move to Trash" for the list, or `nil` when the model cannot move anything, as in previews.
    private var moveToTrash: MoveToTrash? {
        model.canMoveToTrash ? MoveToTrash(model: model, subTool: subTool, review: $review) : nil
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
        scanHelp: Text, @ViewBuilder results: @escaping (MoveToTrash?) -> Results
    ) {
        self.init(
            subTool: subTool, model: model, subtitle: subtitle, notScanned: notScanned, nothingFound: nothingFound,
            scanHelp: scanHelp, results: results, controls: { EmptyView() })
    }
}
