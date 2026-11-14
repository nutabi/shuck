import ShuckKitTestSupport
import XCTest

/// Caches & Logs: caches, logs and container caches grouped by the app they belong to, the default selection, the summary
/// confirmation and Delete, which empties a folder and keeps it, and the disabled rows of a running app and of a running
/// Xcode.
final class CachesAndLogsUITests: ShuckUITestCase {
    /// A folder whose own date and whose files' dates are `modified`, so the scan sees nothing in it changing since.
    @discardableResult
    private func folder(_ path: String, files: [String] = ["data.db"], modified: Date) throws -> URL {
        for file in files {
            try root.file("\(path)/\(file)", size: 4096, modified: modified)
        }
        let url = try root.url(path)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    /// The checkbox of the row at `path`, found by the identifier the page gives it.
    @MainActor
    private func checkbox(_ app: XCUIApplication, _ path: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "cache-\(path)").firstMatch
    }

    /// A checkbox's state, which XCUITest reports as 1 or 0.
    @MainActor
    private func isChecked(_ app: XCUIApplication, _ path: String) -> Bool {
        let box = checkbox(app, path)
        XCTAssertTrue(box.appears(within: 5), "No checkbox for \(path)")
        return "\(box.value ?? "")" == "1"
    }

    /// The footer says how many rows are selected; the size is left out because folders add allocated bytes.
    @MainActor
    private func footer(_ app: XCUIApplication, startingWith text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text, text))
            .firstMatch
    }

    /// A static text in `container` that starts with `text`, such as a sheet's title with a size in it.
    @MainActor
    private func text(_ container: XCUIElement, startingWith text: String) -> XCUIElement {
        container.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text, text))
            .firstMatch
    }

    @MainActor
    func testClearCachesAndLogsByApp() throws {
        let longAgo = Date.now.addingTimeInterval(-40 * 86_400)
        let notesCache = try folder("Library/Caches/com.example.Notes", modified: longAgo)
        let notesLogs = try folder("Library/Logs/com.example.Notes", files: ["notes.log"], modified: longAgo)
        let mailCaches = try folder(
            "Library/Containers/com.example.Mail/Data/Library/Caches", modified: longAgo)
        let fresh = try folder("Library/Caches/Fresh", modified: .now)
        // Part of macOS, which the scan lists but does not select (D-120). TextEdit is on every Mac.
        let textEdit = try folder("Library/Caches/com.apple.TextEdit", modified: longAgo)
        try folder("Library/Caches/Homebrew", modified: longAgo)
        // No installed app has this name, so Shuck cannot tell whose cache it is (CAC-009).
        let mystery = try folder("Library/Caches/Mystery", modified: longAgo)
        try root.file("Library/Application Support/Notes/notes.db", size: 4096, modified: longAgo)
        let app = launch(installedApps: ["com.example.Notes", "com.example.Mail"])
        let sidebar = app.outlines.firstMatch
        let sheet = app.sheets.firstMatch

        step(
            "Caches & Logs lists what each app keeps, under the app's name, with the note about macOS (CAC-002, CAC-007)"
        ) {
            XCTAssertTrue(sidebar.staticTexts["Caches & Logs"].appears(within: 5))
            sidebar.staticTexts["Caches & Logs"].click()
            XCTAssertTrue(
                app.staticTexts["com.example.Notes"].appears(within: 10), "The scan did not list the apps")
            // A folder named after an app that is installed shows the app's name; one that is not keeps its folder name.
            XCTAssertTrue(app.staticTexts["TextEdit"].exists, "The bundle ID was not resolved to the app's name")
            XCTAssertTrue(app.staticTexts["com.example.Mail"].exists)
            XCTAssertTrue(app.staticTexts["Fresh"].exists)
            XCTAssertTrue(app.staticTexts["~/Library/Logs/com.example.Notes"].exists)
            XCTAssertTrue(
                app.staticTexts["~/Library/Containers/com.example.Mail/Data/Library/Caches"].exists,
                "The sandboxed app's caches are missing")
            XCTAssertFalse(app.staticTexts["Homebrew"].exists, "A cache Developer Junk's tool owns is listed")
            XCTAssertFalse(app.staticTexts["Notes"].exists, "Something outside Caches and Logs is listed")
            XCTAssertTrue(
                text(app.windows.firstMatch, startingWith: "macOS also clears caches and logs").exists,
                "The note about macOS is missing")
            attachScreenshot(of: app, named: "Caches & Logs grouped by app")
        }

        step(
            "What nothing changed in for a while starts selected, and what macOS writes or is recent does not (CAC-005)"
        ) {
            XCTAssertTrue(isChecked(app, "~/Library/Caches/com.example.Notes"))
            XCTAssertTrue(isChecked(app, "~/Library/Logs/com.example.Notes"))
            XCTAssertTrue(isChecked(app, "~/Library/Containers/com.example.Mail/Data/Library/Caches"))
            XCTAssertFalse(isChecked(app, "~/Library/Caches/Fresh"))
            XCTAssertFalse(isChecked(app, "~/Library/Caches/com.apple.TextEdit"))
            // A cache whose app Shuck cannot name is listed, says why, and is never selected for the user (CAC-009).
            XCTAssertFalse(isChecked(app, "~/Library/Caches/Mystery"))
            XCTAssertTrue(
                app.staticTexts["Shuck can't tell which app this belongs to, so it starts unselected."].firstMatch
                    .exists)
            XCTAssertTrue(footer(app, startingWith: "3 items selected").appears(within: 5))
        }

        step("Delete… opens the summary confirmation: totals per category, the list on demand (CAC-006, SAF-003)") {
            app.buttons["Delete…"].click()
            XCTAssertTrue(text(sheet, startingWith: "Delete 3 items, ").appears(within: 5))
            for category in ["Caches", "Logs", "App Container Caches"] {
                XCTAssertTrue(sheet.staticTexts[category].exists, "No total for \(category)")
            }
            XCTAssertFalse(sheet.staticTexts["com.example.Notes"].exists, "The list is open before it was asked for")
            attachScreenshot(of: app, named: "Caches & Logs summary confirmation")

            sheet.buttons["Show All Items"].click()
            XCTAssertTrue(sheet.staticTexts["com.example.Notes"].appears(within: 5), "The item list is not reachable")
            sheet.buttons["Cancel"].click()
            XCTAssertTrue(sheet.disappears(within: 5))
            XCTAssertTrue(FileManager.default.fileExists(atPath: notesCache.appending(path: "data.db").path))
        }

        try step(
            "Delete empties each selected folder and keeps the folder, and the summary says what happened (CAC-004)"
        ) {
            app.buttons["Delete…"].click()
            XCTAssertTrue(text(sheet, startingWith: "Delete 3 items, ").appears(within: 5))
            sheet.buttons["Delete"].click()
            XCTAssertTrue(sheet.staticTexts["Deleted 3 items"].appears(within: 10))
            for folder in [notesCache, notesLogs, mailCaches] {
                var isFolder: ObjCBool = false
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue,
                    "A folder was removed: \(folder.lastPathComponent)")
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "Not emptied")
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.appending(path: "data.db").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: textEdit.appending(path: "data.db").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: mystery.appending(path: "data.db").path))
            attachScreenshot(of: app, named: "Caches & Logs summary")
        }

        step("History shows the deletion under Caches & Logs, not restorable (HIS-004, SAF-006)") {
            sheet.buttons["Show in History"].click()
            let run = runRow(in: app, startingWith: "Caches & Logs · Deleted permanently")
            XCTAssertTrue(run.appears(within: 5), "The run is missing")
            XCTAssertTrue(run.label.contains(", 3 items, "), "Wrong count: \(run.label)")
            XCTAssertTrue(app.staticTexts["Not restorable"].appears(within: 5))
        }
    }

    /// One launch with Notes and Xcode both running: Caches & Logs shows Notes's rows disabled, and Developer Junk
    /// shows Xcode's projects disabled. The two fixture sets do not overlap.
    @MainActor
    func testWhileAppsRunTheirDataIsLeftAlone() throws {
        let longAgo = Date.now.addingTimeInterval(-40 * 86_400)
        try folder("Library/Caches/com.example.Notes", modified: longAgo)
        try folder("Library/Logs/com.example.Notes", files: ["notes.log"], modified: longAgo)
        try folder("Library/Caches/com.example.Mail", modified: longAgo)
        try root.derivedDataProject(
            "Stale-abcdefghijklmnopqrstuvwxyzab", workspace: root.folder("Projects/Stale"), modified: longAgo)
        let app = launch(
            runningApps: ["com.example.Notes", "com.apple.dt.Xcode"],
            installedApps: ["com.example.Notes", "com.example.Mail"])
        let sidebar = app.outlines.firstMatch

        step("While an app runs, its caches and logs have a note instead of a checkbox (SAF-009, CAC-003)") {
            XCTAssertTrue(sidebar.staticTexts["Caches & Logs"].appears(within: 5))
            sidebar.staticTexts["Caches & Logs"].click()
            XCTAssertTrue(app.staticTexts["com.example.Notes"].appears(within: 10), "The scan did not list the apps")
            XCTAssertEqual(app.staticTexts.matching(identifier: "App is running").count, 2)
            XCTAssertFalse(
                checkbox(app, "~/Library/Caches/com.example.Notes").exists, "A running app's cache can be chosen")
            XCTAssertFalse(checkbox(app, "~/Library/Logs/com.example.Notes").exists)
            XCTAssertTrue(isChecked(app, "~/Library/Caches/com.example.Mail"))
            XCTAssertTrue(footer(app, startingWith: "1 item selected").appears(within: 5))
            attachScreenshot(of: app, named: "Caches & Logs with an app running")
        }

        step("While Xcode runs, its projects have a note instead of a checkbox (SAF-009, CAC-003)") {
            XCTAssertTrue(sidebar.staticTexts["Developer Junk"].appears(within: 5))
            sidebar.staticTexts["Developer Junk"].click()
            // Only Developer Junk lists the project, so the page has changed before the rest is checked.
            XCTAssertTrue(app.staticTexts["Stale"].appears(within: 10), "The scan did not list the project")
            XCTAssertTrue(app.staticTexts["App is running"].exists)
            let project = app.descendants(matching: .any).matching(identifier: "project-Stale").firstMatch
            XCTAssertFalse(project.exists, "A running app's project can be chosen")
            XCTAssertTrue(app.staticTexts["No items selected"].exists)
            attachScreenshot(of: app, named: "Developer Junk with Xcode running")
        }
    }
}
