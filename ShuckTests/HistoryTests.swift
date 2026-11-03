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
        #expect(String(localized: HistoryView.area(of: run([]), in: .standard)) == "Large Files")
        #expect(String(localized: HistoryView.area(of: run([], tool: .history), in: .standard)) == "Restore")
        #expect(String(localized: HistoryView.area(of: run([], tool: ToolID(rawValue: "XYZ")), in: .standard)) == "XYZ")
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

    /// HIS-004: each item says whether Restore can put it back.
    @Test func anItemSaysWhetherRestoreCanPutItBackHIS004() {
        #expect(
            String(localized: HistoryView.status(of: item(.succeeded, restorability: .trashEmptied)))
                == "Not restorable (Trash emptied)")
        #expect(String(localized: HistoryView.status(of: item(.skipped("missing")))) == "Skipped: no longer there")
        #expect(String(localized: HistoryView.status(of: item(.succeeded, restorability: .restored))) == "Restored")
        #expect(
            String(localized: HistoryView.status(of: item(.succeeded, restorability: .permanent))) == "Not restorable")
        #expect(String(localized: HistoryView.status(of: item(.succeeded))) == "Moved back")
        #expect(
            String(localized: HistoryView.status(of: item(.interrupted)))
                == "Interrupted before its outcome was recorded")
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

    /// SAF-011: logged skip reasons read as words, as this version and Shuck 0.1.0 wrote them (D-88); one the app does
    /// not know is shown as logged.
    @Test func skipReasonsReadAsWordsSAF011() {
        func text(_ detail: String?, _ operation: HistoryRecord.Operation = .trash) -> String {
            String(localized: HistoryView.status(of: item(.skipped(detail), operation: operation)))
        }

        #expect(text("missing") == "Skipped: no longer there")
        #expect(text("missing", .restore) == "Skipped: no longer in the Trash")
        #expect(text("notAccessible") == "Skipped: not accessible")
        #expect(text("changed: file, 4096 bytes") == "Skipped: changed since the scan")
        #expect(text("changed: file, 4096 bytes", .restore) == "Skipped: changed since it was moved to the Trash")
        #expect(text("rejected: outsideAllowedRoots") == "Skipped: failed a safety check")
        #expect(text("unsupportedMethod: tool", .tool) == "Skipped: this version of Shuck can't do this")
        #expect(text("notAllowed: delete", .delete) == "Skipped: not allowed for this kind of item")
        #expect(text("originalTaken", .restore) == "Skipped: its original place is taken")
        #expect(text("otherItem", .restore) == "Skipped: no longer in the Trash, and another item has its name")
        #expect(text("somethingNew") == "Skipped: somethingNew")
        #expect(text(nil) == "Skipped")
    }

    /// SAF-011: Shuck 0.1.0 logged Swift's description of a reason; its code reads the same (D-88).
    @Test func reasonsLoggedByShuck010ReadTheSameSAF011() {
        func text(_ outcome: HistoryRun.Item.Outcome) -> String {
            String(localized: HistoryView.status(of: item(outcome)))
        }

        #expect(
            text(.skipped("changed(ShuckKit.ItemSnapshot(kind: ShuckKit.ItemSnapshot.Kind.file, allocatedSize: 4))"))
                == "Skipped: changed since the scan")
        #expect(
            text(.skipped(#"rejected(ShuckKit.PathGuardError.outsideAllowedRoots("/x/y"))"#))
                == "Skipped: failed a safety check")
        // A failure's description is all 0.1.0 logged, so it is shown as logged.
        #expect(text(.failed("denied")) == "Failed: denied")
    }

    /// SAF-011, NFR-L10N-001: a logged failure shows its error's description, without the domain and code.
    @Test func aLoggedFailureShowsItsDescriptionSAF011() {
        let error = ActionError(errno: EACCES)
        #expect(String(localized: HistoryView.status(of: item(.failed(error.logged)))) == "Failed: Permission denied")
        #expect(String(localized: HistoryView.status(of: item(.failed(nil)))) == "Failed")
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
