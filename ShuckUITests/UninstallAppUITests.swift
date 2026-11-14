import ShuckKitTestSupport
import XCTest

/// Uninstalling an app: the Applications list, sorted and searched, the selected app's leftovers, and the uninstall: a
/// blocked app has none, a running app is quit first, and the review, the run and its summary follow. A later step adds
/// Restore.
///
/// The fixture apps sit in `Applications` and in its `Utilities` subfolder, one level down. Last-opened dates are
/// stubbed to none in a fixture root, so last-opened order is a unit test.
final class UninstallAppUITests: ShuckUITestCase {
    @MainActor
    func testUninstallAnApp() throws {
        try root.app("Applications/Beta.app", bundleID: "com.example.beta", name: "Beta", version: "2.1", size: 3 << 20)
        try root.app(
            "Applications/Alpha.app", bundleID: "com.example.alpha", name: "Alpha", version: "1.0", size: 1 << 20)
        try root.app(
            "Applications/Utilities/Gamma.app", bundleID: "com.example.gamma", name: "Gamma", version: "3.4.5",
            size: 2 << 20)
        // Delta's leftovers: a High one by its bundle ID, a Medium one named like the app, and a system-wide one, which
        // needs admin rights. The other apps have none.
        let delta = try root.app(
            "Applications/Delta.app", bundleID: "org.acme.delta", name: "Delta", version: "4.0", size: 4 << 20)
        try root.file("Library/Application Support/org.acme.delta/data", size: 2_000)
        try root.file("Library/Caches/Delta/cache", size: 3_000)
        try root.file("SystemLibrary/Preferences/org.acme.delta.plist", size: 1_000)
        // An exact bundle-ID match outside Application Support starts selected, so the review lists it with the bundle.
        let preferences = try root.file("Library/Preferences/org.acme.delta.plist", size: 1_000)
        // Locked cannot be removed, since the user cannot change its bundle (APP-005). The permissions go back after the
        // test, so the fixture root can be removed.
        let locked = try root.app(
            "Applications/Locked.app", bundleID: "com.example.locked", name: "Locked", version: "1.0", size: 1 << 20)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        addTeardownBlock { _ = chmod(locked.path, 0o755) }
        let trash = root.url.appending(path: ".Trash")
        // Delta is running, so its uninstall asks it to quit first (APP-006); Xcode, which runs this test, is never asked.
        let app = launch(runningApps: ["org.acme.delta"], appFolders: ["Applications"])
        let sidebar = app.outlines.firstMatch

        /// Clicks a column header. With a search field in the toolbar, XCUITest wrongly reports the headers as not
        /// hittable and gives up trying to scroll them into view, although they are visible. A click at the header's
        /// center skips that check, and a header that really were covered would still fail the order check after it.
        func clickHeader(_ title: String) {
            app.buttons[title].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }

        /// What a static text with an identifier shows: SwiftUI gives it as the value, and leaves the label empty.
        func text(_ element: XCUIElement) -> String {
            element.label.isEmpty ? element.value as? String ?? "" : element.label
        }

        /// A leftover's identifiers name its whole path, which is inside the fixture root.
        let support = "Library/Application Support/org.acme.delta"
        let caches = "Library/Caches/Delta"
        let prefs = "Library/Preferences/org.acme.delta.plist"
        /// The element of a query with a leftover's identifier. A name is matched by a predicate, since a string
        /// subscript refuses more than 128 characters, which a path in the temporary folder exceeds.
        func leftover(_ query: XCUIElementQuery, _ kind: String, _ relativePath: String) -> XCUIElement {
            let identifier = "leftover-\(kind)-\(root.url.path)/\(relativePath)"
            return query.matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        }

        /// The three apps in the order the page shows them, top to bottom.
        func order() -> [String] {
            ["Alpha", "Beta", "Gamma"].sorted { app.staticTexts[$0].frame.minY < app.staticTexts[$1].frame.minY }
        }

        step("Applications lists each app with its name, version and bundle ID, by name (APP-001, APP-009)") {
            XCTAssertTrue(sidebar.staticTexts["Applications"].appears(within: 5))
            sidebar.staticTexts["Applications"].click()
            // Apps stream in one at a time, so wait for the one the scan finds last.
            XCTAssertTrue(app.staticTexts["Gamma"].appears(within: 10))
            for text in [
                "Alpha", "Beta", "com.example.alpha", "com.example.beta", "com.example.gamma", "1.0", "2.1", "3.4.5",
            ] {
                XCTAssertTrue(app.staticTexts[text].exists, "Missing \(text)")
            }
            XCTAssertEqual(order(), ["Alpha", "Beta", "Gamma"])
            attachScreenshot(of: app, named: "Applications")
        }

        step("The Size header sorts by size, and a second click reverses it (APP-009)") {
            clickHeader("Size")
            XCTAssertEqual(order(), ["Alpha", "Gamma", "Beta"])
            clickHeader("Size")
            XCTAssertEqual(order(), ["Beta", "Gamma", "Alpha"])
        }

        step("The Name header sorts by name again (APP-009)") {
            clickHeader("Name")
            XCTAssertEqual(order(), ["Alpha", "Beta", "Gamma"])
        }

        step("Search matches an app's name, and its bundle ID, and the full list returns when it is cleared (APP-009)")
        {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.appears(within: 5))
            search.click()
            search.typeText("beta")
            XCTAssertTrue(app.staticTexts["Alpha"].disappears(within: 5))
            XCTAssertTrue(app.staticTexts["Beta"].exists)
            XCTAssertFalse(app.staticTexts["Gamma"].exists)

            search.typeKey("a", modifierFlags: .command)
            search.typeKey(.delete, modifierFlags: [])
            XCTAssertTrue(app.staticTexts["Alpha"].appears(within: 5))
            // Only the bundle ID contains this text, not any app's name.
            search.typeText("example.alpha")
            XCTAssertTrue(app.staticTexts["Beta"].disappears(within: 5))
            XCTAssertTrue(app.staticTexts["Alpha"].exists)
            XCTAssertFalse(app.staticTexts["Gamma"].exists)

            search.typeKey("a", modifierFlags: .command)
            search.typeKey(.delete, modifierFlags: [])
            XCTAssertTrue(app.staticTexts["Gamma"].appears(within: 5))
            XCTAssertEqual(order(), ["Alpha", "Beta", "Gamma"])
        }

        step("Selecting an app lists its leftovers with how sure the scan is, and why (APP-002, APP-003)") {
            XCTAssertTrue(app.staticTexts["Select an app to see what it leaves behind."].exists)
            app.staticTexts["org.acme.delta"].click()
            let high = leftover(app.staticTexts, "confidence", support)
            XCTAssertTrue(high.appears(within: 10))
            XCTAssertEqual(text(high), "High")
            XCTAssertEqual(
                text(leftover(app.staticTexts, "reason", support)),
                "Named by the app's bundle ID")
            XCTAssertEqual(text(leftover(app.staticTexts, "confidence", caches)), "Medium")
            XCTAssertEqual(text(leftover(app.staticTexts, "reason", caches)), "Named like the app: Delta")
            let note = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "may ask for", "may ask for")
            XCTAssertTrue(app.descendants(matching: .any).matching(note).firstMatch.exists)
            attachScreenshot(of: app, named: "Leftovers")
        }

        step("A system-wide leftover says it needs admin and offers Show in Finder, and the others do not (APP-004)") {
            let name = "SystemLibrary/Preferences/org.acme.delta.plist"
            XCTAssertEqual(text(leftover(app.staticTexts, "confidence", name)), "High")
            XCTAssertEqual(
                text(leftover(app.staticTexts, "disabled", name)), "Needs admin — not removable in this version")
            XCTAssertTrue(leftover(app.buttons, "show-in-finder", name).exists)
            XCTAssertFalse(leftover(app.buttons, "show-in-finder", caches).exists)
            XCTAssertFalse(leftover(app.buttons, "show-in-finder", support).exists)
        }

        step("An app with no leftovers says so, and the pane forgets the last app's") {
            app.staticTexts["com.example.alpha"].click()
            XCTAssertTrue(app.staticTexts["No leftovers found"].appears(within: 10))
            XCTAssertFalse(leftover(app.staticTexts, "confidence", caches).exists)
        }

        step("A blocked app says why and has no Uninstall (APP-005)") {
            app.staticTexts["com.example.locked"].click()
            XCTAssertTrue(app.staticTexts["Can't uninstall this app"].appears(within: 10))
            XCTAssertFalse(app.buttons["Uninstall…"].isEnabled)
        }

        step("Each leftover has a checkbox: the scan's choice, and none for what needs admin (APP-007)") {
            app.staticTexts["org.acme.delta"].click()
            XCTAssertTrue(leftover(app.staticTexts, "confidence", prefs).appears(within: 10))
            XCTAssertTrue(app.buttons["Uninstall…"].becomesEnabled(within: 10))
            XCTAssertEqual(leftover(app.checkBoxes, "toggle", prefs).value as? Int, 1)
            XCTAssertEqual(leftover(app.checkBoxes, "toggle", support).value as? Int, 0)
            XCTAssertEqual(leftover(app.checkBoxes, "toggle", caches).value as? Int, 0)
            XCTAssertFalse(
                leftover(app.checkBoxes, "toggle", "SystemLibrary/Preferences/org.acme.delta.plist").isEnabled)
        }

        let sheet = app.sheets.firstMatch
        let moveToTrash = sheet.buttons["Move to Trash"]

        step("The review lists the app first, then what is chosen, and moves nothing yet (APP-007, SAF-002)") {
            app.buttons["Uninstall…"].click()
            let title = NSPredicate(format: "value BEGINSWITH %@", "Move 2 items,")
            XCTAssertTrue(sheet.staticTexts.matching(title).firstMatch.appears(within: 10))
            XCTAssertTrue(sheet.staticTexts["Delta.app"].exists)
            XCTAssertTrue(sheet.staticTexts["org.acme.delta.plist"].exists)
            XCTAssertFalse(sheet.staticTexts["org.acme.delta"].exists, "Support was not chosen")
            XCTAssertLessThan(
                sheet.staticTexts["Delta.app"].frame.minY, sheet.staticTexts["org.acme.delta.plist"].frame.minY)
            XCTAssertTrue(FileManager.default.fileExists(atPath: delta.path))
            attachScreenshot(of: app, named: "Uninstall review")
        }

        step("Cancel moves nothing, and the review opens again with the app still running (APP-006)") {
            sheet.buttons["Cancel"].click()
            XCTAssertTrue(sheet.disappears(within: 5))
            XCTAssertTrue(FileManager.default.fileExists(atPath: delta.path))
            app.buttons["Uninstall…"].click()
            XCTAssertTrue(sheet.buttons["Quit Delta"].appears(within: 10))
        }

        step("A running app keeps Move to Trash off until Quit has taken it away (APP-006)") {
            XCTAssertFalse(moveToTrash.isEnabled)
            XCTAssertTrue(sheet.staticTexts["Delta is running. Quit it to continue."].exists)
            sheet.buttons["Quit Delta"].click()
            XCTAssertTrue(moveToTrash.becomesEnabled(within: 10))
            XCTAssertFalse(sheet.buttons["Quit Delta"].exists)
        }

        step(
            "Move to Trash moves the app and the chosen leftover into the Trash and drops them from the page (APP-007)"
        ) {
            moveToTrash.click()
            XCTAssertTrue(sheet.staticTexts["Moved 2 items to the Trash"].appears(within: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: delta.path), "Delta.app did not move")
            XCTAssertFalse(FileManager.default.fileExists(atPath: preferences.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: "Delta.app").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: "org.acme.delta.plist").path))
            XCTAssertTrue(sheet.buttons["Show in History"].exists)
            attachScreenshot(of: app, named: "Uninstall summary")
            sheet.buttons["Done"].click()
            XCTAssertTrue(sheet.disappears(within: 5))
            XCTAssertTrue(app.staticTexts["org.acme.delta"].disappears(within: 5))
            XCTAssertTrue(app.staticTexts["Select an app to see what it leaves behind."].exists)
        }
    }
}
