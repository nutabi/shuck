import Foundation

/// Somewhere items can be moved to and later restored from.
///
/// The app uses ``SystemTrash``. Tests use a fake that moves items into a folder inside the fixture root, so they never
/// touch the real Trash in the home folder (D-47).
public protocol Trash: Sendable {
    /// The folder the Trash moves items into. Restore takes items only from directly inside it.
    var folder: URL { get throws }

    /// Moves the item at `url` to the Trash and returns where it ended up (SAF-005).
    func trashItem(at url: URL) throws -> URL
}

/// The user's Trash, through `FileManager.trashItem(at:resultingItemURL:)` [S42].
public struct SystemTrash: Trash {
    public init() {}

    public var folder: URL {
        get throws {
            try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        }
    }

    public func trashItem(at url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let trashed = resulting as URL? else { throw CocoaError(.fileWriteUnknown) }
        return trashed
    }
}
