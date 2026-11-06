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

    /// The exact executable and arguments, quoted for display only. Never pass this string to a shell.
    public var display: String {
        ([executable] + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(
            separator: " ")
    }
}

public enum ToolCommandError: Error, Equatable {
    case invalidExecutable
    case invalidArgumentsOrEnvironment
    case invalidTimeout
}
