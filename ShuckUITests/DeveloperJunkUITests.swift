import ShuckKitTestSupport
import XCTest

/// Developer Junk's Xcode build folders: one row per project, stale ones and those whose project is gone selected,
/// and the rows of a running Xcode disabled.
final class DeveloperJunkUITests: ShuckUITestCase {
    private let projectHash = "abcdefghijklmnopqrstuvwxyzab"

    /// The page's footer says how many rows are selected; `size` is left out because folders add allocated bytes.
    @MainActor
    private func footer(_ app: XCUIApplication, startingWith text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// A checkbox's state, which XCUITest reports as 1 or 0.
    @MainActor
    private func isChecked(_ box: XCUIElement) -> Bool {
        "\(box.value ?? "")" == "1"
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
            XCTAssertTrue(isChecked(app.checkBoxes["Stale"]))
            XCTAssertTrue(isChecked(app.checkBoxes["Gone"]))
            XCTAssertFalse(isChecked(app.checkBoxes["Fresh"]))
            XCTAssertTrue(footer(app, startingWith: "2 items selected").appears(within: 5))
        }

        step("Choosing a recent project selects it, and clearing a box deselects it (DEV-005)") {
            app.checkBoxes["Fresh"].click()
            XCTAssertTrue(footer(app, startingWith: "3 items selected").appears(within: 5))
            app.checkBoxes["Stale"].click()
            app.checkBoxes["Gone"].click()
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
            XCTAssertFalse(app.checkBoxes["Stale"].exists, "A running app's project can be chosen")
            XCTAssertTrue(app.staticTexts["No items selected"].exists)
            attachScreenshot(of: app, named: "Developer Junk with Xcode running")
        }
    }
}
