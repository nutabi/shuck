import Foundation

/// Why an action on an item failed: the error's domain and code, which callers can act on, and its localized
/// description (SAF-011, D-88).
public struct ActionError: LocalizedError, Equatable, Sendable {
    /// The error's domain, such as `NSCocoaErrorDomain` or `NSPOSIXErrorDomain`.
    public let domain: String
    /// The error's code in its domain, such as an `errno` value.
    public let code: Int
    /// The error's localized description.
    public let message: String

    public init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }

    /// The domain, code and localized description of `error`.
    public init(_ error: any Error) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code, message: error.localizedDescription)
    }

    /// The error a failed POSIX call left in `errno`.
    public init(errno code: Int32) {
        self.init(domain: NSPOSIXErrorDomain, code: Int(code), message: String(cString: strerror(code)))
    }

    /// The error that `logged` recorded, or `nil` for other text, such as the description Shuck 0.1.0 logged
    /// (D-88). The domain has no spaces, so the first space ends it.
    public init?(logged: String) {
        guard let space = logged.firstIndex(of: " "), let colon = logged.range(of: ": "),
            space < colon.lowerBound, let code = Int(logged[logged.index(after: space)..<colon.lowerBound])
        else { return nil }
        self.init(domain: String(logged[..<space]), code: code, message: String(logged[colon.upperBound...]))
    }

    /// The text the history log records: `NSCocoaErrorDomain 513: The file couldn’t be moved…`.
    public var logged: String {
        "\(domain) \(code): \(message)"
    }

    /// The localized description, which the app shows (NFR-L10N-001).
    public var errorDescription: String? { message }
}
