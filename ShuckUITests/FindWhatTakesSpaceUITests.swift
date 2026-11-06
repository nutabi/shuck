import ShuckKitTestSupport
import XCTest

/// Finding what takes space: Scan All and the total on the File Cleanup landing page, then the Large Files list grouped,
/// sorted, selected and previewed, then the Old Files list.
final class FindWhatTakesSpaceUITests: ShuckUITestCase {
    @MainActor
    func testFindWhatTakesSpace() throws {
        let year: TimeInterval = 365 * 86_400
        try root.file("Movies/Holiday.mov", size: 5 << 20, modified: .now.addingTimeInterval(-3 * year))
        try root.file("Movies/Clip.mov", size: 2 << 20)
        try root.file("Downloads/Installer.dmg", size: 3 << 20, modified: .now.addingTimeInterval(-2 * year))
        try root.file("Documents/notes.txt", size: 10, modified: .now.addingTimeInterval(-5 * year))
        let app = launch()
        let sidebar = app.outlines.firstMatch

        /// The three large files in the order the page shows them, top to bottom.
        func order() -> [String] {
            ["Holiday.mov", "Installer.dmg", "Clip.mov"].sorted {
                app.staticTexts[$0].frame.minY < app.staticTexts[$1].frame.minY
            }
        }

        step("Scan All fills in each sub-tool's estimate and a total that counts each file once (FCL-004, FCL-007)") {
            sidebar.staticTexts["File Cleanup"].click()
            XCTAssertTrue(app.staticTexts["No total yet"].appears(within: 5))
            app.buttons["Scan All"].click()

            // Large Files lists the three large files (10.5 MB), Old Files the holiday movie and the installer (8.4 MB),
            // and the total counts the two files both list once.
            XCTAssertTrue(app.staticTexts["10.5 MB reclaimable in total"].appears(within: 10))
            XCTAssertTrue(app.staticTexts["10.5 MB reclaimable"].exists)
            XCTAssertTrue(app.staticTexts["8.4 MB reclaimable"].exists)
            XCTAssertTrue(app.staticTexts["Each file counts once, even if several sub-tools list it."].exists)
            // FCL-004: the age advances while the landing page stays idle, without another scan or navigation.
            let ages = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Scanned "))
            XCTAssertTrue(ages.firstMatch.appears(within: 5))
            let initialAge = ages.firstMatch.label
            XCTAssertTrue(
                app.staticTexts.matching(identifier: initialAge).firstMatch.disappears(within: 5),
                "The scan age did not update while the page was idle")
            XCTAssertTrue(ages.firstMatch.exists, "The scan age disappeared instead of updating")
            attachScreenshot(of: app, named: "File Cleanup total")
        }

        step("Large Files groups files by top-level folder, biggest first, with subtotals (LRG-001, LRG-003)") {
            sidebar.staticTexts["Large Files"].click()
            XCTAssertTrue(app.staticTexts["Holiday.mov"].appears(within: 10))
            for name in ["Clip.mov", "Installer.dmg", "Movies", "Downloads"] {
                XCTAssertTrue(app.staticTexts[name].exists, "Missing \(name)")
            }
            XCTAssertFalse(app.staticTexts["notes.txt"].exists, "A file below the minimum size is listed")
            // Movies (7.3 MB) is a bigger group than Downloads (3.1 MB), so it comes first.
            XCTAssertLessThan(app.staticTexts["Movies"].frame.minY, app.staticTexts["Downloads"].frame.minY)
            XCTAssertTrue(app.staticTexts["7.3 MB"].exists, "Missing the Movies subtotal")
            attachScreenshot(of: app, named: "Large Files grouped by folder")
        }

        step("One flat list is sorted largest first, and a column header changes the sort (LRG-002, FCL-012)") {
            app.toolbars.checkBoxes["Group by Folder"].click()
            XCTAssertEqual(order(), ["Holiday.mov", "Installer.dmg", "Clip.mov"])
            app.buttons["Size"].click()
            XCTAssertEqual(order(), ["Clip.mov", "Installer.dmg", "Holiday.mov"])
        }

        step("Selecting rows shows their total, and Space opens Quick Look (FCL-012)") {
            XCTAssertTrue(app.staticTexts["No items selected"].exists)
            app.staticTexts["Holiday.mov"].click()
            XCTAssertTrue(app.staticTexts["1 item selected, 5.2 MB"].appears(within: 5))
            // 2 MiB and 3 MiB.
            app.staticTexts["Clip.mov"].click()
            XCUIElement.perform(withKeyModifiers: .command) { app.staticTexts["Installer.dmg"].click() }
            XCTAssertTrue(app.staticTexts["2 items selected, 5.2 MB"].appears(within: 5))

            app.typeKey(" ", modifierFlags: [])
            XCTAssertTrue(app.windows["Quick Look"].appears(within: 5), "Space did not open Quick Look")
            app.typeKey(" ", modifierFlags: [])
            XCTAssertTrue(app.windows["Quick Look"].disappears(within: 5), "Space did not close Quick Look")
        }

        step("Old Files lists files not opened for 12 months, the longest unopened first (OLD-001 to OLD-003)") {
            sidebar.staticTexts["Old Files"].click()
            // Only Old Files has this column, so the page has changed before the rows are checked.
            XCTAssertTrue(app.buttons["Last Opened"].appears(within: 10))
            XCTAssertTrue(app.staticTexts["Holiday.mov"].exists)
            XCTAssertTrue(app.staticTexts["Installer.dmg"].exists)
            XCTAssertFalse(app.staticTexts["Clip.mov"].exists, "A recently changed file is listed")
            XCTAssertFalse(app.staticTexts["notes.txt"].exists, "A file below the minimum size is listed")
            // Spotlight has no record of fixture files being opened, so each row says it shows the modified date.
            XCTAssertTrue(app.staticTexts["Modified"].exists, "The fallback to the modified date is not marked")
            XCTAssertLessThan(app.staticTexts["Holiday.mov"].frame.minY, app.staticTexts["Installer.dmg"].frame.minY)
            attachScreenshot(of: app, named: "Old Files, oldest first")
        }
    }
}
