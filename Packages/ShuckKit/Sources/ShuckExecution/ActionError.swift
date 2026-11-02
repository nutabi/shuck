import Foundation

/// Why an action on an item failed: the error's domain and code, which callers can act on, and its localized
/// description (SAF-011, D-88).
public struct ActionError: Error, Equatable, Sendable {
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

    /// The text the history log records: `NSCocoaErrorDomain 513: The file couldn’t be moved…`.
    public var logged: String {
        "\(domain) \(code): \(message)"
    }
}
