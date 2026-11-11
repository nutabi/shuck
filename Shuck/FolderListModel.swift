import Foundation

/// A list of folders Settings shows and changes: the excluded folders (SET-001) or the project folders (SET-003).
///
/// Every change is stored, then reported to ``didChange``, which gives the new list to the scans, plans and runs
/// (D-150, D-154).
@Observable
final class FolderListModel {
    private(set) var folders: [URL]
    /// The folders the last ``add(_:)`` did not accept, so Settings can say which and why.
    private(set) var refused: [URL] = []
    private let list: FolderList
    private let accepts: (URL) -> Bool
    private let didChange: ([URL]) -> Void

    /// - Parameters:
    ///   - accepts: Whether a folder may be added. A folder it refuses is kept in ``refused`` and is not stored.
    ///   - didChange: Called with the whole list after every change. The app passes what gives the new list to File
    ///     Cleanup.
    init(
        list: FolderList, accepts: @escaping (URL) -> Bool = { _ in true }, didChange: @escaping ([URL]) -> Void
    ) {
        self.list = list
        self.accepts = accepts
        self.didChange = didChange
        folders = list.folders
    }

    /// Adds the folders. One already in the list is not added twice, and one that is not accepted is not added at all.
    func add(_ urls: [URL]) {
        let accepted = urls.filter(accepts)
        refused = urls.filter { !accepted.contains($0) }
        guard !accepted.isEmpty else { return }
        update(list.add(accepted))
    }

    /// Takes the folders out of the list. They are scanned again from the next scan on.
    func remove(_ urls: [URL]) {
        refused = []
        update(list.remove(urls))
    }

    private func update(_ updated: [URL]) {
        guard updated != folders else { return }
        folders = updated
        didChange(updated)
    }
}
