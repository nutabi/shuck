import ShuckKit
import os

extension Logger {
    /// The app's own diagnostics, which belong to no one tool: launch errors, refused plans and failed history reads
    /// (NFR-OBS-001). The engine logs a tool's scans and runs under that tool's category.
    nonisolated static let app = Logger(subsystem: ShuckKit.loggerSubsystem, category: "App")
}
