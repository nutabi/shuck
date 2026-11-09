import Foundation
import ShuckKit

/// What the History page shows for one logged item: a name and, under it, where it is (HIS-002, #63).
///
/// The log's `path` is not always a file path (PRD section 8.5). It is a file for `trash`, `delete` and `restore`; the
/// quoted command for `tool`; and the job label for `launchctl`. Each is shown as what it is: a file with its folder, a
/// command with the tool's own path, a job with its kind. A file name read from a command would be a made-up folder.
nonisolated struct HistoryItemDisplay: Equatable {
    /// The file or job name, or the command without paths or quotes (`xcrun simctl delete unavailable`).
    let title: String
    /// Where the file is, the full path of the tool, or what kind of item a job label names.
    let location: String
    /// Whether the title is a command, which the page sets in a fixed-width font.
    let isCommand: Bool

    init(title: String, location: String, isCommand: Bool) {
        self.title = title
        self.location = location
        self.isCommand = isCommand
    }

    init(_ item: HistoryRun.Item, home: URL) {
        switch item.operation {
        case .trash, .delete, .restore:
            let url = URL(filePath: item.path)
            title = url.lastPathComponent
            location = ResultRow.folder(of: url, home: home)
            isCommand = false
        case .tool:
            if let command = LoggedCommand(logged: item.path) {
                title = command.commandLine
                location = command.executable
                isCommand = true
            } else {
                // A record Shuck did not write in this form: shown as logged, never as a file.
                title = item.path
                location = String(localized: "Tool command")
                isCommand = true
            }
        case .launchctl:
            title = item.path
            location = String(localized: "Launchd job")
            isCommand = false
        }
    }
}
