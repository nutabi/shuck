import XCTest

/// The sidebar, the placeholder pages of tools later milestones build, and the Settings window.
final class NavigationUITests: ShuckUITestCase {
    @MainActor
    func testSidebarShowsToolsAndSubTools() throws {
        let app = launch()

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

    /// NFR-QA-003: each tool or sub-tool a later milestone builds opens a page that says so.
    @MainActor
    func testPlaceholderPagesNameTheirMilestone() throws {
        let app = launch()

        for (title, summary, milestone) in [
            ("Overview", "Disk space at a glance, and what each sub-tool could reclaim.", "M5"),
            ("Developer Junk", "What can developer tools rebuild?", "M2"),
            ("Caches & Logs", "Which caches and logs can go?", "M2"),
            ("Applications", "Uninstall apps together with the files they leave behind.", "M3"),
            ("Startup Items", "See what starts automatically and turn off what you don't want.", "M4"),
        ] {
            app.outlines.firstMatch.staticTexts[title].click()
            XCTAssertTrue(app.staticTexts[summary].waitForExistence(timeout: 5), "\(title)'s page did not open")
            XCTAssertTrue(app.staticTexts["Planned for milestone \(milestone)."].exists, "\(title)'s milestone")
        }
    }

    /// D-27: Settings opens from the app menu with ⌘, in a window of its own, not in the sidebar.
    @MainActor
    func testCommandCommaOpensSettingsInItsOwnWindowD27() throws {
        let app = launch()
        XCTAssertTrue(app.outlines.firstMatch.waitForExistence(timeout: 5))

        app.typeKey(",", modifierFlags: .command)
        let summary = "Exclusions, thresholds and project folders."
        XCTAssertTrue(app.staticTexts[summary].waitForExistence(timeout: 5), "⌘, did not open Settings")
        XCTAssertTrue(app.staticTexts["Planned for milestone M5."].exists)
        XCTAssertEqual(app.windows.count, 2)
        let main = app.windows.containing(.outline, identifier: nil).element
        XCTAssertFalse(main.staticTexts[summary].exists, "Settings opened in the main window")
    }
}
