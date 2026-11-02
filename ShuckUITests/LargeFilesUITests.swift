import ShuckKitTestSupport
import XCTest

/// The Large Files sub-tool: its list, the shared results table, and Move to Trash (LRG-001 to LRG-004, FCL-012).
final class LargeFilesUITests: ShuckUITestCase {
    /// LRG-001, LRG-003, FCL-012, D-61: opening the page scans, and lists files at or above the minimum size, grouped
    /// by top-level folder with subtotals.
    @MainActor
    func testLargeFilesListsFilesGroupedByFolderLRG001LRG003() throws {
        try root.file("Movies/Holiday.mov", size: 5 << 20)
        try root.file("Movies/Clip.mov", size: 2 << 20)
        try root.file("Downloads/Installer.dmg", size: 3 << 20)
        try root.file("Documents/notes.txt", size: 10)
        let app = launch()

        app.outlines.firstMatch.staticTexts["Large Files"].click()

        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForExistence(timeout: 10))
        for name in ["Clip.mov", "Installer.dmg", "Movies", "Downloads"] {
            XCTAssertTrue(app.staticTexts[name].exists, "Missing \(name)")
        }
        XCTAssertFalse(app.staticTexts["notes.txt"].exists, "A file below the minimum size is listed")
        // Movies (7.3 MB) is a bigger group than Downloads (3.1 MB), so it comes first.
        XCTAssertLessThan(app.staticTexts["Movies"].frame.minY, app.staticTexts["Downloads"].frame.minY)
        XCTAssertTrue(app.staticTexts["7.3 MB"].exists, "Missing the Movies subtotal")

        attachScreenshot(of: app, named: "Large Files grouped by folder")
    }

    /// LRG-002, FCL-012: one flat list is sorted largest first; a column header changes the sort; selecting rows
    /// shows their total; Space opens Quick Look.
    @MainActor
    func testLargeFilesSortsSelectsAndPreviewsLRG002FCL012() throws {
        try root.file("Movies/Holiday.mov", size: 5 << 20)
        try root.file("Movies/Clip.mov", size: 2 << 20)
        try root.file("Downloads/Installer.dmg", size: 3 << 20)
        let app = launch()

        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForExistence(timeout: 10))
        app.toolbars.checkBoxes["Group by Folder"].click()

        func order() -> [String] {
            ["Holiday.mov", "Installer.dmg", "Clip.mov"].sorted {
                app.staticTexts[$0].frame.minY < app.staticTexts[$1].frame.minY
            }
        }
        XCTAssertEqual(order(), ["Holiday.mov", "Installer.dmg", "Clip.mov"])

        app.buttons["Size"].click()
        XCTAssertEqual(order(), ["Clip.mov", "Installer.dmg", "Holiday.mov"])

        XCTAssertTrue(app.staticTexts["No items selected"].exists)
        app.staticTexts["Holiday.mov"].click()
        XCTAssertTrue(app.staticTexts["1 item selected, 5.2 MB"].waitForExistence(timeout: 5))
        // 2 MiB and 3 MiB.
        app.staticTexts["Clip.mov"].click()
        XCUIElement.perform(withKeyModifiers: .command) { app.staticTexts["Installer.dmg"].click() }
        XCTAssertTrue(app.staticTexts["2 items selected, 5.2 MB"].waitForExistence(timeout: 5))

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.windows["Quick Look"].waitForExistence(timeout: 5), "Space did not open Quick Look")
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.windows["Quick Look"].waitForNonExistence(timeout: 5), "Space did not close Quick Look")
    }

    /// SAF-002, LRG-004, SAF-016: "Move to Trash…" opens an itemized review whose title states the count and size, and
    /// nothing moves until its button is pressed. Cancelling moves nothing. Confirming moves the items into the
    /// fixture root's own Trash, never the real one, and the summary says so; the moved rows leave the list.
    @MainActor
    func testMoveToTrashReviewsThenMovesSAF002LRG004() throws {
        let holiday = try root.file("Movies/Holiday.mov", size: 5 << 20)
        let clip = try root.file("Movies/Clip.mov", size: 2 << 20)
        let installer = try root.file("Downloads/Installer.dmg", size: 3 << 20)
        let app = launch()

        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForExistence(timeout: 10))
        let moveToTrash = app.buttons["Move to Trash…"]
        XCTAssertFalse(moveToTrash.isEnabled, "Nothing is selected, so there is nothing to review")

        // ⌘⌫ opens the review; Cancel moves nothing.
        app.staticTexts["Installer.dmg"].click()
        app.typeKey(.delete, modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["Move 1 item, 3.1 MB, to the Trash?"].waitForExistence(timeout: 5))
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.path))

        app.staticTexts["Holiday.mov"].click()
        XCUIElement.perform(withKeyModifiers: .command) { app.staticTexts["Clip.mov"].click() }
        moveToTrash.click()
        XCTAssertTrue(sheet.staticTexts["Move 2 items, 7.3 MB, to the Trash?"].waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.staticTexts["Holiday.mov"].exists)
        XCTAssertTrue(sheet.staticTexts["Clip.mov"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: holiday.path), "An item moved before the confirmation")
        attachScreenshot(of: app, named: "Move to Trash review")

        sheet.buttons["Move to Trash"].click()
        XCTAssertTrue(sheet.staticTexts["Moved 2 items to the Trash"].waitForExistence(timeout: 10))
        let trash = root.url.appending(path: ".Trash")
        for file in [holiday, clip] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent) did not move")
            XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: file.lastPathComponent).path))
        }
        attachScreenshot(of: app, named: "Move to Trash summary")

        sheet.buttons["Done"].click()
        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Clip.mov"].exists)
        XCTAssertTrue(app.staticTexts["Installer.dmg"].exists)
    }
}
