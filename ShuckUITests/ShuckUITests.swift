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

    /// FCL-004: the landing page lists each sub-tool with its summary and its own Scan button. None is built yet, so
    /// every Scan button and "Scan All" are disabled, and each row says which milestone builds it.
    @MainActor
    func testFileCleanupLandingPageListsSubToolsFCL004() throws {
        let app = XCUIApplication()
        app.launch()

        app.outlines.firstMatch.staticTexts["File Cleanup"].click()
        let subTools = [
            ("Large Files", "What is taking the most space?"),
            ("Old Files", "What haven't I opened in a long time?"),
            ("Developer Junk", "What can developer tools rebuild?"),
            ("Caches & Logs", "Which caches and logs can go?"),
        ]
        XCTAssertTrue(app.staticTexts[subTools[0].1].waitForExistence(timeout: 5))
        for (name, summary) in subTools {
            XCTAssertTrue(app.staticTexts[summary].exists, "Missing summary for \(name)")
            let scan = app.buttons["Scan \(name)"]
            XCTAssertTrue(scan.exists, "Missing Scan button for \(name)")
            XCTAssertFalse(scan.isEnabled, "\(name) is not built yet, so it cannot scan")
        }
        XCTAssertTrue(app.staticTexts["Planned for milestone M2."].exists)
        XCTAssertFalse(app.buttons["Scan All"].isEnabled)

        // Kept in the test results, so reviewers can see the page (ENG-003).
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "File Cleanup landing page"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
