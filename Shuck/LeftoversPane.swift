import ShuckKit
import SwiftUI

/// What sits below the apps list: the selected app's leftovers, each with how sure the scan is and why it is listed
/// (APP-002, APP-003), the system-wide ones that need admin rights (APP-004), or why the app cannot be uninstalled
/// (APP-005, R-16). Each leftover has a checkbox that chooses it for the uninstall, set as the scan selected it, and a
/// disabled one has none to change (APP-007). Uninstall in the toolbar opens the review.
struct LeftoversPane: View {
    let model: ApplicationsModel

    var body: some View {
        VStack(spacing: 0) {
            if let app = model.selectedApp {
                if case .blocked(let reason) = app.removability {
                    blocked(reason, bundle: app.url)
                } else {
                    leftovers(of: app)
                }
            } else {
                ContentUnavailableView {
                    Label("No app selected", systemImage: "app.dashed")
                } description: {
                    Text("Select an app to see what it leaves behind.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The reason in words and a lock, as the row's "Can't uninstall" label does (APP-005). "Show in Finder" lets the
    /// user remove the app by hand, as for a system-wide leftover (APP-004). Shuck itself moves nothing.
    private func blocked(_ reason: AppRemovability.Reason, bundle: URL) -> some View {
        ContentUnavailableView {
            Label("Can't uninstall this app", systemImage: "lock")
        } description: {
            Text(reason.explanation)
        } actions: {
            Button("Show in Finder") { FinderReveal.show([bundle]) }
                .accessibilityIdentifier("blocked-show-in-finder")
        }
    }

    @ViewBuilder private func leftovers(of app: InstalledApp) -> some View {
        Label {
            Text("macOS may ask for permission to read other apps' containers.")
        } icon: {
            Image(systemName: "hand.raised")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        if !model.leftoverNotAccessible.isEmpty { NotAccessibleNote(folders: model.leftoverNotAccessible) }
        if !model.leftoverUnreadable.isEmpty { UnreadableNote(folders: model.leftoverUnreadable) }
        if model.leftovers.isEmpty {
            if model.leftoverState == .scanned {
                ContentUnavailableView("No leftovers found", systemImage: "checkmark.circle")
            } else {
                ProgressView("Looking for leftovers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List(ScanOrder.ordered(model.leftovers, scanning: model.leftoverState == .scanning)) { item in
                LeftoverRow(
                    item: item,
                    isChosen: Binding {
                        item.url.map(model.chosen.contains) ?? false
                    } set: {
                        model.setChosen($0, for: item)
                    })
            }
        }
    }
}

/// One leftover: its name and folder, its size, how sure the scan is in words, and why it is listed. A system-wide one
/// says why it cannot be removed and has "Show in Finder", since the user can remove it by hand (APP-004).
private struct LeftoverRow: View {
    let item: ScanItem
    /// Whether the uninstall will move it to the Trash.
    @Binding var isChosen: Bool

    var body: some View {
        let name = item.url?.lastPathComponent ?? ""
        // The whole path, since `~/Library/Preferences/x.plist` and `/Library/Preferences/x.plist` share a name.
        let key = item.url?.path ?? name
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // The name is the VoiceOver label; a disabled one reads as dimmed, and its words say why (NFR-A11Y-001).
            Toggle(isOn: $isChosen) { Text(verbatim: name) }
                .labelsHidden()
                .disabled(!item.selection.isSelectable)
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityIdentifier("leftover-toggle-\(key)")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                if let folder = item.url?.deletingLastPathComponent().path {
                    Text(verbatim: folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("leftover-reason-\(key)")
                if let reason = item.selection.disabledReason, let url = item.url {
                    HStack {
                        Text(reason)
                            .font(.caption)
                            .accessibilityIdentifier("leftover-disabled-\(key)")
                        Button("Show in Finder") { FinderReveal.show([url]) }
                            .controlSize(.small)
                            .accessibilityIdentifier("leftover-show-in-finder-\(key)")
                    }
                }
            }
            Spacer()
            if let confidence = item.confidence {
                Text(Self.word(for: confidence))
                    .accessibilityIdentifier("leftover-confidence-\(key)")
            }
            SizeText(target: item.target, bytes: item.allocatedSize, snapshot: item.snapshot)
        }
    }

    /// The confidence in words, so color never carries it alone (NFR-A11Y-001).
    private static func word(for confidence: Confidence) -> LocalizedStringKey {
        switch confidence {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}
