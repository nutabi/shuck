import ShuckKitTestSupport
import XCTest

/// Uninstalling an app: the Applications list, sorted and searched. Later steps add the leftovers, the uninstall and
/// its Restore.
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
        let app = launch(appFolders: ["Applications"])
        let sidebar = app.outlines.firstMatch

        /// Clicks a column header. With a search field in the toolbar, XCUITest wrongly reports the headers as not
        /// hittable and gives up trying to scroll them into view, although they are visible. A click at the header's
        /// center skips that check, and a header that really were covered would still fail the order check after it.
        func clickHeader(_ title: String) {
            app.buttons[title].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
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
    }
}
