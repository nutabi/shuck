import ShuckKitTestSupport
import XCTest

/// The base of every UI test: each test launches the app on its own fixture root, so the app never sees real user data
/// (NFR-QA-002, SAF-016), and from default preferences (D-70).
///
/// UI tests are user workflows (D-75): each test launches the app once and follows one realistic path through several
/// tools, in named steps (`step(_:_:)`). Each tool's and sub-tool's main path is a step of a workflow (NFR-QA-003). A
/// new tool or sub-tool adds its step to the workflow a user would follow, or adds a workflow, and lists it here:
///
/// - File Cleanup: Scan All and the de-duplicated total, in `FindWhatTakesSpaceUITests`.
/// - Large Files: scan, review and Move to Trash, in `CleanUpThenUndoUITests`; Stop a scan, in `FirstLookUITests`.
/// - Old Files: scan, review and Move to Trash, in `CleanUpThenUndoUITests`.
/// - History: a run's summary opens the run in History, in `CleanUpThenUndoUITests`.
/// - History's Restore: Keep Both for a taken place, then Restore All, in `CleanUpThenUndoUITests`.
/// - Overview, Developer Junk, Caches & Logs, Applications and Startup Items: a placeholder that names its milestone,
///   in `FirstLookUITests`.
/// - Settings: ⌘, opens its own window, and ⌘N opens no second main window, in `FirstLookUITests`.
///
/// Tests wait with `appears(within:)` and `disappears(within:)`, defined below, not with XCTest's own waits (D-74).
class ShuckUITestCase: XCTestCase {
    var root: FixtureRoot!

    override func setUpWithError() throws {
        continueAfterFailure = false
        root = try FixtureRoot()
    }

    override func tearDownWithError() throws {
        root = nil
    }

    /// Launches the app with the fixture root as its home folder and the minimum sizes of Large Files and Old Files at
    /// 1 MiB, so fixtures stay small. The app runs in English with the United States region, so the tests' expected
    /// text, such as "10.5 MB", doesn't depend on the Mac's own settings (TD-20).
    /// - Parameter scanDelay: Seconds each personal-files scan waits before it starts, so a test can stop one.
    @MainActor
    func launch(scanDelay: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ShuckFixtureRoot", root.url.path, "-LargeFilesMinimumSize", "\(1 << 20)", "-OldFilesMinimumSize",
            "\(1 << 20)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        if let scanDelay {
            app.launchArguments += ["-ShuckScanDelaySeconds", "\(scanDelay)"]
        }
        app.launch()
        return app
    }

    /// Runs one step of a workflow under its name in the test results, so a failure shows which step it was in.
    @MainActor
    func step(_ name: String, _ body: () throws -> Void) rethrows {
        try XCTContext.runActivity(named: name) { _ in try body() }
    }

    /// Kept in the test results, so reviewers can see the page (ENG-003).
    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

/// Waits that check every 0.1 s (D-74). XCTest's `waitForExistence(timeout:)` and `waitForNonExistence(timeout:)` first
/// check about a second after they start, so each of them costs at least a second, even for an element that is already
/// on screen.
@MainActor
extension XCUIElement {
    /// Whether the element exists within `timeout` seconds.
    func appears(within timeout: TimeInterval) -> Bool {
        wait(within: timeout, untilExists: true)
    }

    /// Whether the element is gone within `timeout` seconds.
    func disappears(within timeout: TimeInterval) -> Bool {
        wait(within: timeout, untilExists: false)
    }

    private func wait(within timeout: TimeInterval, untilExists expected: Bool) -> Bool {
        // One step in the test report, like XCTest's own waits, with each check inside it.
        let name = "Wait up to \(timeout) s for \(self) to \(expected ? "appear" : "disappear")"
        return XCTContext.runActivity(named: name) { _ in
            let deadline = Date.now.addingTimeInterval(timeout)
            while exists != expected {
                guard Date.now < deadline else { return false }
                Thread.sleep(forTimeInterval: 0.1)
            }
            return true
        }
    }
}
