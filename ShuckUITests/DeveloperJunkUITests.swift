import ShuckKitTestSupport
import XCTest

/// Developer Junk's Xcode build folders: one row per project, stale ones and those whose project is gone selected,
/// and the rows of a running Xcode disabled.
final class DeveloperJunkUITests: ShuckUITestCase {
    private let projectHash = "abcdefghijklmnopqrstuvwxyzab"

    /// The page's footer says how many rows are selected; the size is left out because folders add allocated bytes.
    @MainActor
    private func footer(_ app: XCUIApplication, startingWith text: String) -> XCUIElement {
        // macOS text can expose its content as an accessibility value rather than a label.
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text, text))
            .firstMatch
    }

    /// The checkbox of the project named `name`, found by the identifier the page gives it.
    @MainActor
    private func checkbox(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "project-\(name)").firstMatch
    }

    /// What the window holds, in one line, for a failure message.
    @MainActor
    private func outline(of app: XCUIApplication) -> String {
        app.windows.firstMatch.descendants(matching: .any).allElementsBoundByIndex
            .map { "\($0.elementType.rawValue):\($0.identifier):\($0.label)" }.joined(separator: " | ")
    }

    /// A checkbox's state, which XCUITest reports as 1 or 0.
    @MainActor
    private func isChecked(_ app: XCUIApplication, _ name: String) -> Bool {
        let box = checkbox(app, name)
        XCTAssertTrue(box.appears(within: 5), "No checkbox for \(name): \(outline(of: app))")
        return "\(box.value ?? "")" == "1"
    }

    @MainActor
    func testReviewXcodeBuildFolders() throws {
        let longAgo = Date.now.addingTimeInterval(-40 * 86_400)
        try root.derivedDataProject("Stale-\(projectHash)", workspace: root.folder("Projects/Stale"), modified: longAgo)
        try root.derivedDataProject("Fresh-\(projectHash)", workspace: root.folder("Projects/Fresh"), modified: .now)
        try root.derivedDataProject("Gone-\(projectHash)", workspace: root.url("Projects/Gone"), modified: .now)
        let app = launch()
        let sidebar = app.outlines.firstMatch

        step("Developer Junk lists one row per project, by name, with why it is listed (DEV-R01, DEV-008)") {
            XCTAssertTrue(sidebar.staticTexts["Developer Junk"].appears(within: 5))
            sidebar.staticTexts["Developer Junk"].click()
            XCTAssertTrue(app.staticTexts["Stale"].appears(within: 10), "The scan did not list the projects")
            XCTAssertTrue(app.staticTexts["Fresh"].exists)
            XCTAssertTrue(app.staticTexts["Gone"].exists)
            XCTAssertFalse(app.staticTexts["Stale-\(projectHash)"].exists, "The folder's hash is shown")
            XCTAssertTrue(app.staticTexts["Its project is no longer on this Mac."].exists)
            XCTAssertTrue(app.staticTexts["Not built for 30 days or more."].exists)
            attachScreenshot(of: app, named: "Developer Junk, Xcode build folders")
        }

        step("A project that is stale or gone starts selected, a recent one does not (DEV-005, DEV-008)") {
            XCTAssertTrue(isChecked(app, "Stale"))
            XCTAssertTrue(isChecked(app, "Gone"))
            XCTAssertFalse(isChecked(app, "Fresh"))
            XCTAssertTrue(footer(app, startingWith: "2 items selected").appears(within: 5), outline(of: app))
        }

        step("Choosing a recent project selects it, and clearing a box deselects it (DEV-005)") {
            checkbox(app, "Fresh").click()
            XCTAssertTrue(footer(app, startingWith: "3 items selected").appears(within: 5))
            checkbox(app, "Stale").click()
            checkbox(app, "Gone").click()
            XCTAssertTrue(footer(app, startingWith: "1 item selected").appears(within: 5))
        }
    }

    @MainActor
    func testARunningXcodeDisablesItsProjects() throws {
        try root.derivedDataProject(
            "Stale-\(projectHash)", workspace: root.folder("Projects/Stale"),
            modified: .now.addingTimeInterval(-40 * 86_400))
        let app = launch(runningApps: ["com.apple.dt.Xcode"])
        let sidebar = app.outlines.firstMatch

        step("While Xcode runs, its projects have a note instead of a checkbox (SAF-009, CAC-003)") {
            XCTAssertTrue(sidebar.staticTexts["Developer Junk"].appears(within: 5))
            sidebar.staticTexts["Developer Junk"].click()
            XCTAssertTrue(app.staticTexts["Stale"].appears(within: 10), "The scan did not list the project")
            XCTAssertTrue(app.staticTexts["App is running"].exists)
            XCTAssertFalse(checkbox(app, "Stale").exists, "A running app's project can be chosen")
            XCTAssertTrue(app.staticTexts["No items selected"].exists)
            attachScreenshot(of: app, named: "Developer Junk with Xcode running")
        }
    }
}
