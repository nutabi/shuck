import ShuckKitTestSupport
import XCTest

/// The File Cleanup landing page, and what its sub-tools' pages share (FCL-004, FCL-007, D-61).
final class FileCleanupUITests: ShuckUITestCase {
    /// FCL-004: the landing page lists each sub-tool with its summary and its own Scan button. Large Files and Old
    /// Files can scan; the others say which milestone builds them.
    @MainActor
    func testFileCleanupLandingPageListsSubToolsFCL004() throws {
        let app = launch()

        app.outlines.firstMatch.staticTexts["File Cleanup"].click()
        let subTools = [
            ("Large Files", "What is taking the most space?", true),
            ("Old Files", "What haven't I opened in a long time?", true),
            ("Developer Junk", "What can developer tools rebuild?", false),
            ("Caches & Logs", "Which caches and logs can go?", false),
        ]
        XCTAssertTrue(app.staticTexts[subTools[0].1].waitForExistence(timeout: 5))
        for (name, summary, available) in subTools {
            XCTAssertTrue(app.staticTexts[summary].exists, "Missing summary for \(name)")
            let scan = app.buttons["Scan \(name)"]
            XCTAssertTrue(scan.exists, "Missing Scan button for \(name)")
            XCTAssertEqual(scan.isEnabled, available, "\(name)'s Scan button")
        }
        XCTAssertTrue(app.staticTexts["Not scanned yet"].exists)
        XCTAssertTrue(app.staticTexts["Planned for milestone M2."].exists)
        XCTAssertTrue(app.buttons["Scan All"].isEnabled)

        // Kept in the test results, so reviewers can see the page (ENG-003).
        attachScreenshot(of: app, named: "File Cleanup landing page")
    }

    /// FCL-007: after Scan All, the landing page's total counts a file that is both large and old once.
    @MainActor
    func testLandingPageTotalCountsEachFileOnceFCL007() throws {
        let year: TimeInterval = 365 * 86_400
        try root.file("Movies/Holiday.mov", size: 5 << 20, modified: .now.addingTimeInterval(-3 * year))
        try root.file("Movies/Clip.mov", size: 2 << 20)
        let app = launch()

        app.outlines.firstMatch.staticTexts["File Cleanup"].click()
        XCTAssertTrue(app.staticTexts["No total yet"].waitForExistence(timeout: 5))
        app.buttons["Scan All"].click()

        // Large Files lists both files (7.3 MB), Old Files only the holiday movie (5.2 MB).
        XCTAssertTrue(app.staticTexts["7.3 MB reclaimable in total"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["7.3 MB reclaimable"].exists)
        XCTAssertTrue(app.staticTexts["5.2 MB reclaimable"].exists)
        XCTAssertTrue(app.staticTexts["Each file counts once, even if several sub-tools list it."].exists)

        attachScreenshot(of: app, named: "File Cleanup total")
    }

    /// D-61: with nothing to list, the page shows only its message, without an empty table. Going back to a page
    /// keeps its scan instead of starting another.
    @MainActor
    func testAPageWithNothingToListShowsNoTable() throws {
        try root.file("Documents/notes.txt", size: 10)
        let app = launch()

        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts["No files of at least 1 MB"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Size"].exists, "An empty table is shown")
        XCTAssertFalse(app.staticTexts["No items selected"].exists, "An empty table's footer is shown")

        // The shared scan already covered Old Files, so its page needs no scan of its own.
        app.outlines.firstMatch.staticTexts["Old Files"].click()
        XCTAssertTrue(app.staticTexts["No files left unopened for 12 months"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Size"].exists, "An empty table is shown")

        attachScreenshot(of: app, named: "Old Files with nothing to list")
    }
}
