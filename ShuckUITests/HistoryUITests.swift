import ShuckKitTestSupport
import XCTest

/// The History page: its runs and their items (HIS-002, HIS-004).
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
}
