import ShuckExecution
import ShuckKit
import SwiftUI

/// What happened to an item, in words: the one table from the log's codes to text, used by both run sheets and the
/// History page (SAF-011, D-90).
///
/// A skip's words come from its stable code (D-88), so a reason reads the same live and in History, and in a log
/// written by Shuck 0.1.0.
nonisolated enum OutcomeWording {
    /// What each operation does, as a run or an item on the History page shows it (HIS-002).
    static func method(_ operation: HistoryRecord.Operation) -> LocalizedStringResource {
        switch operation {
        case .trash: "Moved to the Trash"
        case .delete: "Deleted permanently"
        case .tool: "Cleaned by its tool"
        case .launchctl: "Changed with launchctl"
        case .restore: "Moved back from the Trash"
        }
    }

    /// What a run did: its items' one operation, or every operation they used, joined as a list (HIS-002, SAF-006).
    static func method(of run: HistoryRun) -> String {
        let operations = run.operations
        guard operations.count > 1 else { return operations.first.map { String(localized: method($0)) } ?? "" }
        let list = operations.map { String(localized: part($0)) }.formatted(.list(type: .and))
        return list.prefix(1).localizedUppercase + list.dropFirst()
    }

    /// An operation as one part of a run's combined method: "Deleted permanently and cleaned by tools".
    private static func part(_ operation: HistoryRecord.Operation) -> LocalizedStringResource {
        switch operation {
        case .trash: "moved to the Trash"
        case .delete: "deleted permanently"
        case .tool: "cleaned by tools"
        case .launchctl: "changed with launchctl"
        case .restore: "moved back from the Trash"
        }
    }

    /// Why an item was skipped. `operation` is what was to be done to it: an item to restore was in the Trash, so a
    /// missing one is "no longer in the Trash" where another is "no longer there".
    static func skipped(_ code: SkipCode, operation: HistoryRecord.Operation) -> LocalizedStringResource {
        let isRestore = operation == .restore
        switch code {
        case .missing: return isRestore ? "Skipped: no longer in the Trash" : "Skipped: no longer there"
        case .notAccessible: return "Skipped: not accessible"
        case .changed:
            return isRestore ? "Skipped: changed since it was moved to the Trash" : "Skipped: changed since the scan"
        case .replaced: return "Skipped: another file took its place since the scan"
        case .ruleChanged: return "Skipped: no longer matches the cleanup rule"
        case .modifiedSinceScan: return "Skipped: modified since the scan"
        case .rejected: return "Skipped: failed a safety check"
        case .cancelled:
            return isRestore ? "Skipped: stopped before it was restored" : "Skipped: stopped before it was acted on"
        case .historyUnavailable: return "Skipped: the history log stopped working"
        case .unsupportedMethod: return "Skipped: this version of Shuck can't do this"
        case .notAllowed: return "Skipped: not allowed for this kind of item"
        case .originalTaken: return "Skipped: its original place is taken"
        case .notInTrash: return "Skipped: not in the Trash"
        case .otherItem: return "Skipped: no longer in the Trash, and another item has its name"
        }
    }

    /// A logged skip. A code this version does not know is shown as logged.
    static func skipped(detail: String?, operation: HistoryRecord.Operation) -> LocalizedStringResource {
        if let code = detail.flatMap(SkipCode.init(detail:)) { return skipped(code, operation: operation) }
        return detail.map { "Skipped: \($0)" } ?? "Skipped"
    }

    /// Why an action failed, in the error's localized description (NFR-L10N-001).
    static func failed(_ error: ActionError) -> LocalizedStringResource {
        "Failed: \(error.localizedDescription)"
    }

    /// A logged failure: its error's description, without the domain and code the log keeps (D-88). Other text, as
    /// Shuck 0.1.0 logged it, is shown as logged.
    static func failed(detail: String?) -> LocalizedStringResource {
        if let error = detail.flatMap(ActionError.init(logged:)) { return failed(error) }
        return detail.map { "Failed: \($0)" } ?? "Failed"
    }

    /// What went wrong with the history log, and the path it happened at (TD-16).
    static func message(_ error: HistoryError) -> (text: LocalizedStringResource, path: String) {
        switch error {
        case .notAFolder(let path):
            ("Something other than a folder is where Shuck keeps its data.", path)
        case .notARegularFile(let path):
            ("Something other than a file is where Shuck keeps its history log.", path)
        case .cannotPrepareFolder(let path, _):
            ("Shuck couldn't create its data folder or limit who can read it.", path)
        case .cannotOpen(let path, errno: ELOOP):
            ("The history log is a link to another place, so Shuck doesn't open it.", path)
        case .cannotOpen(let path, errno: EACCES), .cannotOpen(let path, errno: EPERM):
            ("Shuck isn't allowed to open its history log.", path)
        case .cannotOpen(let path, _):
            ("Shuck couldn't open its history log.", path)
        case .cannotWrite(let path, _):
            ("Shuck couldn't write to its history log.", path)
        case .cannotRead(let path, _):
            ("Shuck couldn't read its history log.", path)
        }
    }
}

/// A history log error's message, with its path on a second line that can be selected and copied (TD-16).
struct HistoryErrorText: View {
    let error: HistoryError

    var body: some View {
        let message = OutcomeWording.message(error)
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
            Text(verbatim: message.path)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
