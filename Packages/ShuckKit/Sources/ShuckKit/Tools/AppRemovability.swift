import Foundation

/// Whether the user can remove an app's bundle, from what a read-only check sees (APP-005, R-16).
///
/// A missing App Management permission cannot be seen before the run, so it is not here: the run reports the bundle
/// as a skipped item (M3-T06). A blocked app is still listed.
public enum AppRemovability: Equatable, Sendable {
    case removable
    case blocked(Reason)

    /// Why the bundle cannot be removed.
    public enum Reason: Equatable, Sendable, CaseIterable {
        /// Another user owns the bundle, such as a root-owned app an installer put in `/Applications`.
        case ownedByAnotherUser
        /// The user cannot change the bundle itself.
        case bundleNotWritable
        /// The user cannot change the folder the bundle is in.
        case folderNotWritable

        public var explanation: LocalizedStringResource {
            switch self {
            case .ownedByAnotherUser:
                LocalizedStringResource(
                    "Installed by another user or an installer — Shuck can't remove it without admin rights",
                    bundle: #bundle)
            case .bundleNotWritable:
                LocalizedStringResource("You don't have permission to change this app", bundle: #bundle)
            case .folderNotWritable:
                LocalizedStringResource(
                    "You don't have permission to change the folder this app is in", bundle: #bundle)
            }
        }
    }

    /// Moving a bundle to the Trash needs write access to the bundle and to the folder it is in, which `access(2)`
    /// reports with ACLs counted. Without both, the reason is the owner if it is another user, then the bundle, then
    /// the folder. If `access` fails for another reason the app counts as removable: a missed case becomes a skip in
    /// the run, but a wrongly blocked app could never be uninstalled. Only reads (APP-005).
    static func check(_ bundle: URL, owner: uid_t?, currentUser: uid_t) -> AppRemovability {
        let bundleWritable = isWritable(bundle)
        let folderWritable = isWritable(bundle.deletingLastPathComponent())
        guard !bundleWritable || !folderWritable else { return .removable }
        if let owner, owner != currentUser { return .blocked(.ownedByAnotherUser) }
        return .blocked(bundleWritable ? .folderNotWritable : .bundleNotWritable)
    }

    /// `false` only when `access` refuses for lack of permission.
    private static func isWritable(_ url: URL) -> Bool {
        access(url.path, W_OK) == 0 || (errno != EACCES && errno != EPERM && errno != EROFS)
    }
}
