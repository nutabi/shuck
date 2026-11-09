import ShuckKitTestSupport
import XCTest

/// Developer Junk's Xcode files: one row per project, stale ones and those whose project is gone selected, device
/// support versions selected unless they are the newest, simulator caches selected, and the rows of a running Xcode disabled.
final class DeveloperJunkUITests: ShuckUITestCase {
    private let projectHash = "abcdefghijklmnopqrstuvwxyzab"

    /// The page's footer says how many rows are selected; the size is left out because folders add allocated bytes.
    @MainActor
    private func footer(_ app: XCUIApplication, startingWith text: String) -> XCUIElement {
        // macOS text can expose its content as an accessibility value rather than a label.
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text, text))
            .firstMatch
    }

    /// A static text in `container` that starts with `text`, such as a sheet's title with a size in it.
    @MainActor
    private func text(_ container: XCUIElement, startingWith text: String) -> XCUIElement {
        container.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text, text))
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
        let stale = try root.derivedDataProject(
            "Stale-\(projectHash)", workspace: root.folder("Projects/Stale"), modified: longAgo)
        let fresh = try root.derivedDataProject(
            "Fresh-\(projectHash)", workspace: root.folder("Projects/Fresh"), modified: .now)
        let gone = try root.derivedDataProject(
            "Gone-\(projectHash)", workspace: root.url("Projects/Gone"), modified: .now)
        try root.deviceSupport("iOS", "16.4 (20E247)")
        try root.deviceSupport("iOS", "17.2 (21C62) arm64e")
        try root.file("Library/Developer/CoreSimulator/Caches/dyld/cache", size: 4096)
        try root.file("Library/Developer/CoreSimulator/Devices/ABCD-1234/device.plist", size: 10)
        let app = launch()
        let sidebar = app.outlines.firstMatch
        let sheet = app.sheets.firstMatch

        step("Developer Junk lists one row per project, by name, with why it is listed (DEV-R01, DEV-008)") {
            XCTAssertTrue(sidebar.staticTexts["Developer Junk"].appears(within: 5))
            sidebar.staticTexts["Developer Junk"].click()
            XCTAssertTrue(app.staticTexts["Stale"].appears(within: 10), "The scan did not list the projects")
            XCTAssertTrue(app.staticTexts["Fresh"].exists)
            XCTAssertTrue(app.staticTexts["Gone"].exists)
            XCTAssertFalse(app.staticTexts["Stale-\(projectHash)"].exists, "The folder's hash is shown")
            XCTAssertTrue(app.staticTexts["Its project is no longer on this Mac."].exists)
            XCTAssertTrue(app.staticTexts["Not built for 30 days or more."].exists)
            XCTAssertTrue(app.staticTexts["iOS 16.4 (20E247)"].exists, "No row for the device support version")
            attachScreenshot(of: app, named: "Developer Junk, Xcode build folders")
        }

        step("A project that is stale or gone starts selected, a recent one does not (DEV-005, DEV-008)") {
            XCTAssertTrue(isChecked(app, "Stale"))
            XCTAssertTrue(isChecked(app, "Gone"))
            XCTAssertFalse(isChecked(app, "Fresh"))
        }

        step("A device support version starts selected unless it is its platform's newest (DEV-R02)") {
            XCTAssertTrue(isChecked(app, "iOS 16.4 (20E247)"))
            XCTAssertFalse(isChecked(app, "iOS 17.2 (21C62) arm64e"))
        }

        step("A simulator cache starts selected, and the simulators' devices are not listed (DEV-R04, DEV-007)") {
            XCTAssertTrue(isChecked(app, "dyld"))
            XCTAssertFalse(app.staticTexts["ABCD-1234"].exists, "A simulator device is listed")
            XCTAssertTrue(footer(app, startingWith: "4 items selected").appears(within: 5), outline(of: app))
        }

        step("Choosing a recent project selects it, and clearing a box deselects it (DEV-005)") {
            checkbox(app, "Fresh").click()
            XCTAssertTrue(footer(app, startingWith: "5 items selected").appears(within: 5))
            checkbox(app, "Stale").click()
            checkbox(app, "Gone").click()
            XCTAssertTrue(footer(app, startingWith: "3 items selected").appears(within: 5))
        }

        step("Delete… opens the summary confirmation: totals per category, the list on demand, Cancel deletes nothing")
        {
            // The recent project is still selected; leave out the device support and the simulator cache and choose
            // the stale project, so the run is two build folders.
            checkbox(app, "iOS 16.4 (20E247)").click()
            checkbox(app, "dyld").click()
            checkbox(app, "Stale").click()
            XCTAssertTrue(footer(app, startingWith: "2 items selected").appears(within: 5))
            app.buttons["Delete…"].click()
            XCTAssertTrue(
                text(sheet, startingWith: "Delete 2 items, ").appears(within: 5), "No confirmation: \(outline(of: app))"
            )
            XCTAssertTrue(sheet.staticTexts["Xcode"].exists, "The category's total is missing: \(outline(of: app))")
            XCTAssertFalse(sheet.staticTexts["Stale-\(projectHash)"].exists, "The list is open before it was asked for")
            attachScreenshot(of: app, named: "Summary confirmation")

            sheet.buttons["Show All Items"].click()
            XCTAssertTrue(
                sheet.staticTexts["Stale-\(projectHash)"].appears(within: 5), "The item list is not reachable")
            XCTAssertTrue(sheet.staticTexts["Fresh-\(projectHash)"].exists)
            XCTAssertTrue(sheet.buttons["Hide All Items"].exists)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: stale.path), "A folder was deleted before the confirmation")

            sheet.buttons["Cancel"].click()
            XCTAssertTrue(sheet.disappears(within: 5))
            XCTAssertTrue(FileManager.default.fileExists(atPath: stale.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
            XCTAssertTrue(
                footer(app, startingWith: "2 items selected").appears(within: 5), "Cancel cleared the selection")
        }

        step("Delete removes the selection permanently, and the summary says what happened (SAF-003, SAF-011)") {
            app.buttons["Delete…"].click()
            XCTAssertTrue(text(sheet, startingWith: "Delete 2 items, ").appears(within: 5))
            sheet.buttons["Delete"].click()
            XCTAssertTrue(sheet.staticTexts["Deleted 2 items"].appears(within: 10), outline(of: app))
            XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "Stale was not deleted")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path), "Fresh was not deleted")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: gone.path), "A folder that was not selected was deleted")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.url.appending(path: ".Trash/Stale-\(projectHash)").path),
                "A rebuildable item went to the Trash")
            attachScreenshot(of: app, named: "Delete summary")
        }

        step("History shows the deletion as a run whose items are not restorable (HIS-004, SAF-006)") {
            sheet.buttons["Show in History"].click()
            let run = runRow(in: app, startingWith: "Developer Junk · Deleted permanently")
            XCTAssertTrue(run.appears(within: 5), "The run is missing: \(outline(of: app))")
            XCTAssertTrue(run.label.contains(", 2 items, "), "Wrong count: \(run.label)")
            XCTAssertTrue(run.label.hasSuffix(", Completed"), "Wrong status: \(run.label)")
            XCTAssertTrue(app.staticTexts["Not restorable"].appears(within: 5), "The items are not marked")
            XCTAssertFalse(app.buttons["Restore All"].exists, "A deletion offers Restore")
            attachScreenshot(of: app, named: "History with a deletion")
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
