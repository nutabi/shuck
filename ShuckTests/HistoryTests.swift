import Foundation
import ShuckExecution
import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// The History page's model and wording (HIS-002, HIS-004, SAF-011).
///
/// The log is a stub, so these tests never touch the file system. The engine's fixture tests read a real log
/// (`HistoryRunTests`), and the UI test opens History after a real run.
@MainActor
struct HistoryTests {
    let home = URL(filePath: "/StubHome", directoryHint: .isDirectory)

    func item(
        _ outcome: HistoryRun.Item.Outcome, restorability: Restorability? = nil,
        operation: HistoryRecord.Operation = .trash
    ) -> HistoryRun.Item {
        HistoryRun.Item(
            operation: operation, path: "/StubHome/Movies/clip.mov", trashedPath: nil, bytes: 100, tier: .yourData,
            outcome: outcome,
            restorability: restorability)
    }

    func run(_ items: [HistoryRun.Item], tool: ToolID = .largeFiles) -> HistoryRun {
        HistoryRun(id: UUID(), tool: tool, started: .now, items: items)
    }

    @Test func reloadShowsTheLogAndThenItsChanges() async {
        let first = HistoryModel.History(runs: [run([item(.succeeded)])], unreadableLineCount: 0)
        let second = HistoryModel.History(runs: [run([item(.succeeded)])] + first.runs, unreadableLineCount: 1)
        let loads = Mutex([first, second])
        let model = HistoryModel(home: home) { () async throws(HistoryError) -> HistoryModel.History in
            loads.withLock { $0.removeFirst() }
        }
        #expect(model.state == .loading)

        await model.reload()
        #expect(model.state == .loaded(first))
        await model.reload()
        #expect(model.state == .loaded(second))
    }

    @Test func aLogThatCannotBeReadIsReported() async {
        let failure = HistoryError.cannotRead("/StubHome/Library/Application Support/me.nutabi.shuck", "denied")
        let model = HistoryModel(home: home) { () async throws(HistoryError) -> HistoryModel.History in
            throw failure
        }

        await model.reload()
        #expect(model.state == .failed(failure))
    }

    @Test func showingARunInHistorySelectsHistoryAndRemembersTheRun() {
        let navigation = AppNavigation()
        let id = UUID()

        navigation.showHistory(revealing: id)
        #expect(navigation.selection == .history)
        #expect(navigation.revealedRun == id)
    }

    /// HIS-002: a run's area comes from the registry, and a restore's is Restore.
    @Test func aRunsAreaIsItsSubToolsNameHIS002() {
        #expect(HistoryView.area(of: run([]), in: .standard) == "Large Files")
        #expect(HistoryView.area(of: run([], tool: .history), in: .standard) == "Restore")
        #expect(HistoryView.area(of: run([], tool: ToolID(rawValue: "XYZ")), in: .standard) == "XYZ")
    }

    /// HIS-002, SAF-011: a run's status says whether every item succeeded, and an interrupted run says so.
    @Test func aRunsStatusCountsWhatWasDoneHIS002() {
        #expect(
            String(localized: HistoryView.status(of: run([item(.succeeded), item(.succeeded)])).text) == "Completed")
        #expect(
            String(localized: HistoryView.status(of: run([item(.succeeded), item(.skipped("missing"))])).text)
                == "1 of 2 done")
        #expect(
            String(localized: HistoryView.status(of: run([item(.succeeded), item(.interrupted)])).text) == "Interrupted"
        )
    }

    /// HIS-004, SAF-006: permanent deletions are shown as not restorable, and Restore offers nothing for them.
    @Test func aDeletedItemIsNotRestorableHIS004SAF006() {
        let deleted = run(
            [
                item(.succeeded, restorability: .permanent, operation: .delete),
                item(.skipped("missing"), operation: .delete),
            ],
            tool: .developerJunk)

        #expect(deleted.restorableItems.isEmpty)
        #expect(OutcomeWording.method(of: deleted) == "Deleted permanently")
        #expect(String(localized: HistoryView.status(of: deleted.items[0])) == "Not restorable")
        #expect(HistoryView.area(of: deleted, in: .standard) == "Developer Junk")
    }

    /// HIS-002: a run is labelled by its items' one operation, or by every operation they used (D-90).
    @Test func aRunsMethodComesFromItsItemsHIS002() {
        #expect(OutcomeWording.method(of: run([item(.succeeded), item(.succeeded)])) == "Moved to the Trash")
        let restore = run([item(.succeeded, operation: .restore)], tool: .history)
        #expect(OutcomeWording.method(of: restore) == "Moved back from the Trash")
        let mixed = run([
            item(.succeeded, operation: .delete), item(.succeeded, operation: .tool),
            item(.succeeded, operation: .delete),
        ])
        #expect(OutcomeWording.method(of: mixed) == "Deleted permanently and cleaned by tools")
        let uninstall = run([
            item(.succeeded, operation: .launchctl), item(.succeeded, operation: .trash),
            item(.succeeded, operation: .tool),
        ])
        #expect(
            OutcomeWording.method(of: uninstall) == "Changed with launchctl, moved to the Trash, and cleaned by tools")
    }

    /// One logged item and the words History shows for it.
    struct StatusCase: Sendable {
        let outcome: HistoryRun.Item.Outcome
        let operation: HistoryRecord.Operation
        var restorability: Restorability?
        let text: String

        init(
            _ outcome: HistoryRun.Item.Outcome, _ operation: HistoryRecord.Operation,
            restorability: Restorability? = nil,
            _ text: String
        ) {
            self.outcome = outcome
            self.operation = operation
            self.restorability = restorability
            self.text = text
        }

        init(_ outcome: HistoryRun.Item.Outcome, restorability: Restorability? = nil, _ text: String) {
            self.init(outcome, .trash, restorability: restorability, text)
        }
    }

    nonisolated static func toolEnd(_ domain: String, _ code: Int) -> HistoryRun.Item.Outcome {
        .failed(ActionError(domain: domain, code: code, message: "x").logged)
    }

    /// HIS-004, SAF-011, DEV-004, SET-001, APP-011, NFR-L10N-001: each item says whether Restore can put it back, its
    /// logged skip reason reads as words, as this version and Shuck 0.1.0 wrote them, and a failure shows its error's
    /// description, a tool's end its status (D-88, D-115). A reason the app does not know is shown as logged.
    @Test(arguments: [
        StatusCase(.succeeded, restorability: .trashEmptied, "Not restorable (Trash emptied)"),
        StatusCase(.succeeded, restorability: .restored, "Restored"),
        StatusCase(.succeeded, restorability: .permanent, "Not restorable"),
        StatusCase(.succeeded, "Moved back"),
        StatusCase(.interrupted, "Interrupted before its outcome was recorded"),
        StatusCase(.skipped("missing"), "Skipped: no longer there"),
        StatusCase(.skipped("missing"), .restore, "Skipped: no longer in the Trash"),
        StatusCase(.skipped("notAccessible"), "Skipped: not accessible"),
        StatusCase(.skipped("changed: file, 4096 bytes"), "Skipped: changed since the scan"),
        StatusCase(
            .skipped("changed: file, 4096 bytes"), .restore, "Skipped: changed since it was moved to the Trash"),
        StatusCase(.skipped("rejected: outsideAllowedRoots"), "Skipped: failed a safety check"),
        StatusCase(
            .skipped("userExclusion: /Users/someone/Documents/Keep"),
            "Skipped: it is in a folder you excluded in Settings"),
        StatusCase(.skipped("unsupportedMethod: tool"), .tool, "Skipped: this version of Shuck can't do this"),
        StatusCase(.skipped("notAllowed: delete"), .delete, "Skipped: not allowed for this kind of item"),
        StatusCase(.skipped("dependencyNotDone: com.example.job"), "Skipped: an item it needs was not done"),
        StatusCase(.skipped("originalTaken"), .restore, "Skipped: its original place is taken"),
        StatusCase(
            .skipped("otherItem"), .restore, "Skipped: no longer in the Trash, and another item has its name"),
        StatusCase(.skipped("somethingNew"), "Skipped: somethingNew"),
        StatusCase(.skipped(nil), "Skipped"),
        // Shuck 0.1.0 logged Swift's description of a reason, and only a failure's description.
        StatusCase(
            .skipped("changed(ShuckKit.ItemSnapshot(kind: ShuckKit.ItemSnapshot.Kind.file, allocatedSize: 4))"),
            "Skipped: changed since the scan"),
        StatusCase(
            .skipped(#"rejected(ShuckKit.PathGuardError.outsideAllowedRoots("/x/y"))"#),
            "Skipped: failed a safety check"),
        StatusCase(.failed("denied"), "Failed: denied"),
        StatusCase(.failed(ActionError(errno: EACCES).logged), "Failed: Permission denied"),
        StatusCase(.failed(nil), "Failed"),
        StatusCase(toolEnd("ShuckToolExit", 3), .tool, "Failed: the tool ended with status 3"),
        StatusCase(toolEnd("ShuckToolSignal", 9), .tool, "Failed: the tool was ended by signal 9"),
        StatusCase(
            toolEnd("ShuckToolTimeout", 600), .tool,
            "Failed: the tool did not finish in 600 seconds, so Shuck stopped it"),
        StatusCase(toolEnd("ShuckToolStopped", 15), .tool, "Stopped before the tool finished"),
    ])
    func anItemReadsAsWordsHIS004SAF011DEV004SET001APP011(_ row: StatusCase) {
        let shown = HistoryView.status(
            of: item(row.outcome, restorability: row.restorability, operation: row.operation))
        #expect(String(localized: shown) == row.text)
    }

    /// SAF-011, D-90: the summaries of a run say why an item was or was not acted on, in the words History uses for the
    /// same code.
    @Test func aRunsSummaryUsesTheWordsOfHistorySAF011() {
        func text(_ result: ItemOutcome.Result, method: ActionMethod = .trash) -> String {
            let item = PlannedItem(
                url: home.appending(path: "Movies/clip.mov"), tier: .yourData, method: method,
                snapshot: ItemSnapshot(kind: .file, allocatedSize: 10))
            return String(localized: OutcomeWording.result(of: ItemOutcome(item: item, result: result)))
        }

        #expect(text(.done(nil), method: .delete) == "Deleted permanently")
        #expect(text(.skipped(.missing)) == "Skipped: no longer there")
        #expect(text(.skipped(.notAccessible)) == "Skipped: not accessible")
        #expect(
            text(.skipped(.changed(ItemSnapshot(kind: .file, allocatedSize: 20)))) == "Skipped: changed since the scan")
        #expect(text(.skipped(.modifiedSinceScan)) == "Skipped: modified since the scan")
        #expect(text(.skipped(.appRunning)) == "Skipped: its app was running")
        #expect(text(.skipped(.cancelled)) == "Skipped: stopped before it was acted on")
        #expect(
            text(.skipped(.unsupportedMethod(.tool)), method: .tool) == "Skipped: this version of Shuck can't do this")
        #expect(text(.skipped(.notAllowed(.delete)), method: .delete) == "Skipped: not allowed for this kind of item")
        #expect(text(.failed(ActionError(errno: EACCES))) == "Failed: Permission denied")
        #expect(
            text(.skipped(.missing)) == String(localized: HistoryView.status(of: item(.skipped("missing")))))
    }

    /// An item at `path`, of `operation`, as the log holds it.
    private func display(_ operation: HistoryRecord.Operation, path: String) -> HistoryItemDisplay {
        HistoryItemDisplay(
            HistoryRun.Item(
                operation: operation, path: path, trashedPath: nil, bytes: nil, tier: .rebuildable,
                outcome: .succeeded, restorability: nil),
            home: home)
    }

    /// HIS-002, #63: a trashed, deleted or restored item is a file, shown with its folder; a tool run shows the tool and
    /// its command, and the tool's own path, never a made-up folder; a launchctl change shows its job label.
    @Test func anItemShowsItsNameAndWhereItIsFromHIS002() throws {
        for operation in [HistoryRecord.Operation.trash, .delete, .restore] {
            let shown = display(operation, path: "/StubHome/Movies/clip.mov")
            #expect(shown == HistoryItemDisplay(title: "clip.mov", location: "~/Movies", isCommand: false))
        }
        let command = try ToolCommand(
            executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"],
            environment: ["PATH": "/usr/bin"])
        #expect(
            display(.tool, path: command.display)
                == HistoryItemDisplay(
                    title: "xcrun simctl delete unavailable", location: "/usr/bin/xcrun", isCommand: true))
        // A record that is not a quoted command is shown as logged, and not as a file.
        let unknown = display(.tool, path: "brew")
        #expect(unknown.title == "brew")
        #expect(unknown.isCommand)
        #expect(unknown.location == "Tool command")
        #expect(
            display(.launchctl, path: "com.example.agent")
                == HistoryItemDisplay(title: "com.example.agent", location: "Launchd job", isCommand: false))
    }

    /// The sheets and the History page word a reason the same, from its code (D-90).
    @Test func theSheetsAndHistoryShareTheirWordsSAF011() {
        for code in SkipCode.allCases {
            for operation in [HistoryRecord.Operation.trash, .restore] {
                #expect(
                    String(localized: OutcomeWording.skipped(code, operation: operation))
                        == String(localized: OutcomeWording.skipped(detail: code.logged("x"), operation: operation)))
            }
        }
    }

    /// TD-16: a history log error reads as a message, with its path apart, never as Swift's description of it.
    @Test func historyErrorsReadAsWords() {
        let path = "/StubHome/Library/Application Support/me.nutabi.shuck/history.jsonl"
        let errors: [HistoryError] = [
            .notAFolder(path), .notARegularFile(path), .cannotPrepareFolder(path, "x"), .cannotOpen(path, errno: ELOOP),
            .cannotOpen(path, errno: EACCES), .cannotOpen(path, errno: EIO), .cannotWrite(path, "x"),
            .cannotRead(path, "x"),
        ]
        let messages = errors.map { OutcomeWording.message($0) }

        #expect(messages.allSatisfy { $0.path == path })
        #expect(Set(messages.map { String(localized: $0.text) }).count == errors.count)
        #expect(messages.allSatisfy { !String(localized: $0.text).contains(path) })
        #expect(String(localized: messages[7].text) == "Shuck couldn't read its history log.")
    }
}
