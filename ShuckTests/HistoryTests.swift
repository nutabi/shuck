import Foundation
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

    func item(_ outcome: HistoryRun.Item.Outcome, restorability: Restorability? = nil) -> HistoryRun.Item {
        HistoryRun.Item(
            path: "/StubHome/Movies/clip.mov", trashedPath: nil, bytes: 100, tier: .yourData, outcome: outcome,
            restorability: restorability)
    }

    func run(_ items: [HistoryRun.Item], tool: ToolID = .largeFiles) -> HistoryRun {
        HistoryRun(id: UUID(), tool: tool, operation: .trash, started: .now, items: items)
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

    /// SAF-011: logged skip reasons read as words, as this version and Shuck 0.1.0 wrote them (D-88); one the app does
    /// not know is shown as logged.
    @Test func skipReasonsReadAsWordsSAF011() {
        #expect(String(localized: HistoryView.skipReason("missing")) == "no longer there")
        #expect(String(localized: HistoryView.skipReason("notAccessible")) == "not accessible")
        #expect(String(localized: HistoryView.skipReason("changed: file, 4096 bytes")) == "changed since the scan")
        #expect(
            String(
                localized: HistoryView.skipReason(
                    "changed(ShuckKit.ItemSnapshot(kind: ShuckKit.ItemSnapshot.Kind.file, allocatedSize: 4))"))
                == "changed since the scan")
        #expect(
            String(localized: HistoryView.skipReason(#"rejected(ShuckKit.PathGuardError.outsideAllowedRoots("/x/y"))"#))
                == "failed a safety check")
        #expect(String(localized: HistoryView.skipReason("originalTaken")) == "its original place is taken")
        #expect(String(localized: HistoryView.skipReason("otherItem")) == "another item has its name in the Trash")
        #expect(String(localized: HistoryView.skipReason("somethingNew")) == "somethingNew")
    }
}
