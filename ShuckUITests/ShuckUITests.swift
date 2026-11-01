import XCTest

final class ShuckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarShowsToolsAndSubTools() throws {
        let app = XCUIApplication()
        app.launch()

        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        for title in [
            "Overview", "File Cleanup", "Large Files", "Old Files", "Developer Junk",
            "Caches & Logs", "Applications", "Startup Items", "History",
        ] {
            XCTAssertTrue(sidebar.staticTexts[title].exists, "Missing sidebar item: \(title)")
        }
        XCTAssertFalse(sidebar.staticTexts["Settings"].exists, "Settings belongs in its own window (D-27)")
    }

    @MainActor
    func testSelectingSubToolShowsItsPage() throws {
        let app = XCUIApplication()
        app.launch()

        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts["What is taking the most space?"].waitForExistence(timeout: 5))
    }
}
