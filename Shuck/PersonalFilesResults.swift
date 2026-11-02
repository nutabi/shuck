import Foundation
import ShuckKit
import UniformTypeIdentifiers

/// One sub-tool's list of personal files, as Large Files and Old Files show it (FCL-012).
///
/// The list fills in as the shared personal-files scan sends events, stays sorted by the column the user picked, and
/// keeps the user's selection. Each sub-tool has its own list and selection (FCL-002). When a run trashes items, they
/// are removed from every list at once (FCL-006).
@Observable
final class PersonalFilesResults {
    /// The rows in display order.
    private(set) var rows: [ResultRow] = []

    var sortOrder: [KeyPathComparator<ResultRow>] {
        didSet { rows.sort(using: sortOrder) }
    }

    /// The rows the user selected. Nothing is selected until the user chooses (D-10).
    var selection: Set<URL> = []

    private let home: URL
    private let includes: (PersonalFile) -> Bool

    /// - Parameters:
    ///   - home: The scanned home folder, shown as `~` in the Folder column.
    ///   - sortOrder: The sub-tool's default order, for example largest first for Large Files (LRG-002).
    ///   - includes: Which personal files the sub-tool lists, for example those above Large Files' threshold.
    init(
        home: URL, sortOrder: [KeyPathComparator<ResultRow>],
        includes: @escaping (PersonalFile) -> Bool = { _ in true }
    ) {
        self.home = home
        self.sortOrder = sortOrder
        self.includes = includes
    }

    /// Adds the files of a scan event that this list includes. A file listed again replaces its old row.
    func apply(_ event: PersonalFilesEvent) {
        guard case .files(let files) = event else { return }
        let incoming = files.filter(includes).map { ResultRow($0, home: home) }
        guard !incoming.isEmpty else { return }
        let incomingIDs = Set(incoming.map(\.id))
        rows.removeAll { incomingIDs.contains($0.id) }
        rows.append(contentsOf: incoming)
        rows.sort(using: sortOrder)
    }

    /// Removes rows, for example after a run trashed them, and drops them from the selection.
    func remove(_ urls: some Sequence<URL>) {
        let removed = Set(urls)
        rows.removeAll { removed.contains($0.id) }
        selection.subtract(removed)
    }

    /// The selected rows a cleanup can act on. Read-only rows are left out (FCL-011).
    var actionableSelection: [ResultRow] {
        rows.filter { selection.contains($0.id) && $0.readOnly == nil }
    }

    /// The allocated size of the actionable selection (SAF-013).
    var selectedBytes: Int64 {
        actionableSelection.reduce(0) { $0 + $1.size }
    }

    /// Whether the selection holds read-only rows, which the total and any cleanup leave out.
    var selectionIncludesReadOnly: Bool {
        rows.contains { selection.contains($0.id) && $0.readOnly != nil }
    }
}

/// A personal file as the results table shows it: name, folder, kind, size and date (FCL-012).
nonisolated struct ResultRow: Identifiable, Equatable {
    let id: URL
    let name: String
    /// The folder that holds the item, with the home folder shown as `~`.
    let folder: String
    /// The file type's name, as Finder shows it, for example "Disk Image".
    let kind: String
    /// Allocated size in bytes (SAF-013).
    let size: Int64
    /// The content-modified date. Old Files shows "last opened" instead from M1-T10 (OLD-002).
    let date: Date?
    let readOnly: ReadOnlyReason?

    /// `date` for sorting. Rows without a date sort as the oldest.
    var sortDate: Date { date ?? .distantPast }

    init(_ file: PersonalFile, home: URL) {
        id = file.url
        name = file.url.lastPathComponent
        folder = Self.folder(of: file.url, home: home)
        kind = Self.kind(of: file.url, snapshot: file.snapshot)
        size = file.snapshot.allocatedSize
        date = file.modified
        readOnly = file.readOnly
    }

    static func folder(of url: URL, home: URL) -> String {
        let parent = url.deletingLastPathComponent().pathComponents
        let homeParts = home.pathComponents
        guard parent.starts(with: homeParts) else { return NSString.path(withComponents: parent) }
        return (["~"] + parent.dropFirst(homeParts.count)).joined(separator: "/")
    }

    /// The type's name from the file name extension, so listing a row reads nothing from disk.
    static func kind(of url: URL, snapshot: ItemSnapshot) -> String {
        if !url.pathExtension.isEmpty, let name = UTType(filenameExtension: url.pathExtension)?.localizedDescription {
            return name
        }
        return snapshot.kind == .folder ? String(localized: "Folder") : String(localized: "Document")
    }
}
