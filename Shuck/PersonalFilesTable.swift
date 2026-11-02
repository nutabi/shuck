import AppKit
import QuickLook
import ShuckKit
import SwiftUI

/// The results table Large Files and Old Files share (FCL-012).
///
/// Rows appear as the scan finds them, and every column sorts. Selecting rows only marks them: nothing is removed
/// before the review (SAF-002). Space opens a Quick Look preview of the selection, and "Show in Finder" reveals it.
struct PersonalFilesTable: View {
    @Bindable var results: PersonalFilesResults
    /// For the name of the sub-tool that manages a read-only item (FCL-011).
    let registry: ToolRegistry
    /// Rows in sections by top-level folder, with subtotals (LRG-003).
    var grouped = false

    @State private var previewURL: URL?
    @FocusState private var isFocused: Bool
    @State private var previewItems: [URL] = []

    var body: some View {
        Table(of: ResultRow.self, selection: $results.selection, sortOrder: $results.sortOrder) {
            TableColumn("Name", value: \.name) { row in
                NameCell(row: row, registry: registry)
            }
            .width(min: 160, ideal: 240)
            TableColumn("Folder", value: \.folder)
                .width(min: 120, ideal: showsLastOpened ? 160 : 200)
            TableColumn("Kind", value: \.kind)
                .width(min: 80, ideal: 120)
            TableColumn("Size", value: \.size) { row in
                Text(row.size, format: .byteCount(style: .file))
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            .alignment(.numeric)
            TableColumn(dateTitle, value: \.sortDate) { row in
                DateCell(row: row)
            }
            // A last-opened date may have the word "Modified" next to it (OLD-002). Folder gives up the room, because
            // a table wider in total than its ideal width overflows the window instead of shrinking.
            .width(min: showsLastOpened ? 140 : 90, ideal: showsLastOpened ? 170 : 130)
        } rows: {
            if grouped {
                ForEach(results.groups) { group in
                    Section {
                        ForEach(group.rows) { TableRow($0) }
                    } header: {
                        GroupHeader(group: group)
                    }
                }
            } else {
                ForEach(results.rows) { TableRow($0) }
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            Button("Quick Look") { preview(urls) }
            Button("Show in Finder") { reveal(urls) }
        } primaryAction: { urls in
            reveal(urls)
        }
        // A click on a row selects it but leaves keyboard focus where it was, so Space would not reach the table.
        .focused($isFocused)
        .onChange(of: results.selection) {
            isFocused = true
        }
        // Space toggles the preview, as in Finder.
        .onKeyPress(.space) {
            if previewURL == nil {
                preview(results.selection)
            } else {
                previewURL = nil
            }
            return .handled
        }
        .quickLookPreview($previewURL, in: previewItems)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private var showsLastOpened: Bool { results.dateColumn == .lastOpened }

    private var dateTitle: Text {
        switch results.dateColumn {
        case .modified: Text("Modified")
        case .lastOpened: Text("Last Opened")
        }
    }

    /// The selection's total, and buttons for keyboard and VoiceOver users.
    private var footer: some View {
        HStack(spacing: 12) {
            if results.selection.isEmpty {
                Text("No items selected")
            } else {
                let count = results.actionableSelection.count
                Text(
                    "^[\(count) item](inflect: true) selected, \(results.selectedBytes, format: .byteCount(style: .file))"
                )
            }
            if results.selectionIncludesReadOnly {
                Label("Read-only items are not included", systemImage: "lock")
            }
            Spacer()
            Button("Quick Look") { preview(results.selection) }
                .disabled(results.selection.isEmpty)
            Button("Show in Finder") { reveal(results.selection) }
                .disabled(results.selection.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// `urls` in display order, so Quick Look and Finder follow the table's sort.
    private func ordered(_ urls: Set<URL>) -> [URL] {
        results.rows.map(\.id).filter(urls.contains)
    }

    private func preview(_ urls: Set<URL>) {
        let items = ordered(urls)
        guard let first = items.first else { return }
        previewItems = items
        previewURL = first
    }

    /// Opens Finder with the items selected. It only shows them; nothing is moved.
    private func reveal(_ urls: Set<URL>) {
        let items = ordered(urls)
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items)
    }
}

private struct GroupHeader: View {
    let group: ResultGroup

    var body: some View {
        HStack {
            if group.topFolder.isEmpty {
                Text("Home Folder")
            } else {
                Text(verbatim: group.topFolder)
            }
            Spacer()
            Text(group.size, format: .byteCount(style: .file))
                .monospacedDigit()
        }
    }
}

/// A date, marked in words when the last-opened column falls back to the modified date (OLD-002).
private struct DateCell: View {
    let row: ResultRow

    var body: some View {
        if let date = row.date {
            HStack(spacing: 4) {
                Text(date, format: .dateTime.day().month().year())
                if row.dateIsModifiedFallback {
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Spotlight has no record of this file being opened, so this is when it last changed.")
                }
            }
        } else {
            Text("Unknown")
        }
    }
}

private struct NameCell: View {
    let row: ResultRow
    let registry: ToolRegistry

    var body: some View {
        HStack(spacing: 4) {
            Text(row.name)
            // A symbol and its label, not color alone, mark a read-only row (NFR-A11Y-001).
            if let reason = row.readOnly {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(note(reason))
                    .accessibilityLabel(note(reason))
            }
        }
    }

    private func note(_ reason: ReadOnlyReason) -> Text {
        switch reason {
        case .managedBy(let id):
            let name = registry.info(id).map { String(localized: $0.name) } ?? id.rawValue
            return Text("Read-only: \(name) manages this item.")
        case .protected:
            return Text("Read-only: Shuck never removes this item.")
        }
    }
}

#Preview {
    let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
    let results = PersonalFilesResults(home: home, sortOrder: [KeyPathComparator(\.size, order: .reverse)])
    results.apply(
        .files([
            PersonalFile(
                url: home.appending(path: "Downloads/Installer.dmg"),
                snapshot: ItemSnapshot(kind: .file, allocatedSize: 2_400_000_000), modified: .now),
            PersonalFile(
                url: home.appending(path: "Movies/Holiday.mov"),
                snapshot: ItemSnapshot(kind: .file, allocatedSize: 6_100_000_000),
                modified: .now.addingTimeInterval(-90 * 86_400)),
            PersonalFile(
                url: home.appending(path: "Pictures/Photos Library.photoslibrary"),
                snapshot: ItemSnapshot(kind: .folder, allocatedSize: 48_000_000_000), modified: nil,
                readOnly: .protected),
            PersonalFile(
                url: home.appending(path: "go/pkg/mod"),
                snapshot: ItemSnapshot(kind: .folder, allocatedSize: 1_200_000_000), modified: nil,
                readOnly: .managedBy(.developerJunk)),
        ]))
    return PersonalFilesTable(results: results, registry: .standard, grouped: true)
        .frame(width: 760, height: 320)
}
