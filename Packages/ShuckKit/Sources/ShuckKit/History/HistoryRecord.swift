import Foundation

/// One line of the history log (PRD section 8.5).
///
/// The executor writes an intent record before each operation and a result record after it (SAF-005, SAF-006), so
/// after a crash the log still shows what was about to happen. Build records with ``intent(run:tool:operation:path:
/// tier:trashedPath:identity:bytes:)`` and ``result(run:tool:operation:path:tier:status:trashedPath:identity:bytes:detail:)``.
public struct HistoryRecord: Codable, Equatable, Sendable {
    /// The schema version this code writes and reads.
    public static let currentVersion = 1

    public enum Phase: String, Codable, Sendable {
        case intent
        case result
    }

    public enum Operation: String, Codable, Sendable {
        case trash
        case delete
        case tool
        case launchctl
        case restore

        /// The operation that records an action of `method`. Every run writes its records' operation through this, so
        /// a plan that mixes methods logs each item as what was done to it.
        public init(_ method: ActionMethod) {
            switch method {
            case .trash: self = .trash
            case .delete: self = .delete
            case .tool: self = .tool
            case .launchctl: self = .launchctl
            }
        }
    }

    public enum Status: String, Codable, Sendable {
        case ok
        case skipped
        case failed
    }

    public let version: Int
    public let timestamp: Date
    public let run: UUID
    public let tool: ToolID
    public let phase: Phase
    public let operation: Operation
    /// The original path; the tool name for a `tool` operation; the job label for `launchctl`. For `restore`, where
    /// the item is put back: the original path, or a " (restored)" name next to it (D-52).
    public let path: String
    /// Where the item went in the Trash, from `resultingItemURL` (SAF-005): result records of `trash`. For `restore`,
    /// intent and result records, the trashed path the item is taken from, which links it to its `trash` record (D-52).
    public let trashedPath: String?
    /// The trashed item's file identity, read just before the move: result records of `trash`, and, since Shuck 0.2.0,
    /// their intent records, so History can find an item whose result was never written in the Trash (HIS-001).
    /// Restore moves only an item that still has it. Logs written by Shuck 0.1.0 do not have it in results.
    public let identity: FileIdentity?
    /// The allocated size estimate in bytes. A tool item's result record has the size measured after the run instead,
    /// when there was one (D-184).
    public let bytes: Int64?
    public let tier: Tier
    /// Result records only.
    public let status: Status?
    /// A reason, tool exit code or error.
    public let detail: String?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case timestamp = "ts"
        case run, tool, phase
        case operation = "op"
        case path, trashedPath, identity, bytes, tier, status, detail
    }

    /// The record written just before an operation.
    public static func intent(
        run: UUID, tool: ToolID, operation: Operation, path: String, tier: Tier, trashedPath: String? = nil,
        identity: FileIdentity? = nil, bytes: Int64? = nil, timestamp: Date = Date()
    ) -> Self {
        Self(
            version: currentVersion, timestamp: timestamp, run: run, tool: tool, phase: .intent,
            operation: operation, path: path, trashedPath: trashedPath, identity: identity, bytes: bytes, tier: tier,
            status: nil, detail: nil)
    }

    /// The record written just after an operation, with its outcome (SAF-011).
    public static func result(
        run: UUID, tool: ToolID, operation: Operation, path: String, tier: Tier, status: Status,
        trashedPath: String? = nil, identity: FileIdentity? = nil, bytes: Int64? = nil, detail: String? = nil,
        timestamp: Date = Date()
    ) -> Self {
        Self(
            version: currentVersion, timestamp: timestamp, run: run, tool: tool, phase: .result,
            operation: operation, path: path, trashedPath: trashedPath, identity: identity, bytes: bytes, tier: tier,
            status: status, detail: detail)
    }

    // MARK: - JSON Lines

    /// Timestamps are ISO 8601 in UTC, with milliseconds so records written in the same second keep their order.
    private static let timestampFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// The record as one line of JSON, without the line break.
    func jsonLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.timestampFormat))
        }
        return try encoder.encode(self)
    }

    /// Decodes one line of the log. Returns `nil` for a line that is not a record this version can read.
    static func decode(line: Data) -> Self? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? timestampFormat.parse(text) { return date }
            return try Date.ISO8601FormatStyle().parse(text)
        }
        guard let record = try? decoder.decode(Self.self, from: line), record.version == currentVersion else {
            return nil
        }
        return record
    }
}
