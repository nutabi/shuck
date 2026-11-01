/// The ID of a tool or sub-tool, as written in the history log's `tool` field (PRD section 8.5).
///
/// A struct rather than an enum, so a new sub-tool adds its ID next to its own code (FCL-003).
public struct ToolID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let largeFiles = ToolID(rawValue: "LRG")
    public static let oldFiles = ToolID(rawValue: "OLD")
    public static let developerJunk = ToolID(rawValue: "DEV")
    public static let cachesAndLogs = ToolID(rawValue: "CAC")
    public static let applications = ToolID(rawValue: "APP")
    public static let startupItems = ToolID(rawValue: "STA")
    /// History itself, for restores.
    public static let history = ToolID(rawValue: "HIS")
}
