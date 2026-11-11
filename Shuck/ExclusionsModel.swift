import Foundation

/// The list of excluded folders Settings shows and changes (SET-001).
///
/// Every change is stored, then reported to ``didChange``, which gives the new list to the scans, plans and runs
/// (D-150).
@Observable
final class ExclusionsModel {
    private(set) var folders: [URL]
    private let list: ExcludedFolders
    private let didChange: ([URL]) -> Void

    /// - Parameters:
    ///   - didChange: Called with the whole list after every change. The app passes what rebuilds the path guard's
    ///     configuration for File Cleanup.
    init(list: ExcludedFolders, didChange: @escaping ([URL]) -> Void) {
        self.list = list
        self.didChange = didChange
        folders = list.folders
    }

    /// Excludes the folders. One already in the list is not added twice.
    func add(_ urls: [URL]) {
        update(list.add(urls))
    }

    /// Takes the folders out of the list. They are scanned again from the next scan on.
    func remove(_ urls: [URL]) {
        update(list.remove(urls))
    }

    private func update(_ updated: [URL]) {
        guard updated != folders else { return }
        folders = updated
        didChange(updated)
    }
}
