import ShuckKitTestSupport
import XCTest

/// Developer Junk's Xcode files: one row per project, stale ones and those whose project is gone selected, device
/// support versions selected unless they are the newest, simulator caches selected, and an Xcode archive, which is
/// "Your data": never selected, moved to the Trash after its own review. The workflow ends with the tool rules, which
/// run the tool's own command.
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

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// What the window holds, in one line, for a failure message.
    @MainActor
    private func outline(of app: XCUIApplication) -> String {
        app.windows.firstMatch.descendants(matching: .any).allElementsBoundByIndex
            .map { "\($0.elementType.rawValue):\($0.identifier):\($0.label):\($0.value ?? "")" }.joined(
                separator: " | ")
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
        // Stale, so it would be selected and counted, if its folder were not excluded (SET-001).
        try root.derivedDataProject(
            "Private-\(projectHash)", workspace: root.folder("Projects/Private"), modified: longAgo)
        try root.deviceSupport("iOS", "16.4 (20E247)")
        try root.deviceSupport("iOS", "17.2 (21C62) arm64e")
        try root.file("Library/Developer/CoreSimulator/Caches/dyld/cache", size: 4096)
        let device = try root.file("Library/Developer/CoreSimulator/Devices/ABCD-1234/device.plist", size: 10)
        // The tool rules' fake tools, which the app finds only inside the root (D-114, D-124). The last steps run them.
        try root.xcrun(.reportsInvocation)
        try root.tool("opt/homebrew/bin/npm", .reportsInvocation)
        let npmCache = try root.file(".npm/_cacache/content-v2/ab", size: 50_000)
        let archive = try root.xcarchive(day: "2026-11-10", name: "Release Build")
        // Two Node.js projects in a project folder, both left alone for 40 days: `web` would be selected, and `shop`
        // patches its packages, so it is listed and never selected (DEV-R06, DEV-006).
        let web = try root.nodeProject("Developer/web", edited: longAgo)
        let shop = try root.nodeProject(
            "Developer/shop", manifest: "{\"scripts\": {\"postinstall\": \"patch-package\"}}", edited: longAgo)
        let app = launch(
            exclusions: ["Library/Developer/Xcode/DerivedData/Private-\(projectHash)"], projectFolders: ["Developer"])
        let sidebar = app.outlines.firstMatch
        let sheet = app.sheets.firstMatch

        step("Developer Junk lists one row per project, by name, with why it is listed (DEV-R01, DEV-008)") {
            XCTAssertTrue(sidebar.staticTexts["Developer Junk"].appears(within: 5))
            sidebar.staticTexts["Developer Junk"].click()
            XCTAssertTrue(app.staticTexts["Stale"].appears(within: 10), "The scan did not list the projects")
            XCTAssertTrue(app.staticTexts["Fresh"].exists)
            XCTAssertTrue(app.staticTexts["Gone"].exists)
            XCTAssertFalse(app.staticTexts["Stale-\(projectHash)"].exists, "The folder's hash is shown")
            XCTAssertFalse(app.staticTexts["Private"].exists, "A project in an excluded folder is listed (SET-001)")
            // Two projects can share a name, so each row shows the path Xcode recorded for its project (M2-F20, D-138).
            XCTAssertTrue(app.staticTexts["~/Projects/Stale"].exists, "The project's path is missing")
            XCTAssertTrue(app.staticTexts["~/Projects/Gone"].exists, "A missing project's path is missing")
            XCTAssertTrue(app.staticTexts["Its project is no longer on this Mac."].exists)
            XCTAssertTrue(app.staticTexts["Not built for 30 days or more."].exists)
            XCTAssertTrue(app.staticTexts["iOS 16.4 (20E247)"].exists, "No row for the device support version")
            attachScreenshot(of: app, named: "Developer Junk, Xcode build folders")
        }

        step("A project's node_modules is a row named by its project, with its path and how to restore it (DEV-R06)") {
            XCTAssertTrue(app.staticTexts["web"].appears(within: 10), "No row for the project: \(outline(of: app))")
            XCTAssertTrue(app.staticTexts["shop"].exists)
            XCTAssertTrue(app.staticTexts["Node.js projects"].exists, "The projects have no group of their own")
            XCTAssertTrue(app.staticTexts["~/Developer/web"].exists, "The project's path is missing")
            XCTAssertFalse(app.staticTexts["node_modules"].exists, "The row is named after the folder, not the project")
            // Shuck has no network, so every row says that restoring needs an install and a connection.
            let restore =
                "To restore it, run npm install, or your project's package manager, which needs an internet connection."
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", restore, restore)).count
                    == 1,
                "The restore sentence is not shown once: \(outline(of: app))")
            // macOS text can expose its content as a value rather than a label, and the sentence is shown once.
            let warned = app.staticTexts.matching(
                NSPredicate(
                    format: "label BEGINSWITH %@ OR value BEGINSWITH %@", restore + " This project patches",
                    restore + " This project patches"))
            XCTAssertEqual(warned.count, 1, "The patch-package warning is not shown once: \(outline(of: app))")
            attachScreenshot(of: app, named: "Developer Junk with Node.js projects")
        }

        step("A project that is stale or gone starts selected, a recent one does not (DEV-005, DEV-008)") {
            XCTAssertTrue(isChecked(app, "Stale"))
            XCTAssertTrue(isChecked(app, "Gone"))
            XCTAssertFalse(isChecked(app, "Fresh"))
        }

        step("A stale project's node_modules starts selected, one that patches its packages does not (DEV-006)") {
            XCTAssertTrue(isChecked(app, "web"))
            XCTAssertFalse(isChecked(app, "shop"))
        }

        step("A device support version starts selected unless it is its platform's newest (DEV-R02)") {
            XCTAssertTrue(isChecked(app, "iOS 16.4 (20E247)"))
            XCTAssertFalse(isChecked(app, "iOS 17.2 (21C62) arm64e"))
        }

        step("A simulator cache starts selected, and the simulators' devices are not listed (DEV-R04, DEV-007)") {
            XCTAssertTrue(isChecked(app, "dyld"))
            XCTAssertFalse(app.staticTexts["ABCD-1234"].exists, "A simulator device is listed")
        }

        step("A tool rule is one selected row with its exact command and a size or none (DEV-R03, DEV-R07, DEV-003)") {
            XCTAssertTrue(isChecked(app, "Unavailable Simulators"))
            XCTAssertTrue(app.staticTexts["Size not known"].exists)
            XCTAssertTrue(isChecked(app, "npm Cache"))
            XCTAssertTrue(
                app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Up to ", "Up to ")
                ).firstMatch.exists,
                "The npm cache has no size estimate: \(outline(of: app))")
            // As a user would type it, with no quotes around plain words (D-138).
            let command = app.staticTexts.matching(
                NSPredicate(
                    format: "label ENDSWITH %@ OR value ENDSWITH %@", "/usr/bin/xcrun simctl delete unavailable",
                    "/usr/bin/xcrun simctl delete unavailable")
            ).firstMatch
            XCTAssertTrue(command.exists, "The command is not shown: \(outline(of: app))")
            // The five rows above and the two tool rules.
            XCTAssertTrue(footer(app, startingWith: "7 items selected").appears(within: 5), outline(of: app))
            attachScreenshot(of: app, named: "Developer Junk with tool rules")

            // The steps below start from the five rows above; the tool rules are run in the last steps.
            checkbox(app, "Unavailable Simulators").click()
            checkbox(app, "npm Cache").click()
            XCTAssertTrue(footer(app, startingWith: "5 items selected").appears(within: 5), outline(of: app))
        }

        step("Choosing a recent project selects it, and clearing a box deselects it (DEV-005)") {
            checkbox(app, "Fresh").click()
            XCTAssertTrue(footer(app, startingWith: "6 items selected").appears(within: 5))
            checkbox(app, "Stale").click()
            checkbox(app, "Gone").click()
            XCTAssertTrue(footer(app, startingWith: "4 items selected").appears(within: 5))
        }

        step("Delete… opens the summary confirmation: totals per category, the list on demand, Cancel deletes nothing")
        {
            // The recent project and `web` are still selected; leave out the device support and the simulator cache and
            // choose the stale project, so the run is two build folders and a node_modules.
            checkbox(app, "iOS 16.4 (20E247)").click()
            checkbox(app, "dyld").click()
            checkbox(app, "Stale").click()
            XCTAssertTrue(footer(app, startingWith: "3 items selected").appears(within: 5))
            app.buttons["Delete…"].click()
            XCTAssertTrue(
                text(sheet, startingWith: "Delete 3 items, ").appears(within: 5), "No confirmation: \(outline(of: app))"
            )
            XCTAssertTrue(sheet.staticTexts["Xcode"].exists, "The category's total is missing: \(outline(of: app))")
            XCTAssertTrue(sheet.staticTexts["Node.js projects"].exists, "The projects' total is missing")
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
                exists(web.appending(path: "node_modules")), "A node_modules was deleted before the confirmation")
            XCTAssertTrue(
                footer(app, startingWith: "3 items selected").appears(within: 5), "Cancel cleared the selection")
        }

        step("Delete removes the selection permanently, and the summary says what happened (SAF-003, SAF-011)") {
            app.buttons["Delete…"].click()
            XCTAssertTrue(text(sheet, startingWith: "Delete 3 items, ").appears(within: 5))
            sheet.buttons["Delete"].click()
            XCTAssertTrue(sheet.staticTexts["Deleted 3 items"].appears(within: 10), outline(of: app))
            XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "Stale was not deleted")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path), "Fresh was not deleted")
            // Only the node_modules goes: the project's own files stay, and so does the one that was not selected.
            XCTAssertFalse(exists(web.appending(path: "node_modules")), "web's node_modules was not deleted")
            XCTAssertTrue(exists(web.appending(path: "package.json")), "A project's own file was deleted")
            XCTAssertTrue(exists(shop.appending(path: "node_modules")), "A node_modules that was not selected went")
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
            XCTAssertTrue(run.label.contains(", 3 items, "), "Wrong count: \(run.label)")
            XCTAssertTrue(run.label.hasSuffix(", Completed"), "Wrong status: \(run.label)")
            XCTAssertTrue(app.staticTexts["Not restorable"].appears(within: 5), "The items are not marked")
            XCTAssertFalse(app.buttons["Restore All"].exists, "A deletion offers Restore")
            attachScreenshot(of: app, named: "History with a deletion")
        }

        // The archive is "Your data": the steps below choose it by hand, since neither a scan nor Select All does.
        step(
            "An archive is its own group, unselected, and says it is Your data and goes to the Trash (DEV-R05, SAF-002)"
        ) {
            sidebar.staticTexts["Developer Junk"].click()
            XCTAssertTrue(app.staticTexts["Release Build"].appears(within: 10), outline(of: app))
            XCTAssertTrue(app.staticTexts["Xcode Archives"].exists, "The archives have no group of their own")
            XCTAssertTrue(
                app.staticTexts["Your data. Shuck moves it to the Trash, and you can restore it from History."].exists,
                "The row does not say it is Your data: \(outline(of: app))")
            XCTAssertFalse(isChecked(app, "Release Build"), "An archive starts selected")
            XCTAssertTrue(footer(app, startingWith: "Your data: none selected").exists)
            XCTAssertFalse(app.buttons["Move to Trash…"].isEnabled, "Nothing of Your data is selected")
            attachScreenshot(of: app, named: "Developer Junk with an archive")
        }

        step("Select All chooses the rebuildable rows and leaves the archive unchecked (SAF-002)") {
            app.buttons["Select All"].click()
            // The five rows and the two tool rules.
            XCTAssertTrue(footer(app, startingWith: "7 items selected").appears(within: 5), outline(of: app))
            XCTAssertFalse(isChecked(app, "Release Build"), "Select All chose an archive")
            XCTAssertTrue(footer(app, startingWith: "Your data: none selected").exists)
            XCTAssertFalse(app.buttons["Move to Trash…"].isEnabled)
        }

        step("Select None clears the selection, and ⇧⌘A and ⌘A do the same from the keyboard (NFR-A11Y-001)") {
            app.buttons["Select None"].click()
            XCTAssertTrue(footer(app, startingWith: "No items selected").appears(within: 5), outline(of: app))
            XCTAssertFalse(isChecked(app, "Gone"), "Select None left a row checked")
            XCTAssertFalse(app.buttons["Select None"].isEnabled, "Select None stays enabled with nothing selected")

            app.typeKey("a", modifierFlags: .command)
            XCTAssertTrue(footer(app, startingWith: "7 items selected").appears(within: 5), outline(of: app))
            XCTAssertFalse(isChecked(app, "Release Build"), "⌘A chose an archive")

            app.typeKey("a", modifierFlags: [.command, .shift])
            XCTAssertTrue(footer(app, startingWith: "No items selected").appears(within: 5), outline(of: app))

            // The steps after this one start from the full selection.
            app.buttons["Select All"].click()
            XCTAssertTrue(footer(app, startingWith: "7 items selected").appears(within: 5), outline(of: app))
        }

        step("Choosing the archive enables Move to Trash with its own count, and Delete keeps its own (SAF-002)") {
            checkbox(app, "Release Build").click()
            XCTAssertTrue(footer(app, startingWith: "Your data: 1 item selected, ").appears(within: 5))
            XCTAssertTrue(app.buttons["Move to Trash…"].isEnabled)
            XCTAssertTrue(footer(app, startingWith: "7 items selected").exists, "The archive was counted with Delete")
        }

        step("Move to Trash… lists the archive in the itemized review, then moves it (SAF-002, DEV-R05)") {
            app.buttons["Move to Trash…"].click()
            XCTAssertTrue(
                text(sheet, startingWith: "Move 1 item, ").appears(within: 5), "No review: \(outline(of: app))")
            XCTAssertTrue(sheet.staticTexts["Release Build.xcarchive"].exists, "The archive is not in the review")
            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path), "The archive moved before the review")
            attachScreenshot(of: app, named: "Move to Trash review of an archive")

            sheet.buttons["Move to Trash"].click()
            XCTAssertTrue(sheet.staticTexts["Moved 1 item to the Trash"].appears(within: 10), outline(of: app))
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path), "The archive did not move")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.url.appending(path: ".Trash/Release Build.xcarchive").path))
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: gone.path), "A rebuildable item was touched by the Trash run")
        }

        step("History shows the archive as moved to the Trash and restorable (HIS-003, HIS-004)") {
            sheet.buttons["Show in History"].click()
            let run = runRow(in: app, startingWith: "Developer Junk · Moved to the Trash")
            XCTAssertTrue(run.appears(within: 5), "The run is missing: \(outline(of: app))")
            XCTAssertTrue(run.label.contains(", 1 item, "), "Wrong count: \(run.label)")
            XCTAssertTrue(run.label.hasSuffix(", Completed"), "Wrong status: \(run.label)")
            XCTAssertTrue(app.staticTexts["In the Trash"].appears(within: 5), "The item is not marked restorable")
            XCTAssertTrue(app.buttons["Restore All"].exists, "A move to the Trash offers no Restore")
            attachScreenshot(of: app, named: "History with an archive in the Trash")
        }

        step("The moved archive left the list, and the page stops offering Move to Trash (SAF-011)") {
            sidebar.staticTexts["Developer Junk"].click()
            XCTAssertTrue(app.staticTexts["Gone"].appears(within: 5))
            XCTAssertTrue(app.staticTexts["Release Build"].disappears(within: 5), "The moved archive is still listed")
            XCTAssertFalse(app.buttons["Move to Trash…"].exists, "Move to Trash stays with nothing of Your data")
        }

        // The tool rules come last: the UI test runner is sandboxed, so the fake tool it writes is quarantined and the app
        // is not allowed to run it, and the run ends as a failure. This part checks what a user sees whatever the tool's
        // exit; that a tool that succeeds is "done", with its output, is covered by the engine tests (docs/testing.md,
        // UI tests).
        step("Choosing only the tool rules selects exactly them, with nothing of Your data (DEV-R03, DEV-R07, DEV-003)")
        {
            // The page is still Developer Junk, with the tool rules the scan listed at the start.
            XCTAssertTrue(app.staticTexts["Unavailable Simulators"].exists, outline(of: app))
            app.buttons["Select None"].click()
            XCTAssertTrue(footer(app, startingWith: "No items selected").appears(within: 5), outline(of: app))
            checkbox(app, "Unavailable Simulators").click()
            checkbox(app, "npm Cache").click()
            XCTAssertTrue(footer(app, startingWith: "2 items selected").appears(within: 5), outline(of: app))
        }

        step("The confirmation says Clean Up, since a tool removes its own data (SAF-003, D-125)") {
            app.buttons["Delete…"].click()
            XCTAssertTrue(
                text(sheet, startingWith: "Clean up 2 items, up to ").appears(within: 5),
                "No confirmation: \(outline(of: app))")
            XCTAssertTrue(sheet.staticTexts["Xcode"].exists && sheet.staticTexts["Package managers"].exists)
            XCTAssertFalse(sheet.buttons["Delete"].exists, "A tool run is worded as a deletion")
            sheet.buttons["Show All Items"].click()
            XCTAssertTrue(
                sheet.staticTexts.matching(
                    NSPredicate(
                        format: "label ENDSWITH %@ OR value ENDSWITH %@", "xcrun simctl delete unavailable",
                        "xcrun simctl delete unavailable")
                ).firstMatch
                    .appears(within: 5), "The command is not in the item list")
            XCTAssertFalse(root.aFakeToolRan, "The tool ran before the confirmation")
            attachScreenshot(of: app, named: "Summary confirmation for a tool")
        }

        step("Clean Up starts the run, and the summary says what happened (SAF-010, SAF-011)") {
            sheet.buttons["Clean Up"].click()
            XCTAssertTrue(text(sheet, startingWith: "Cleaned up").appears(within: 10), outline(of: app))
            XCTAssertTrue(sheet.buttons["Show in History"].exists, outline(of: app))
            XCTAssertTrue(FileManager.default.fileExists(atPath: device.path), "Shuck deleted simulator data itself")
            XCTAssertTrue(FileManager.default.fileExists(atPath: npmCache.path), "Shuck deleted npm's cache itself")
        }

        step("History shows the tool run as its command and its tool, not as a file (HIS-002, HIS-004, #63)") {
            sheet.buttons["Show in History"].click()
            let run = runRow(in: app, startingWith: "Developer Junk · Cleaned by its tool")
            XCTAssertTrue(run.appears(within: 5), "The run is missing: \(outline(of: app))")
            XCTAssertTrue(
                app.staticTexts["xcrun simctl delete unavailable"].appears(within: 5),
                "The command is not the item's name: \(outline(of: app))")
            XCTAssertTrue(app.staticTexts["npm cache clean --force"].exists)
            XCTAssertTrue(
                app.staticTexts.matching(
                    NSPredicate(
                        format: "label ENDSWITH %@ OR value ENDSWITH %@", "/usr/bin/xcrun · Cleaned by its tool",
                        "/usr/bin/xcrun · Cleaned by its tool")
                ).firstMatch.exists, "The tool's own path is missing")
            XCTAssertFalse(app.buttons["Restore All"].exists, "A tool run offers Restore")
            attachScreenshot(of: app, named: "History with a tool run")
        }
    }
}
