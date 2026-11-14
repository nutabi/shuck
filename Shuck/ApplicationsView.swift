import AppKit
import ShuckKit
import SwiftUI

/// Applications: the apps the user can uninstall, with their icon, version, size and last-opened date (APP-001). The
/// Name, Size and Last Opened headers sort the list, and the search field matches an app's name and bundle ID
/// (APP-009). Selecting an app shows its leftovers in a pane below the list (APP-002 to APP-005).
///
/// Like a File Cleanup sub-tool's page, it scans when it opens if it has not scanned yet, shows only a message while
/// there is nothing to list, and has Scan and, while scanning, Stop in the toolbar (SAF-014, D-61). Choosing apps to
/// uninstall comes later.
struct ApplicationsView: View {
    let info: ToolInfo
    @Bindable var model: ApplicationsModel

    var body: some View {
        // A ZStack, not a Group, so the toolbar and the search field stay while the list gives way to a message.
        ZStack {
            if model.apps.isEmpty {
                emptyState
            } else if model.visibleApps.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                list
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // What the app scan could not read, as File Cleanup's pages tell it (SAF-011, SAF-012).
            VStack(spacing: 0) {
                if !model.notAccessible.isEmpty { NotAccessibleNote(folders: model.notAccessible) }
                if !model.unreadable.isEmpty { UnreadableNote(folders: model.unreadable) }
            }
        }
        .navigationTitle(Text(info.name))
        .navigationSubtitle(Text(info.summary))
        .searchable(text: $model.searchText, prompt: Text("Search Apps"))
        .toolbar {
            // Stop covers the leftover scan too (SAF-014).
            if model.state == .scanning || model.leftoverState == .scanning {
                // On its own, without the glass capsule the toolbar would otherwise share with the buttons next to it.
                ToolbarItem {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning")
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem {
                    Button("Stop Scanning", systemImage: "stop.fill") {
                        model.cancelScan()
                    }
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop scanning (⌘.). Scanning never removes anything.")
                }
            }
            ToolbarItem {
                Button("Scan", systemImage: "magnifyingglass") {
                    model.scan()
                }
                .disabled(!model.canScan)
                .help("Look for installed apps. Scanning never removes anything.")
            }
        }
        .onAppear {
            model.scanIfNotScanned()
        }
    }

    private var list: some View {
        VSplitView {
            table.frame(minHeight: 160)
            LeftoversPane(model: model).frame(minHeight: 140, idealHeight: 220)
        }
    }

    private var table: some View {
        Table(
            of: InstalledApp.self,
            selection: Binding {
                model.selection
            } set: {
                model.select($0)
            },
            sortOrder: $model.sortOrder
        ) {
            TableColumn("Name", sortUsing: AppSortComparator(key: .name)) { app in
                NameCell(app: app)
            }
            .width(min: 180, ideal: 260)
            TableColumn("Version") { app in
                if let version = app.version {
                    Text(verbatim: version)
                } else {
                    Text("Unknown")
                }
            }
            .width(min: 70, ideal: 100)
            TableColumn("Size", sortUsing: AppSortComparator(key: .size)) { app in
                SizeText(target: .path(app.url), bytes: app.allocatedSize, snapshot: app.snapshot)
            }
            .width(min: 70, ideal: 90)
            .alignment(.numeric)
            TableColumn("Last Opened", sortUsing: AppSortComparator(key: .lastOpened)) { app in
                if let date = app.lastOpened {
                    Text(date, format: .dateTime.day().month().year())
                } else {
                    Text("Unknown")
                        .help("Spotlight has no record of this app being opened.")
                }
            }
            .width(min: 100, ideal: 130)
        } rows: {
            ForEach(model.visibleApps) { TableRow($0) }
        }
    }

    /// What the page shows while there is nothing to list.
    @ViewBuilder private var emptyState: some View {
        switch model.state {
        case .notScanned:
            ContentUnavailableView {
                Label("Not scanned yet", systemImage: info.symbolName)
            } description: {
                Text("Scan to list the apps you can uninstall. Scanning never removes anything.")
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
                Label("No apps found", systemImage: "checkmark.circle")
            }
        }
    }
}

/// An app's icon, name and bundle ID. Each text is its own element, so VoiceOver reads the name, then the bundle ID.
private struct NameCell: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: app.name)
                if let bundleID = app.bundleID {
                    Text(verbatim: bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if case .blocked = app.removability {
                    // A lock and words, never color alone (NFR-A11Y-001, APP-005).
                    Label("Can't uninstall", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
