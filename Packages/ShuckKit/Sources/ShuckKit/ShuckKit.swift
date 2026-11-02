import os

/// Shuck's engine: tools, scanning, rules, planning, safety and history (PRD section 11.1).
///
/// Nothing here deletes, moves or modifies user files or launchd state; that is ShuckExecution's job (SAF-017).
public enum ShuckKit {
    /// The release build's bundle ID (D-21).
    public static let bundleID = "me.nutabi.shuck"

    /// The debug build's bundle ID, so a debug build keeps its own preferences and data folder (D-70).
    public static let debugBundleID = "me.nutabi.shuck.debug"

    /// The `Logger` subsystem for all of Shuck's diagnostics (NFR-OBS-001). Debug builds use it too (D-70). A tool's
    /// or sub-tool's diagnostics use `Logger(tool:)`.
    public static let loggerSubsystem = bundleID

    /// The data folder of the build with `bundleID`, relative to the home folder (D-70). It holds the history log
    /// (section 8.5).
    public static func dataFolder(bundleID: String) -> String {
        "Library/Application Support/\(bundleID)"
    }
}

extension Logger {
    /// A logger for the diagnostics of `tool`, in a category of its own (NFR-OBS-001). Code that runs for several
    /// tools, such as an executor or a shared scan, logs under the tool it is running for.
    public init(tool: ToolID) {
        self.init(subsystem: ShuckKit.loggerSubsystem, category: tool.loggerCategory)
    }
}
