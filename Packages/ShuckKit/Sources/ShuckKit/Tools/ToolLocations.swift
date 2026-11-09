import Foundation

/// Where Developer Junk finds a tool, and the command it builds for it (DEV-002, DEV-004).
///
/// A tool is found at an absolute path under the scan's tool root, which is `/` in the app and the fixture root in a UI
/// test (D-124). Shuck looks only where each tool is installed by the usual ways, in order, and never searches the
/// user's `PATH`: it runs a program by a path it can name in the review. A tool installed somewhere else is not found,
/// and its rule is hidden.
struct ToolLocations {
    /// The folders Homebrew puts its tools in on Apple silicon, then on Intel Macs' default. Shuck runs only on Apple
    /// silicon, but a Homebrew moved from an Intel Mac keeps the second.
    static let homebrewFolders = ["opt/homebrew/bin", "usr/local/bin"]
    /// The command's `PATH`: what a tool started from Terminal would find first, such as a Homebrew `node` for `npm`.
    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// The two variables a command's environment has.
    static let pathVariable = "PATH"
    static let homeVariable = "HOME"

    let root: URL
    let home: URL

    /// The locations for a scan, or `nil` if it looks for no tools.
    init?(_ context: ScanContext) {
        guard let root = context.toolRoot else { return nil }
        self.root = root
        home = context.home
    }

    /// The path of the tool called `name` in the first of `folders` (relative to the tool root) where it can run. If it
    /// runs in none, the first one's path, so a rule built for it is hidden by its detection (DEV-002).
    func executable(_ name: String, in folders: [String]) -> String {
        executable([name], in: folders)
    }

    /// The path of the first of `names`, in order, that can run in one of `folders`: a tool that goes by more than one
    /// name, such as pip's `pip` and `pip3`. If none runs, the first name's first path (DEV-002).
    func executable(_ names: [String], in folders: [String]) -> String {
        let paths = names.flatMap { name in folders.map { root.appending(path: "\($0)/\(name)").path } }
        return paths.first { CleanupRule.Detection.executable($0).isAvailable } ?? paths.first ?? ""
    }

    /// The command that runs `executable` with `arguments`: nothing of the app's environment, only `PATH` and `HOME`,
    /// which the tool needs to find its cache (DEV-004).
    func command(_ executable: String, _ arguments: [String]) throws(RuleError) -> ToolCommand {
        do {
            return try ToolCommand(
                executable: executable, arguments: arguments,
                environment: [Self.pathVariable: Self.searchPath, Self.homeVariable: home.path])
        } catch {
            throw .invalidDetection
        }
    }
}
