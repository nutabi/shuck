import ShuckKitTestSupport
import XCTest

/// The History page: its runs and their items, and Restore (HIS-002, HIS-003, HIS-004).
final class HistoryUITests: ShuckUITestCase {
    /// HIS-002: with nothing logged, History says so.
    @MainActor
    func testHistoryWithNothingLoggedSaysSoHIS002() throws {
        let app = launch()

        app.outlines.firstMatch.staticTexts["History"].click()
        XCTAssertTrue(app.staticTexts["No history yet"].waitForExistence(timeout: 5))
    }

    /// HIS-002, HIS-004: after a run, the summary's "Show in History" opens History with the run expanded: its area,
    /// method, item count, size and status, then each item with what happened to it.
    @MainActor
    func testRunSummaryOpensTheRunInHistoryHIS002() throws {
        try root.file("Movies/Holiday.mov", size: 5 << 20)
        try root.file("Movies/Clip.mov", size: 2 << 20)
        let app = launch()

        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForExistence(timeout: 10))
        app.staticTexts["Holiday.mov"].click()
        app.buttons["Move to Trash…"].click()
        let sheet = app.sheets.firstMatch
        sheet.buttons["Move to Trash"].click()
        XCTAssertTrue(sheet.staticTexts["Moved 1 item to the Trash"].waitForExistence(timeout: 10))

        sheet.buttons["Show in History"].click()
        // A run row reads as one element, as VoiceOver speaks it: area and method, count and size, date, status.
        // `firstMatch` never finds this combined element, so the query must match exactly one; the rest of the label is
        // checked in Swift, for a failure message that shows it.
        let run = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Large Files · Moved to the Trash")
        )
        .element
        XCTAssertTrue(run.waitForExistence(timeout: 5), "The run is missing")
        XCTAssertTrue(run.label.contains(", 1 item, 5.2 MB, "), "Wrong count or size: \(run.label)")
        XCTAssertTrue(run.label.hasSuffix(", Completed"), "Wrong status: \(run.label)")
        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForExistence(timeout: 5), "The run is not expanded")
        XCTAssertTrue(app.staticTexts["In the Trash"].exists)
        XCTAssertFalse(app.staticTexts["Clip.mov"].exists, "An item the run did not touch is listed")

        attachScreenshot(of: app, named: "History with one run")
    }

    /// HIS-003, SAF-016: "Restore All" puts a run's items back at once, without a question when nothing is in the way,
    /// and the summary and History say so.
    @MainActor
    func testRestoreAllPutsTheRunBackHIS003() throws {
        let holiday = try root.file("Movies/Holiday.mov", size: 5 << 20)
        let app = launch()
        let sheet = try moveToTrashAndShowInHistory(app, "Holiday.mov")

        app.buttons["Restore All"].click()
        XCTAssertTrue(sheet.staticTexts["Restored 1 item"].waitForExistence(timeout: 10))
        XCTAssertTrue(sheet.staticTexts["Restored"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: holiday.path), "Holiday.mov is not back")
        let trashed = root.url.appending(path: ".Trash/Holiday.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.path), "Holiday.mov is still in the Trash")
        attachScreenshot(of: app, named: "Restore summary")

        sheet.buttons["Done"].click()
        let restoreRun = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Restore · Moved back from the Trash")
        )
        .element
        XCTAssertTrue(restoreRun.waitForExistence(timeout: 5), "The restore is not listed as a run")
        XCTAssertTrue(app.staticTexts["Restored"].exists, "The trashed item is not marked Restored")
        XCTAssertFalse(app.buttons["Restore All"].exists, "A restored run still offers Restore All")
    }

    /// HIS-003: when the original path is taken, Restore asks once; Keep Both puts the item back beside what is there,
    /// with " (restored)" in its name, and never replaces it.
    @MainActor
    func testRestoreToATakenPathAsksAndKeepsBothHIS003() throws {
        try root.file("Movies/Holiday.mov", size: 5 << 20)
        let app = launch()
        let sheet = try moveToTrashAndShowInHistory(app, "Holiday.mov")
        let newer = try root.file("Movies/Holiday.mov", size: 1 << 20)

        app.staticTexts["Holiday.mov"].click()
        XCTAssertTrue(app.staticTexts["1 item selected, 5.2 MB"].waitForExistence(timeout: 5))
        app.buttons["Restore"].click()
        XCTAssertTrue(sheet.staticTexts["The original place of 1 item is taken"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.url.appending(path: "Movies/Holiday (restored).mov").path),
            "The item moved before the answer")
        attachScreenshot(of: app, named: "Restore question")

        sheet.buttons["Keep Both"].click()
        XCTAssertTrue(sheet.staticTexts["Restored 1 item"].waitForExistence(timeout: 10))
        XCTAssertTrue(sheet.staticTexts["Restored as “Holiday (restored).mov”"].exists)
        let restored = root.url.appending(path: "Movies/Holiday (restored).mov")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: restored.path)[.size] as? Int, 5 << 20)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: newer.path)[.size] as? Int, 1 << 20,
            "The file at the original path was replaced")
    }

    /// Moves `name` to the Trash from Large Files and opens the run in History. Returns the sheet query, which the
    /// Restore sheet reuses.
    ///
    /// Large Files keeps another file listed: when its list empties, the page drops the table, and with it the Move to
    /// Trash summary (`docs/progress.md`, left over from M1-T12).
    @MainActor
    private func moveToTrashAndShowInHistory(_ app: XCUIApplication, _ name: String) throws -> XCUIElement {
        try root.file("Movies/Clip.mov", size: 2 << 20)
        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
        app.staticTexts[name].click()
        app.buttons["Move to Trash…"].click()
        let sheet = app.sheets.firstMatch
        sheet.buttons["Move to Trash"].click()
        XCTAssertTrue(sheet.staticTexts["Moved 1 item to the Trash"].waitForExistence(timeout: 10))
        sheet.buttons["Show in History"].click()
        XCTAssertTrue(app.staticTexts["In the Trash"].waitForExistence(timeout: 5), "The run is not expanded")
        return sheet
    }
}
