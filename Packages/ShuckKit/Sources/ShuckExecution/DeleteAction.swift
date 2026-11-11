import Foundation
import ShuckKit

/// Deletes an item permanently: the action for Delete items, which only the Rebuildable tier allows (SAF-004). It
/// removes the item itself, or for an item whose scope is ``ItemScope/contents``, everything inside the folder, which
/// stays (CAC-004). Nothing is restorable; the history log records the item as `delete` (SAF-006).
///
/// It never follows anything out of the target (SAF-007). It works through file descriptors, not paths: it opens the
/// target's folder with no symlink anywhere in its path (`O_NOFOLLOW_ANY`), then removes each entry relative to the
/// folder that holds it. A symlink is removed itself, never followed, and a folder is entered only if it is still the
/// one just examined, so a folder swapped for a symlink during the run is not entered either. A folder on another
/// volume, such as a disk image mounted inside the target, is never entered.
///
/// An entry it cannot remove, such as a locked file, fails the item, but the rest of the item is still deleted: all of
/// it is inside the target, and a rebuildable item's tool rebuilds what is gone (D-101).
package struct DeleteAction: PlanAction {
    package init() {}

    package func act(on item: PlannedItem, at target: URL) async -> Acted<ItemOutcome.SkipReason> {
        // The guard returned the target with its parent folders resolved, so their path has no symlink to follow.
        let parent = open(target.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard parent >= 0 else { return Acted(.failed(ActionError(errno: errno))) }
        defer { close(parent) }
        let name = Array(target.lastPathComponent.utf8CString)
        var parentInfo = stat()
        var info = stat()
        guard fstat(parent, &parentInfo) == 0 else { return Acted(.failed(ActionError(errno: errno))) }
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            return errno == ENOENT ? Acted(.skipped(.missing)) : Acted(.failed(ActionError(errno: errno)))
        }

        let isFolder = info.st_mode & S_IFMT == S_IFDIR
        // A folder on another volume, mounted at the target. The guard refuses one too (D-135); this checks again on
        // the descriptor the deletion uses, in case a volume was mounted after the guard looked.
        if isFolder, info.st_dev != parentInfo.st_dev {
            return Acted(.skipped(.rejected(.otherVolume(target.path))))
        }
        let error: Int32?
        switch (item.scope, isFolder) {
        case (.item, false):
            error = unlinkat(parent, name, 0) == 0 ? nil : errno
        case (.item, true):
            error = Self.empty(name, in: parent, expected: info) ?? Self.removeEmptyFolder(name, in: parent)
        case (.contents, true):
            error = Self.empty(name, in: parent, expected: info)
        case (.contents, false):
            // The plan refuses this item and re-validation compares its kind; checked again here, next to the deletion.
            error = ENOTDIR
        }
        return Acted(error.map { .failed(ActionError(errno: $0)) } ?? .done(nil))
    }

    /// Removes everything inside the folder `name` in `parent`, which `expected` describes, and keeps the folder.
    /// Returns the first error, if any.
    private static func empty(_ name: [CChar], in parent: Int32, expected: stat) -> Int32? {
        withFolder(name, in: parent, expected: expected) { removeContents(of: $0, device: $1) }
    }

    /// Removes the folder `name` in `parent`, which must be empty by now. Returns the error, if any.
    private static func removeEmptyFolder(_ name: [CChar], in parent: Int32) -> Int32? {
        unlinkat(parent, name, AT_REMOVEDIR) == 0 ? nil : errno
    }

    /// Opens the folder `name` in `parent` without following a symlink, checks that it is the folder `expected`
    /// describes, and hands its descriptor and volume to `body`. Returns `body`'s error, or why the folder was not
    /// opened: `ELOOP` if it was swapped for a symlink, `ESTALE` if for another folder.
    private static func withFolder(
        _ name: [CChar], in parent: Int32, expected: stat, body: (Int32, dev_t) -> Int32?
    ) -> Int32? {
        let folder = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { return errno }
        defer { close(folder) }
        var opened = stat()
        guard fstat(folder, &opened) == 0 else { return errno }
        guard opened.st_dev == expected.st_dev, opened.st_ino == expected.st_ino else { return ESTALE }
        return body(folder, opened.st_dev)
    }

    /// Removes everything inside the open `folder`, which is on `device`, and goes on past what it cannot remove.
    /// Returns the first error, if any. An entry that is already gone is not an error.
    private static func removeContents(of folder: Int32, device: dev_t) -> Int32? {
        let (names, listingError) = entries(of: folder)
        if let listingError { return listingError }
        var firstError: Int32?
        for name in names {
            var info = stat()
            guard fstatat(folder, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno != ENOENT { firstError = firstError ?? errno }
                continue
            }
            let error: Int32?
            if info.st_mode & S_IFMT != S_IFDIR {
                error = unlinkat(folder, name, 0) == 0 || errno == ENOENT ? nil : errno
            } else if info.st_dev != device {
                // A mount point: what is mounted there is not part of the target.
                error = EXDEV
            } else {
                error = empty(name, in: folder, expected: info) ?? removeEmptyFolder(name, in: folder)
            }
            firstError = firstError ?? error
        }
        return firstError
    }

    /// The names of the entries in the open `folder`, without `.` and `..`, or why they could not be listed. They are
    /// all read before any is removed, since removing entries while reading a folder can make the reading skip some.
    private static func entries(of folder: Int32) -> (names: [[CChar]], error: Int32?) {
        // `fdopendir` takes over the descriptor it is given and `closedir` closes it, so it gets a copy.
        let copy = dup(folder)
        guard copy >= 0, let listing = fdopendir(copy) else {
            let error = errno
            if copy >= 0 { close(copy) }
            return ([], error)
        }
        defer { closedir(listing) }
        var names: [[CChar]] = []
        while let entry = readdir(listing) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                Array(bytes.prefix(Int(entry.pointee.d_namlen)).map { CChar(bitPattern: $0) }) + [0]
            }
            if name != [46, 0] && name != [46, 46, 0] { names.append(name) }
        }
        return (names, nil)
    }
}
