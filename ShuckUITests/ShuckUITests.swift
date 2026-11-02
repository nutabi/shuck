import ShuckKitTestSupport
import XCTest

/// Every test launches the app on its own fixture root, so the app never sees real user data (NFR-QA-002, SAF-016).
final class ShuckUITests: XCTestCase {
    private var root: FixtureRoot!

    override func setUpWithError() throws {
        continueAfterFailure = false
        root = try FixtureRoot()
    }

    override func tearDownWithError() throws {
        root = nil
    }

    /// Launches the app with the fixture root as its home folder and Large Files' minimum size at 1 MiB, so fixtures
    /// stay small.
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ShuckFixtureRoot", root.url.path, "-LargeFilesMinimumSize", "\(1 << 20)"]
        app.launch()
        return app
    }

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

    @MainActor
    func testSelectingSubToolShowsItsPage() throws {
        let app = launch()

        app.outlines.firstMatch.staticTexts["Old Files"].click()
        XCTAssertTrue(app.staticTexts["What haven't I opened in a long time?"].waitForExistence(timeout: 5))
    }

    /// FCL-004: the landing page lists each sub-tool with its summary and its own Scan button. Large Files can scan;
    /// the others say which milestone builds them.
    @MainActor
    func testFileCleanupLandingPageListsSubToolsFCL004() throws {
        let app = launch()

        app.outlines.firstMatch.staticTexts["File Cleanup"].click()
        let subTools = [
            ("Large Files", "What is taking the most space?", true),
            ("Old Files", "What haven't I opened in a long time?", false),
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

    /// LRG-001, LRG-003, FCL-012: a scan lists files at or above the minimum size, grouped by top-level folder with
    /// subtotals.
    @MainActor
    func testLargeFilesListsFilesGroupedByFolderLRG001LRG003() throws {
        try root.file("Movies/Holiday.mov", size: 5 << 20)
        try root.file("Movies/Clip.mov", size: 2 << 20)
        try root.file("Downloads/Installer.dmg", size: 3 << 20)
        try root.file("Documents/notes.txt", size: 10)
        let app = launch()

        app.outlines.firstMatch.staticTexts["Large Files"].click()
        XCTAssertTrue(app.staticTexts["Not scanned yet"].waitForExistence(timeout: 5))
        app.toolbars.buttons["Scan"].click()

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
        app.toolbars.buttons["Scan"].click()
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

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
