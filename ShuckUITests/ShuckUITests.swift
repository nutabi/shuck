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

    /// Launches the app with the fixture root as its home folder and the minimum sizes of Large Files and Old Files at
    /// 1 MiB, so fixtures stay small.
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ShuckFixtureRoot", root.url.path, "-LargeFilesMinimumSize", "\(1 << 20)", "-OldFilesMinimumSize",
            "\(1 << 20)",
        ]
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

        app.outlines.firstMatch.staticTexts["Developer Junk"].click()
        XCTAssertTrue(app.staticTexts["What can developer tools rebuild?"].waitForExistence(timeout: 5))
    }

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

        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Installer.dmg"].exists)
        XCTAssertFalse(app.staticTexts["Report.pdf"].exists, "A recently changed file is listed")
        XCTAssertFalse(app.staticTexts["notes.txt"].exists, "A file below the minimum size is listed")
        XCTAssertTrue(app.buttons["Last Opened"].exists)
        XCTAssertTrue(app.staticTexts["Modified"].exists, "The fallback to the modified date is not marked")

        XCTAssertLessThan(app.staticTexts["Holiday.mov"].frame.minY, app.staticTexts["Installer.dmg"].frame.minY)

        attachScreenshot(of: app, named: "Old Files, oldest first")
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
        XCTAssertTrue(app.staticTexts["Large Files · Moved to the Trash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 item, 5.2 MB"].exists)
        XCTAssertTrue(app.staticTexts["Completed"].exists)
        XCTAssertTrue(app.staticTexts["Holiday.mov"].waitForExistence(timeout: 5), "The run is not expanded")
        XCTAssertTrue(app.staticTexts["In the Trash"].exists)
        XCTAssertFalse(app.staticTexts["Clip.mov"].exists, "An item the run did not touch is listed")

        attachScreenshot(of: app, named: "History with one run")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
