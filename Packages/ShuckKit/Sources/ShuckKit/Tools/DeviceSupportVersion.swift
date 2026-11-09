import Foundation

/// What Developer Junk reads from the names of Xcode's device support folders, such as
/// `iOS DeviceSupport/17.2 (21C62) arm64e` (DEV-R02, D-118). Only reads names; it never touches the folders.
public enum DeviceSupportVersion {
    /// The folder's OS version as numbers, such as `[17, 2]` for `17.2 (21C62) arm64e` or `iPhone15,2 17.0 (21A329)`,
    /// or `nil` if no word of the name is a version. Xcode has named these folders both ways over the years.
    static func components(ofFolder name: String) -> [Int]? {
        for word in name.split(whereSeparator: \.isWhitespace) {
            let parts = word.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCIIDigit) })
            else { continue }
            return parts.compactMap { Int($0) }
        }
        return nil
    }

    /// The names that hold the newest version among `names`, one platform's folders. All names with that version are
    /// kept, so two builds of one version, or two CPU types, stay together. A name with no version is not among them,
    /// and never decides which version is newest (D-118).
    static func newest(among names: [String]) -> Set<String> {
        let versions = names.compactMap { name in components(ofFolder: name).map { (name, $0) } }
        guard let newest = versions.map(\.1).max(by: { compare($0, $1) == .orderedAscending }) else { return [] }
        return Set(versions.filter { compare($0.1, newest) == .orderedSame }.map(\.0))
    }

    /// Version numbers compare part by part, a missing part as 0, so `17` and `17.0` are the same version.
    private static func compare(_ left: [Int], _ right: [Int]) -> ComparisonResult {
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// What a row shows for the device support folder at `url`: the platform and the version, such as
    /// `iOS 17.2 (21C62) arm64e` for `iOS DeviceSupport/17.2 (21C62) arm64e`. Any other folder keeps its own name.
    public static func name(ofFolder url: URL) -> String {
        let platformFolder = url.deletingLastPathComponent().lastPathComponent
        guard platformFolder.hasSuffix(suffix), platformFolder.count > suffix.count else {
            return url.lastPathComponent
        }
        let platform = platformFolder.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
        return platform.isEmpty ? url.lastPathComponent : "\(platform) \(url.lastPathComponent)"
    }

    static let suffix = "DeviceSupport"
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
