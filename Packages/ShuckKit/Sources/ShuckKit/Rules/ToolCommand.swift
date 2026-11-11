import Foundation

/// A tool's documented cleanup command, kept as arguments rather than shell text (DEV-004). This is data only;
/// only ShuckExecution may run it, once M2-T10 adds the runner.
public struct ToolCommand: Equatable, Hashable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let timeout: TimeInterval

    public init(
        executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval = 600
    ) throws(ToolCommandError) {
        guard executable.hasPrefix("/"), !executable.contains("\0"),
            !executable.split(separator: "/").contains("..")
        else { throw .invalidExecutable }
        guard !arguments.contains(where: { $0.contains("\0") }),
            environment["PATH"]?.isEmpty == false,
            environment.allSatisfy({
                !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.contains("\0") && !$0.value.contains("\0")
            })
        else { throw .invalidArgumentsOrEnvironment }
        guard timeout.isFinite, timeout > 0 else { throw .invalidTimeout }
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
    }

    /// The exact executable and arguments, each in single quotes. The history log records this form and
    /// ``LoggedCommand`` reads it back, so it never changes. Never pass this string to a shell.
    public var display: String {
        ([executable] + arguments).map(Self.quoted).joined(separator: " ")
    }

    /// The exact executable and arguments as people read them, such as `/opt/homebrew/bin/npm cache clean --force`.
    /// Only a word that would otherwise be misread, such as one with a space or a quote, is quoted (D-138). For
    /// display only; never pass this string to a shell.
    public var commandLine: String {
        ([executable] + arguments).map { Self.isPlain($0) ? $0 : Self.quoted($0) }.joined(separator: " ")
    }

    private static func quoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Whether a word reads the same without quotes: not empty, and only letters, digits and `_@%+=:,./-`.
    private static func isPlain(_ word: String) -> Bool {
        !word.isEmpty
            && word.unicodeScalars.allSatisfy {
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "_@%+=:,./-".unicodeScalars.contains($0))
            }
    }
}

public enum ToolCommandError: Error, Equatable {
    case invalidExecutable
    case invalidArgumentsOrEnvironment
    case invalidTimeout
}
