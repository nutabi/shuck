import Foundation
import ShuckKit
import Synchronization
import Testing

/// The running-app check that scans and the executor share (SAF-009, CAC-003, D-110).
struct RunningAppsTests {
    /// Counts each time the list is read, so a test can tell an item without apps never asks.
    final class Counting: RunningApps {
        private let reads = Mutex(0)
        var count: Int { reads.withLock { $0 } }

        func bundleIDs() -> Set<String> {
            reads.withLock { $0 += 1 }
            return ["com.apple.dt.xcode"]
        }
    }

    @Test func bundleIDsCompareWithoutCaseSAF009() {
        let running = StubRunningApps(["com.apple.dt.Xcode"])
        #expect(running.bundleIDs() == ["com.apple.dt.xcode"])
        #expect(running.firstRunning(of: ["COM.APPLE.DT.XCODE"]) == "COM.APPLE.DT.XCODE")
        #expect(running.firstRunning(of: ["com.apple.iphonesimulator"]) == nil)
    }

    @Test func anItemWithoutAppsNeverReadsTheListSAF009() {
        let counting = Counting()
        #expect(counting.firstRunning(of: []) == nil && counting.count == 0)
        #expect(ItemSelection.selected.unlessRunning([], in: counting) == .selected && counting.count == 0)
        #expect(counting.firstRunning(of: ["com.apple.dt.Xcode"]) == "com.apple.dt.Xcode" && counting.count == 1)
    }

    @Test func aRunningAppDisablesAnySelectionWithItsNoteCAC003() {
        let running = StubRunningApps(["com.example.Fixture"])
        for selection in [ItemSelection.selected, .unselected, .disabled("Other reason")] {
            #expect(selection.unlessRunning(["com.example.Fixture"], in: running) == .appIsRunning(nil))
            #expect(selection.unlessRunning(["com.example.Other"], in: running) == selection)
        }
        #expect(!ItemSelection.appIsRunning(nil).isSelectable)
        #expect(ItemSelection.appIsRunning(nil).disabledReason.map { String(localized: $0) } == "App is running")

        // The note names the app whose items are locked, since a row's own name may be another app's (D-138).
        let named = StubRunningApps(["com.apple.dt.Xcode"], names: ["com.apple.dt.Xcode": "Xcode"])
        let selection = ItemSelection.selected.unlessRunning(["com.apple.dt.Xcode"], in: named)
        #expect(!selection.isSelectable)
        #expect(selection.disabledReason.map { String(localized: $0) } == "Xcode is running")
        #expect(ItemSelection.appIsRunning("").disabledReason.map { String(localized: $0) } == "App is running")
    }
}
