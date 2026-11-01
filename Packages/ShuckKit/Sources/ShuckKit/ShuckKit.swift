/// Shuck's engine: tools, scanning, rules, planning, safety and history (PRD section 11.1).
///
/// Nothing here deletes, moves or modifies user files or launchd state; that is ShuckExecution's job (SAF-017).
public enum ShuckKit {
    /// The `Logger` subsystem for all of Shuck's diagnostics (NFR-OBS-001). Equal to the app's bundle ID (D-21).
    public static let loggerSubsystem = "me.nutabi.shuck"

    /// Shuck's data folder, relative to the home folder (D-21). It holds the history log (section 8.5).
    public static let dataFolder = "Library/Application Support/me.nutabi.shuck"
}
