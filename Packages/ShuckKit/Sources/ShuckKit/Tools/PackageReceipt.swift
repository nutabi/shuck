import Foundation

/// The installer package that put an app on the Mac, as the receipt database knows it (APP-008).
public struct PackageReceipt: Equatable, Sendable {
    /// The package's identifier, such as `com.example.Notes.pkg`.
    public let packageID: String
    /// The version the package declares, if the receipt has one.
    public let version: String?
    /// When the package was installed, if the receipt says.
    public let installed: Date?

    public init(packageID: String, version: String?, installed: Date?) {
        self.packageID = packageID
        self.version = version
        self.installed = installed
    }
}

/// Why an app's receipts could not be read. This is never the same as "no receipt": an app that no package
/// installed has an empty list (APP-008).
public enum PackageReceiptError: Error, Equatable, Sendable {
    /// `pkgutil` is not there, or cannot be run.
    case toolUnavailable
    /// `pkgutil` ended with this exit status.
    case failed(Int32)
    /// `pkgutil` took longer than its timeout.
    case timedOut
    /// The lookup was stopped, for example because the selection changed.
    case stopped
    /// `pkgutil` ended well, but what it printed was cut short or is not the property list we expect.
    case unreadableOutput
}

/// Reads the receipts of one installed app. The engine only asks; the implementation that starts `pkgutil` lives in
/// `ShuckExecution`, the only place a subprocess may start (APP-008, D-82, D-200).
public protocol PackageReceiptReader: Sendable {
    /// The packages that installed `app`, one entry per package, in the order `pkgutil` names them. Empty if none did.
    func receipts(forAppAt app: URL) async throws(PackageReceiptError) -> [PackageReceipt]
}

extension PackageReceipt {
    /// The receipts in the output of `pkgutil --file-info-plist <path>` (APP-008). The output is untrusted: it must be
    /// a complete property list with a `path-info` array, or the result is ``PackageReceiptError/unreadableOutput``,
    /// never a guess from a part of it. An entry with no usable `pkgid` is left out, and a package named twice, as a
    /// folder's lookup does for each file in it, is listed once.
    public static func parse(fileInfo output: Data) throws(PackageReceiptError) -> [PackageReceipt] {
        guard let plist = try? PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
            let entries = plist["path-info"] as? [Any]
        else { throw .unreadableOutput }
        var seen = Set<String>()
        var receipts: [PackageReceipt] = []
        for case let entry as [String: Any] in entries {
            guard let id = entry["pkgid"] as? String, !id.isEmpty, seen.insert(id).inserted else { continue }
            let installed = (entry["install-time"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let version = (entry["pkg-version"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            receipts.append(PackageReceipt(packageID: id, version: version, installed: installed))
        }
        return receipts
    }
}
