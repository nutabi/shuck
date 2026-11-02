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
    /// The title of the date column, for example "Modified".
    let dateTitle: LocalizedStringResource
    /// For the name of the sub-tool that manages a read-only item (FCL-011).
    let registry: ToolRegistry

    @State private var previewURL: URL?
    @State private var previewItems: [URL] = []

    var body: some View {
        Table(results.rows, selection: $results.selection, sortOrder: $results.sortOrder) {
            TableColumn("Name", value: \.name) { row in
                NameCell(row: row, registry: registry)
            }
            .width(min: 160, ideal: 240)
            TableColumn("Folder", value: \.folder)
                .width(min: 120, ideal: 200)
            TableColumn("Kind", value: \.kind)
                .width(min: 80, ideal: 120)
            TableColumn("Size", value: \.size) { row in
                Text(row.size, format: .byteCount(style: .file))
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            .alignment(.numeric)
            TableColumn(Text(dateTitle), value: \.sortDate) { row in
                if let date = row.date {
                    Text(date, format: .dateTime.day().month().year())
                } else {
                    Text("Unknown")
                }
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            Button("Quick Look") { preview(urls) }
            Button("Show in Finder") { reveal(urls) }
        } primaryAction: { urls in
            reveal(urls)
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
    return PersonalFilesTable(results: results, dateTitle: "Modified", registry: .standard)
        .frame(width: 760, height: 320)
}
