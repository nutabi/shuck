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
    /// What Select All's help tag says it selects.
    var selectAllHelp = Text("Select every item that can be selected.")
    let selectAll: () -> Void
    let selectNone: () -> Void

    var body: some View {
        Button("Select All", action: selectAll)
            .help(selectAllHelp)
        Button("Select None", action: selectNone)
            .disabled(isEmpty)
            .help("Deselect every item.")
    }
}

/// The bar under a list of Rebuildable items: how many are selected, and "Delete…", which opens the summary
/// confirmation (SAF-003). It is `nil` when the model cannot run anything, as in previews.
///
/// A list that also has "Your data" items, such as Developer Junk with Xcode Archives, gets a second action with its own
/// count and size: "Move to Trash…", which opens the itemized review (SAF-002). Each action counts and acts on its own
/// tier only, so a run never mixes them, and each is disabled while its own count is zero (D-147).
struct RebuildableFooter: View {
    let results: ScanResults
    let action: ConfirmRebuildable?
    /// What the Delete button's help tag says it reviews.
    let help: Text
    /// Opens the review of the selected "Your data" items. `nil` for a page whose list has none, or when the model
    /// cannot run anything.
    var moveToTrash: (() -> Void)?

    var body: some View {
        let rebuildable = results.selectedItems(in: .rebuildable)
        let yourData = results.selectedItems(in: .yourData)
        let hasYourData = moveToTrash != nil && results.hasYourData
        HStack {
            SelectAllButtons(
                isEmpty: results.selectedItems.isEmpty,
                selectAllHelp: hasYourData
                    ? Text("Select every item that can be selected, except your data, which you choose one by one.")
                    : Text("Select every item that can be selected.")
            ) {
                results.selectAll()
            } selectNone: {
                results.selection = []
            }
            Spacer()
            if let moveToTrash, hasYourData {
                if yourData.isEmpty {
                    Text("Your data: none selected")
                } else {
                    Text(
                        "Your data: ^[\(yourData.count) item](inflect: true) selected, \(results.selectedBytes(in: .yourData), format: .byteCount(style: .file))"
                    )
                }
                Button("Move to Trash…") { moveToTrash() }
                    .disabled(yourData.isEmpty)
                    .help("Review the selected items of your data before moving them to the Trash.")
                Divider().frame(height: 16)
            }
            if rebuildable.isEmpty {
                Text("No items selected")
            } else {
                Text(
                    "^[\(rebuildable.count) item](inflect: true) selected, \(results.selectedBytes(in: .rebuildable), format: .byteCount(style: .file))"
                )
            }
            if let action {
                Button("Delete…") { action.review() }
                    .disabled(rebuildable.isEmpty)
                    .help(help)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
