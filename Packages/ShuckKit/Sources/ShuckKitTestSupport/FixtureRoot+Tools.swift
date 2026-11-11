import Foundation

/// What a fake tool does when the tool runner starts it (DEV-004).
///
/// Every fake is a script with a `#!/bin/sh` line that the executor runs by its absolute path, as it runs a real tool.
/// Tests never start it themselves: only `ShuckExecution` starts subprocesses (D-82).
public enum FakeTool: Sendable {
    /// Prints `output` and ends with `status`.
    case exits(Int32, output: String = "")
    /// Prints its arguments, one `arg=value` per line, then its environment, one `NAME=value` per line, and ends with
    /// 0. It also creates `Marks/ran` in the root, to show that it ran (``FixtureRoot/aFakeToolRan``).
    case reportsInvocation
    /// Prints `bytes` bytes of text, then `last`, and ends with 0.
    case printsALot(bytes: Int, last: String)
    /// Marks that it ran, then never ends by itself; it becomes `/bin/sleep`, so ending the process ends the script.
    case runsForever
    /// Marks that it ran, ignores the request to end (SIGTERM) and never ends by itself, so only SIGKILL stops it.
    case ignoresTerminate
}

extension FixtureRoot {
    /// Where a fake Xcode's `simctl` lies in the root: the developer folder `xcrun` uses when none is selected.
    public static let simctlPath = "Applications/Xcode.app/Contents/Developer/usr/bin/simctl"

    /// Creates a fake `xcrun` in `usr/bin` and the `simctl` of a fake Xcode, as on a Mac that has Xcode: Developer
    /// Junk lists its `xcrun simctl` rule only when the active developer folder has `simctl` (DEV-002). Returns
    /// `xcrun`'s location; the command runs `xcrun`, so only it behaves as `behavior` says.
    @discardableResult
    public func xcrun(_ behavior: FakeTool) throws(FixtureError) -> URL {
        try tool(Self.simctlPath, .exits(0))
        return try tool("usr/bin/xcrun", behavior)
    }

    /// Creates a fake tool at `relativePath` and returns its location.
    ///
    /// It is executable, and like every fixture it lies inside the root. A tool runner in the fixture-root mode finds
    /// tools only here (SAF-016).
    @discardableResult
    public func tool(_ relativePath: String, _ behavior: FakeTool) throws(FixtureError) -> URL {
        let target = try newItem(relativePath)
        let script = "#!/bin/sh\n" + Self.body(of: behavior, marks: try url("Marks").path) + "\n"
        guard
            FileManager.default.createFile(
                atPath: target.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        else { throw .fileSystem("Cannot create \(target.path)") }
        return target
    }

    /// Whether a ``FakeTool/reportsInvocation`` tool has run.
    public var aFakeToolRan: Bool {
        FileManager.default.fileExists(atPath: url.appending(path: "Marks/ran").path)
    }

    private static func body(of behavior: FakeTool, marks: String) -> String {
        switch behavior {
        case .exits(let status, let output):
            return (output.isEmpty ? "" : "printf '%s\\n' \(quoted(output))\n") + "exit \(status)"
        case .reportsInvocation:
            return """
                \(mark(marks))
                for argument in "$@"; do printf 'arg=%s\\n' "$argument"; done
                /usr/bin/env
                exit 0
                """
        case .printsALot(let bytes, let last):
            return """
                /usr/bin/head -c \(bytes) /dev/zero | /usr/bin/tr '\\0' 'x'
                printf '\\n%s\\n' \(quoted(last))
                exit 0
                """
        case .runsForever:
            return mark(marks) + "\nexec /bin/sleep 600"
        case .ignoresTerminate:
            return mark(marks) + "\ntrap '' TERM\nwhile :; do /bin/sleep 1; done"
        }
    }

    /// The command that creates `Marks/ran`.
    private static func mark(_ marks: String) -> String {
        "mkdir -p \(quoted(marks)) && : > \(quoted(marks + "/ran"))"
    }

    /// `text` as one single-quoted shell word.
    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
