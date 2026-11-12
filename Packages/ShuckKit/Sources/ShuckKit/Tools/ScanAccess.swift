import Foundation

/// What the path guard says about a scan candidate, told apart so a scan can report what macOS kept it out of
/// (SAF-012, ONB-002) and stay silent about what the user or the protected-locations list hides (SET-001, D-149).
enum ScanAccess {
    case allowed
    /// Refused for a reason that hides the item by design: a protected location, an exclusion, outside the roots.
    case hidden
    /// Shuck may not read the item, so it cannot tell whether it is safe to list.
    case notReadable

    init(_ url: URL, allowedRoots: [URL], protection: PathGuardConfiguration) {
        do {
            _ = try PathGuard(configuration: protection).validate(url, allowedRoots: allowedRoots)
            self = .allowed
        } catch .notReadable {
            self = .notReadable
        } catch {
            self = .hidden
        }
    }

    /// Whether the scan may go on with `url`. A `notReadable` item is reported as not accessible, and nothing is
    /// reported for a `hidden` one or once the scan is cancelled.
    func admits(_ url: URL, _ emit: (ScanEvent) -> Void) -> Bool {
        if self == .notReadable, !Task.isCancelled { emit(.notAccessible(url)) }
        return self == .allowed
    }

    /// The snapshot and the modification date of `url`. If either cannot be read, the item is reported as not
    /// accessible and `nil` is returned. Nothing is reported when the scan was cancelled, which stops the snapshot
    /// too, or when the item is gone, as one that was removed while the scan ran: that is not macOS keeping Shuck out.
    static func measure(_ url: URL, _ emit: (ScanEvent) -> Void) -> (snapshot: ItemSnapshot, modified: Date)? {
        guard let snapshot = ItemSnapshot.read(url, while: { !Task.isCancelled }),
            let modified = RuleMatch.modificationDate(at: url)
        else {
            if !Task.isCancelled, ResolvedPath.itemExists(at: url) { emit(.notAccessible(url)) }
            return nil
        }
        return (snapshot, modified)
    }
}
