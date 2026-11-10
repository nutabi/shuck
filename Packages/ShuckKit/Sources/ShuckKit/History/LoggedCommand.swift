import Foundation

/// A tool command as the history log records it, read back for display (HIS-002, #63).
///
/// A `tool` record's `path` holds the command's display form: each word in single quotes, as ``ToolCommand/display``
/// writes it. This is for showing the command only. Nothing is run or chosen from it (R-07).
public struct LoggedCommand: Equatable, Sendable {
    /// The executable's absolute path.
    public let executable: String
    public let arguments: [String]

    /// The tool's name: the executable's file name, such as `xcrun`.
    public var tool: String { URL(filePath: executable).lastPathComponent }

    /// The tool and its arguments without paths or quotes, such as `xcrun simctl delete unavailable`.
    public var commandLine: String { ([tool] + arguments).joined(separator: " ") }

    /// The command `logged` records, or `nil` for text that is not a quoted command, such as a path or a job label.
    public init?(logged: String) {
        var words: [String] = []
        var word = ""
        var inQuote = false
        var hasWord = false
        var escaped = false
        for character in logged {
            if inQuote {
                if character == "'" { inQuote = false } else { word.append(character) }
            } else if escaped {
                // `'\''` is how a single quote inside a quoted word is written.
                word.append(character)
                escaped = false
            } else if character == "'" {
                inQuote = true
                hasWord = true
            } else if character == "\\" {
                guard hasWord else { return nil }
                escaped = true
            } else if character == " " {
                guard hasWord else { return nil }
                words.append(word)
                word = ""
                hasWord = false
            } else {
                return nil
            }
        }
        guard !inQuote, !escaped, hasWord else { return nil }
        words.append(word)
        guard let executable = words.first, executable.hasPrefix("/") else { return nil }
        self.executable = executable
        arguments = Array(words.dropFirst())
    }
}

/// A tool run's `detail`, split into its summary and the tool's output (D-115).
struct ToolRunDetail: Equatable {
    /// What follows the summary when the tool printed anything.
    static let outputMarker = "; output: "

    /// `exit 0`, or the failure as `<domain> <code>: <message>`, which History words.
    let summary: String
    /// The end of the tool's output, marked with `…` when cut.
    let output: String?

    init(_ detail: String) {
        if let marker = detail.range(of: Self.outputMarker) {
            summary = String(detail[..<marker.lowerBound])
            output = String(detail[marker.upperBound...])
        } else {
            summary = detail
            output = nil
        }
    }
}
