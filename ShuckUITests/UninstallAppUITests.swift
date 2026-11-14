import ShuckKitTestSupport
import XCTest

/// Uninstalling an app: the Applications list, sorted and searched, and the selected app's leftovers. Later steps add
/// the uninstall and its Restore.
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
        try root.app(
            "Applications/Delta.app", bundleID: "org.acme.delta", name: "Delta", version: "4.0", size: 4 << 20)
        try root.file("Library/Application Support/org.acme.delta/data", size: 2_000)
        try root.file("Library/Caches/Delta/cache", size: 3_000)
        try root.file("SystemLibrary/Preferences/org.acme.delta.plist", size: 1_000)
        let app = launch(appFolders: ["Applications"])
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
            let high = app.staticTexts["leftover-confidence-Application Support/org.acme.delta"]
            XCTAssertTrue(high.appears(within: 10))
            XCTAssertEqual(text(high), "High")
            XCTAssertEqual(
                text(app.staticTexts["leftover-reason-Application Support/org.acme.delta"]),
                "Named by the app's bundle ID")
            XCTAssertEqual(text(app.staticTexts["leftover-confidence-Caches/Delta"]), "Medium")
            XCTAssertEqual(text(app.staticTexts["leftover-reason-Caches/Delta"]), "Named like the app: Delta")
            let note = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "may ask for", "may ask for")
            XCTAssertTrue(app.descendants(matching: .any).matching(note).firstMatch.exists)
            attachScreenshot(of: app, named: "Leftovers")
        }

        step("A system-wide leftover says it needs admin and offers Show in Finder, and the others do not (APP-004)") {
            let name = "Preferences/org.acme.delta.plist"
            XCTAssertEqual(text(app.staticTexts["leftover-confidence-\(name)"]), "High")
            XCTAssertEqual(
                text(app.staticTexts["leftover-disabled-\(name)"]), "Needs admin — not removable in this version")
            XCTAssertTrue(app.buttons["leftover-show-in-finder-\(name)"].exists)
            XCTAssertFalse(app.buttons["leftover-show-in-finder-Caches/Delta"].exists)
            XCTAssertFalse(app.buttons["leftover-show-in-finder-Application Support/org.acme.delta"].exists)
        }

        step("An app with no leftovers says so, and the pane forgets the last app's") {
            app.staticTexts["com.example.alpha"].click()
            XCTAssertTrue(app.staticTexts["No leftovers found"].appears(within: 10))
            XCTAssertFalse(app.staticTexts["leftover-confidence-Caches/Delta"].exists)
        }
    }
}
