import Foundation

/// Why an item was skipped, as the history log records it: a stable code that later versions keep, so older logs read
/// the same (SAF-011, section 8.5, D-88).
///
/// A result record's `detail` holds the code alone, or the code, a colon and what the executor found:
/// `missing`, `changed: file, 4096 bytes`. Shuck 0.1.0 wrote the same names followed by Swift's description of their
/// values in brackets, such as `changed(ShuckKit.ItemSnapshot(…))`, and ``init(detail:)`` reads both.
public enum SkipCode: String, CaseIterable, Sendable {
    case missing
    case notAccessible
    case changed
    case replaced
    case rejected
    case cancelled
    case historyUnavailable
    case unsupportedMethod
    case notAllowed
    case originalTaken
    case notInTrash
    case otherItem

    /// The code a logged detail starts with, or `nil` if this version does not know it.
    public init?(detail: String) {
        self.init(rawValue: String(detail.prefix { $0 != ":" && $0 != "(" }))
    }

    /// The text the log records: the code, followed by `detail` after a colon if there is one.
    public func logged(_ detail: String? = nil) -> String {
        detail.map { "\(rawValue): \($0)" } ?? rawValue
    }
}

extension ItemSnapshot {
    /// How a skip reason's detail records the snapshot: `file, 4096 bytes`.
    public var logged: String {
        "\(kind.rawValue), \(allocatedSize) bytes"
    }
}

extension PathGuardError {
    /// The rule the path was rejected by, as a skip reason's detail records it. The path is in the record already.
    public var logged: String {
        switch self {
        case .emptyPath: "emptyPath"
        case .rootFolder: "rootFolder"
        case .homeFolder: "homeFolder"
        case .notAbsolute: "notAbsolute"
        case .parentReference: "parentReference"
        case .unresolvable: "unresolvable"
        case .outsideAllowedRoots: "outsideAllowedRoots"
        case .protectedLocation(_, let protected): "protectedLocation \(protected)"
        case .otherVolume: "otherVolume"
        }
    }
}
