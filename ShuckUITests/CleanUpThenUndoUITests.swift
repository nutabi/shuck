import ShuckKitTestSupport
import XCTest

/// Cleaning up, then undoing it: Move to Trash from Old Files and from Large Files, the runs in History, then Restore,
/// first for an item whose original place is taken again, then for the rest of the run.
final class CleanUpThenUndoUITests: ShuckUITestCase {
    @MainActor
    func testCleanUpThenUndo() throws {
        // Old Files lists only the installer, and Large Files lists all three, so each run empties its list.
        let holiday = try root.file("Movies/Holiday.mov", size: 5 << 20)
        let clip = try root.file("Movies/Clip.mov", size: 2 << 20)
        let installer = try root.file(
            "Downloads/Installer.dmg", size: 3 << 20, modified: .now.addingTimeInterval(-2 * 365 * 86_400))
        // Tests never use the real Trash: the app moves items into the fixture root's own (SAF-016, D-47).
        let trash = root.url.appending(path: ".Trash")
        // iCloud syncs the holiday movie, so Large Files marks it and the review warns (D-129).
        let app = launch(syncedFiles: ["Holiday.mov"])
        let sidebar = app.outlines.firstMatch
        let sheet = app.sheets.firstMatch

        step("Old Files: the review needs a selection, opens with ⌘⌫, and Cancel moves nothing (SAF-002)") {
            sidebar.staticTexts["Old Files"].click()
            XCTAssertTrue(app.staticTexts["Installer.dmg"].appears(within: 10))
            XCTAssertFalse(
                app.buttons["Move to Trash…"].isEnabled, "Nothing is selected, so there is nothing to review")

            app.staticTexts["Installer.dmg"].click()
            app.typeKey(.delete, modifierFlags: .command)
            XCTAssertTrue(sheet.staticTexts["Move 1 item, 3.1 MB, to the Trash?"].appears(within: 5))
            sheet.buttons["Cancel"].click()
            XCTAssertTrue(sheet.disappears(within: 5))
            XCTAssertTrue(FileManager.default.fileExists(atPath: installer.path))
        }

        step("Old Files: Move to Trash moves the selection into the Trash after the review (OLD-004, SAF-016)") {
            XCTAssertTrue(app.staticTexts["1 item selected, 3.1 MB"].exists, "Cancel cleared the selection")
            app.buttons["Move to Trash…"].click()
            XCTAssertTrue(sheet.staticTexts["Move 1 item, 3.1 MB, to the Trash?"].appears(within: 5))
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: installer.path), "The item moved before the confirmation")

            sheet.buttons["Move to Trash"].click()
            XCTAssertTrue(sheet.staticTexts["Moved 1 item to the Trash"].appears(within: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: installer.path), "Installer.dmg did not move")
            XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: "Installer.dmg").path))
        }

        step("Old Files: the summary stays though the run emptied the list, and Done shows the message (SAF-011)") {
            // The moved item left the list as the run ended, before the summary appeared, and the summary is still up.
            XCTAssertTrue(sheet.staticTexts["Moved 1 item to the Trash"].exists)
            attachScreenshot(of: app, named: "Old Files Move to Trash summary")

            sheet.buttons["Done"].click()
            XCTAssertTrue(sheet.disappears(within: 5))
            XCTAssertTrue(app.staticTexts["No files left unopened for 12 months"].appears(within: 5))
            XCTAssertFalse(app.buttons["Size"].exists, "An empty table is shown (D-61)")
        }

        step("Large Files no longer lists the file moved from Old Files, and marks the synced one (FCL-006, FCL-012)") {
            sidebar.staticTexts["Large Files"].click()
            // Old Files doesn't list the clip, so the page has changed before the rows are checked.
            XCTAssertTrue(app.staticTexts["Clip.mov"].appears(within: 5))
            XCTAssertTrue(app.staticTexts["Holiday.mov"].exists)
            XCTAssertFalse(app.staticTexts["Installer.dmg"].exists, "Large Files still lists the moved file")
            XCTAssertEqual(app.staticTexts.matching(identifier: "Synced").count, 1, "Only the synced file is marked")
        }

        step(
            "Large Files: the review lists the selection, warns about the synced file, then Move to Trash moves it "
                + "(LRG-004, SAF-002, SAF-016)"
        ) {
            app.staticTexts["Holiday.mov"].click()
            XCUIElement.perform(withKeyModifiers: .command) { app.staticTexts["Clip.mov"].click() }
            app.buttons["Move to Trash…"].click()
            XCTAssertTrue(sheet.staticTexts["Move 2 items, 7.3 MB, to the Trash?"].appears(within: 5))
            XCTAssertTrue(sheet.staticTexts["Holiday.mov"].exists)
            XCTAssertTrue(sheet.staticTexts["Clip.mov"].exists)
            let warning =
                "1 item is synced with iCloud. Moving it to the Trash also removes it from your other devices."
            XCTAssertTrue(sheet.staticTexts[warning].exists, "The review does not warn about the synced file (SAF-002)")
            XCTAssertTrue(sheet.staticTexts["Synced"].exists)
            XCTAssertTrue(FileManager.default.fileExists(atPath: holiday.path), "An item moved before the confirmation")
            attachScreenshot(of: app, named: "Move to Trash review")

            sheet.buttons["Move to Trash"].click()
            XCTAssertTrue(sheet.staticTexts["Moved 2 items to the Trash"].appears(within: 10))
            for file in [holiday, clip] {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent) did not move")
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: trash.appending(path: file.lastPathComponent).path))
            }
            attachScreenshot(of: app, named: "Move to Trash summary")
        }

        step("The summary opens its run in History, expanded to each item and what happened to it (HIS-002, HIS-004)") {
            sheet.buttons["Show in History"].click()
            let run = runRow(in: app, startingWith: "Large Files · Moved to the Trash")
            XCTAssertTrue(run.appears(within: 5), "The run is missing")
            XCTAssertTrue(run.label.contains(", 2 items, 7.3 MB, "), "Wrong count or size: \(run.label)")
            XCTAssertTrue(run.label.hasSuffix(", Completed"), "Wrong status: \(run.label)")
            XCTAssertTrue(app.staticTexts["Holiday.mov"].appears(within: 5), "The run is not expanded")
            XCTAssertTrue(app.staticTexts["Clip.mov"].exists)
            XCTAssertTrue(app.staticTexts["In the Trash"].exists)
            XCTAssertTrue(
                runRow(in: app, startingWith: "Old Files · Moved to the Trash").exists, "The first run is missing")
            attachScreenshot(of: app, named: "History with two runs")
        }

        try step("Restore asks once when the original place is taken, and Keep Both replaces nothing (HIS-003)") {
            let newer = try root.file("Movies/Holiday.mov", size: 1 << 20)
            let restored = root.url.appending(path: "Movies/Holiday (restored).mov")
            app.staticTexts["Holiday.mov"].click()
            XCTAssertTrue(app.staticTexts["1 item selected, 5.2 MB"].appears(within: 5))
            app.buttons["Restore"].click()
            XCTAssertTrue(sheet.staticTexts["The original place of 1 item is taken"].appears(within: 5))
            XCTAssertFalse(FileManager.default.fileExists(atPath: restored.path), "The item moved before the answer")
            attachScreenshot(of: app, named: "Restore question")

            sheet.buttons["Keep Both"].click()
            XCTAssertTrue(sheet.staticTexts["Restored 1 item"].appears(within: 10))
            XCTAssertTrue(sheet.staticTexts["Restored as “Holiday (restored).mov”"].exists)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: restored.path)[.size] as? Int, 5 << 20)
            XCTAssertEqual(
                try FileManager.default.attributesOfItem(atPath: newer.path)[.size] as? Int, 1 << 20,
                "The file at the original path was replaced")

            sheet.buttons["Done"].click()
            let restore = runRow(in: app, startingWith: "Restore · Moved back from the Trash")
            XCTAssertTrue(restore.appears(within: 5), "The restore is not listed as a run")
            XCTAssertTrue(app.staticTexts["Restored"].exists, "The restored item is not marked Restored")
        }

        step("Restore All puts the rest of the run back, with no question when nothing is in the way (HIS-003)") {
            app.buttons["Restore All"].click()
            XCTAssertTrue(sheet.staticTexts["Restored 1 item"].appears(within: 10))
            XCTAssertTrue(sheet.staticTexts["Restored"].exists)
            XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path), "Clip.mov is not back")
            let trashed = trash.appending(path: "Clip.mov")
            XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.path), "Clip.mov is still in the Trash")
            attachScreenshot(of: app, named: "Restore summary")

            sheet.buttons["Done"].click()
            XCTAssertTrue(app.buttons["Restore All"].disappears(within: 5), "A restored run still offers Restore All")
            let restores = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Restore · Moved back from the Trash"))
            XCTAssertEqual(restores.count, 2, "Each restore is listed as a run of its own")
        }
    }
}
