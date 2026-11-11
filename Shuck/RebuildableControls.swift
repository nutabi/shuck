import ShuckKit
import SwiftUI

/// What starts a row of Rebuildable items: a checkbox, or a lock and a note, such as "App is running", when the row
/// cannot be chosen (SAF-009, CAC-003). Developer Junk and Caches & Logs share it.
struct SelectionMark: View {
    let item: ScanItem
    /// What VoiceOver says for the checkbox.
    let name: String
    /// How a UI test finds the checkbox.
    let identifier: String
    let isSelected: Binding<Bool>

    var body: some View {
        if let reason = item.selection.disabledReason {
            // A symbol and words, not color alone, say why the row cannot be chosen (NFR-A11Y-001).
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .help(Text(reason))
                .accessibilityHidden(true)
        } else {
            Toggle(isOn: isSelected) {
                Text(verbatim: name)
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityIdentifier(identifier)
        }
    }
}

/// "Select All" and "Select None", next to a list's count. A row that cannot be chosen, such as a running app's, stays
/// unselected (SAF-009).
struct SelectAllButtons: View {
    /// Whether nothing is selected, which disables Select None.
    let isEmpty: Bool
    let selectAll: () -> Void
    let selectNone: () -> Void

    var body: some View {
        Button("Select All", action: selectAll)
            .help("Select every item that can be selected.")
        Button("Select None", action: selectNone)
            .disabled(isEmpty)
            .help("Deselect every item.")
    }
}

/// The bar under a list of Rebuildable items: how many are selected, and "Delete…", which opens the summary
/// confirmation (SAF-003). It is `nil` when the model cannot run anything, as in previews.
struct RebuildableFooter: View {
    let results: ScanResults
    let action: ConfirmRebuildable?
    /// What the Delete button's help tag says it reviews.
    let help: Text

    var body: some View {
        HStack {
            if results.selectedItems.isEmpty {
                Text("No items selected")
            } else {
                Text(
                    "^[\(results.selectedItems.count) item](inflect: true) selected, \(results.selectedBytes, format: .byteCount(style: .file))"
                )
            }
            SelectAllButtons(isEmpty: results.selectedItems.isEmpty) {
                results.selectAll()
            } selectNone: {
                results.selection = []
            }
            Spacer()
            if let action {
                Button("Delete…") { action.review() }
                    .disabled(results.selectedItems.isEmpty)
                    .help(help)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
