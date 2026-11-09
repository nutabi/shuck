import ShuckKitTestSupport
import XCTest

/// A first look around a Mac with nothing to clean: the sidebar, History, the File Cleanup landing page, the pages of
/// tools later milestones build, a scan stopped and started again, sub-tool pages with nothing to list, and Settings.
///
/// Each scan waits 2 seconds before it starts, so there is time to stop one.
final class FirstLookUITests: ShuckUITestCase {
    @MainActor
    func testFirstLookWithNothingToClean() throws {
        // Too small for Large Files and Old Files, so neither has anything to list.
        try root.file("Documents/notes.txt", size: 10)
        let app = launch(scanDelay: 2)
        let sidebar = app.outlines.firstMatch

        step("The sidebar lists every tool and sub-tool, and Settings is not one of them (FCL-001, D-27)") {
            XCTAssertTrue(sidebar.appears(within: 5))
            for title in [
                "Overview", "File Cleanup", "Large Files", "Old Files", "Developer Junk",
                "Caches & Logs", "Applications", "Startup Items", "History",
            ] {
                XCTAssertTrue(sidebar.staticTexts[title].exists, "Missing sidebar item: \(title)")
            }
            XCTAssertFalse(sidebar.staticTexts["Settings"].exists, "Settings belongs in its own window (D-27)")
        }

        step("History says nothing is logged yet (HIS-002)") {
            sidebar.staticTexts["History"].click()
            XCTAssertTrue(app.staticTexts["No history yet"].appears(within: 5))
        }

        step("The File Cleanup landing page lists each sub-tool with its summary and Scan button (FCL-004)") {
            sidebar.staticTexts["File Cleanup"].click()
            // Large Files, Old Files and Developer Junk can scan; Caches & Logs says which milestone builds it.
            let subTools = [
                ("Large Files", "What is taking the most space?", true),
                ("Old Files", "What haven't I opened in a long time?", true),
                ("Developer Junk", "What can developer tools rebuild?", true),
                ("Caches & Logs", "Which caches and logs can go?", false),
            ]
            XCTAssertTrue(app.staticTexts[subTools[0].1].appears(within: 5))
            for (name, summary, available) in subTools {
                XCTAssertTrue(app.staticTexts[summary].exists, "Missing summary for \(name)")
                let scan = app.buttons["Scan \(name)"]
                XCTAssertTrue(scan.exists, "Missing Scan button for \(name)")
                XCTAssertEqual(scan.isEnabled, available, "\(name)'s Scan button")
            }
            XCTAssertTrue(app.staticTexts["Not scanned yet"].exists)
            XCTAssertTrue(app.staticTexts["Planned for milestone M2."].exists)
            XCTAssertTrue(app.staticTexts["No total yet"].exists)
            XCTAssertTrue(app.buttons["Scan All"].isEnabled)
            attachScreenshot(of: app, named: "File Cleanup landing page")
        }

        step("Each tool a later milestone builds opens a page that names the milestone (NFR-QA-003)") {
            // Overview comes first, so the landing page, which shows the same summary for Caches & Logs, is gone before
            // it is checked.
            for (title, summary, milestone) in [
                ("Overview", "Disk space at a glance, and what each sub-tool could reclaim.", "M5"),
                ("Caches & Logs", "Which caches and logs can go?", "M2"),
                ("Applications", "Uninstall apps together with the files they leave behind.", "M3"),
                ("Startup Items", "See what starts automatically and turn off what you don't want.", "M4"),
            ] {
                sidebar.staticTexts[title].click()
                XCTAssertTrue(app.staticTexts[summary].appears(within: 5), "\(title)'s page did not open")
                XCTAssertTrue(app.staticTexts["Planned for milestone \(milestone)."].exists, "\(title)'s milestone")
            }
        }

        step(
            "Stop stops the scan opening Large Files started, and opening a page doesn't restart it (SAF-014, D-91)"
        ) {
            sidebar.staticTexts["Large Files"].click()
            let stop = app.toolbars.buttons["Stop Scanning"]
            XCTAssertTrue(stop.appears(within: 5), "No Stop button while scanning")
            stop.click()
            XCTAssertTrue(app.staticTexts["Scan stopped"].appears(within: 5), "The scan did not stop")
            XCTAssertTrue(stop.disappears(within: 5))
            XCTAssertTrue(app.toolbars.buttons["Scan"].isEnabled)

            // Old Files shares the stopped scan, and opening its page doesn't start it again.
            sidebar.staticTexts["Old Files"].click()
            XCTAssertTrue(app.staticTexts["Scan stopped"].appears(within: 5), "Opening Old Files restarted the scan")
            XCTAssertFalse(stop.exists, "Opening Old Files restarted the scan")
            sidebar.staticTexts["Large Files"].click()
            XCTAssertTrue(app.staticTexts["Scan stopped"].appears(within: 5))
        }

        step("Large Files and Old Files with nothing to list show only a message, without an empty table (D-61)") {
            app.toolbars.buttons["Scan"].click()
            XCTAssertTrue(app.staticTexts["No files of at least 1 MB"].appears(within: 10))
            XCTAssertFalse(app.buttons["Size"].exists, "An empty table is shown")
            XCTAssertFalse(app.staticTexts["No items selected"].exists, "An empty table's footer is shown")

            // The shared scan already covered Old Files, so its page needs no scan of its own.
            sidebar.staticTexts["Old Files"].click()
            XCTAssertTrue(app.staticTexts["No files left unopened for 12 months"].appears(within: 5))
            XCTAssertFalse(app.buttons["Size"].exists, "An empty table is shown")
            attachScreenshot(of: app, named: "Old Files with nothing to list")
        }

        step("⌘N opens no second main window, and ⌘, opens Settings in a window of its own (D-27, D-91)") {
            // If ⌘N opened a window, there would be three once Settings is open.
            app.typeKey("n", modifierFlags: .command)
            app.typeKey(",", modifierFlags: .command)
            let summary = "Exclusions, thresholds and project folders."
            XCTAssertTrue(app.staticTexts[summary].appears(within: 5), "⌘, did not open Settings")
            XCTAssertTrue(app.staticTexts["Planned for milestone M5."].exists)
            XCTAssertEqual(app.windows.count, 2)
            let main = app.windows.containing(.outline, identifier: nil).element
            XCTAssertFalse(main.staticTexts[summary].exists, "Settings opened in the main window")
        }
    }
}
