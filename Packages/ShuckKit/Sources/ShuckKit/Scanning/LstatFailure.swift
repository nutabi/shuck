import Foundation

/// What a failed `lstat` says about the path (SAF-012, M3-T01).
///
/// `Restorability` and `ItemSnapshot` both read the error and used to sort it themselves, in opposite directions: for
/// an error that is neither of the two classes below, Restore's check says the Trash is not accessible and
/// re-validation says the item is missing. They now share this one table, and each keeps its own outcome for
/// ``other``.
enum LstatFailure: Equatable {
    /// Nothing is at the path (`ENOENT`), or a part of it that should be a folder is not (`ENOTDIR`).
    case missing
    /// Permission was denied (`EPERM` or `EACCES`), for example by macOS privacy protection.
    case notAccessible
    /// Any other error, such as `ENAMETOOLONG` or `ELOOP`.
    case other

    init(errno code: Int32) {
        switch code {
        case ENOENT, ENOTDIR: self = .missing
        case EPERM, EACCES: self = .notAccessible
        default: self = .other
        }
    }
}
