import ShuckKitTestSupport
import XCTest

/// The Old Files sub-tool: its list and Move to Trash (OLD-001 to OLD-004).
final class OldFilesUITests: ShuckUITestCase {
    /// OLD-001, OLD-002, OLD-003: a scan lists files of at least the minimum size not opened for 12 months, the
    /// longest unopened first. Spotlight has no record of fixture files being opened, so each row says it shows the
    /// modified date.
    @MainActor
    func testOldFilesListsTheLongestUnopenedFirstOLD001OLD003() throws {
        let year: TimeInterval = 365 * 86_400
        try root.file("Movies/Holiday.mov", size: 2 << 20, modified: .now.addingTimeInterval(-3 * year))
        try root.file("Downloads/Installer.dmg", size: 2 << 20, modified: .now.addingTimeInterval(-2 * year))
        try root.file("Documents/Report.pdf", size: 2 << 20)
        try root.file("Documents/notes.txt", size: 10, modified: .now.addingTimeInterval(-5 * year))
        let app = launch()

        app.outlines.firstMatch.staticTexts["Old Files"].click()

        XCTAssertTrue(app.staticTexts["Holiday.mov"].appears(within: 10))
        XCTAssertTrue(app.staticTexts["Installer.dmg"].exists)
        XCTAssertFalse(app.staticTexts["Report.pdf"].exists, "A recently changed file is listed")
        XCTAssertFalse(app.staticTexts["notes.txt"].exists, "A file below the minimum size is listed")
        XCTAssertTrue(app.buttons["Last Opened"].exists)
        XCTAssertTrue(app.staticTexts["Modified"].exists, "The fallback to the modified date is not marked")

        XCTAssertLessThan(app.staticTexts["Holiday.mov"].frame.minY, app.staticTexts["Installer.dmg"].frame.minY)

        attachScreenshot(of: app, named: "Old Files, oldest first")
    }

    /// OLD-004, SAF-002, SAF-016: Move to Trash from Old Files reviews the selection, then moves it into the fixture
    /// root's own Trash. A moved file also leaves Large Files, which listed it too (FCL-006).
    @MainActor
    func testMoveToTrashFromOldFilesOLD004() throws {
        let year: TimeInterval = 365 * 86_400
        let holiday = try root.file("Movies/Holiday.mov", size: 2 << 20, modified: .now.addingTimeInterval(-3 * year))
        let installer = try root.file(
            "Downloads/Installer.dmg", size: 2 << 20, modified: .now.addingTimeInterval(-2 * year))
        let app = launch()

        app.outlines.firstMatch.staticTexts["Old Files"].click()
        XCTAssertTrue(app.staticTexts["Holiday.mov"].appears(within: 10))
        app.staticTexts["Holiday.mov"].click()
        app.buttons["Move to Trash…"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["Move 1 item, 2.1 MB, to the Trash?"].appears(within: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: holiday.path), "The item moved before the confirmation")

        sheet.buttons["Move to Trash"].click()
        XCTAssertTrue(sheet.staticTexts["Moved 1 item to the Trash"].appears(within: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: holiday.path), "Holiday.mov did not move")
        let trash = root.url.appending(path: ".Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: "Holiday.mov").path))
        attachScreenshot(of: app, named: "Old Files Move to Trash summary")

        sheet.buttons["Done"].click()
        XCTAssertTrue(app.staticTexts["Holiday.mov"].disappears(within: 5))
        XCTAssertTrue(app.staticTexts["Installer.dmg"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.path))

        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts["Installer.dmg"].appears(within: 5))
        XCTAssertFalse(app.staticTexts["Holiday.mov"].exists, "Large Files still lists the moved file")
    }
}
