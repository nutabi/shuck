import Foundation
import ShuckExecution
import ShuckKit
import Testing

@testable import Shuck

/// The app scans the real home folder, or a UI test's fixture root in a debug build only (NFR-QA-002).
///
/// These tests only build URLs and configurations; nothing reads the folders they name.
struct AppEnvironmentTests {
    let fixture = "/private/var/folders/ab/xyz/T/ShuckFixtures/\(UUID().uuidString)"
    let appBundle = URL(filePath: "/Applications/Shuck.app")

    private func environment(_ arguments: [String], debugBuild: Bool) throws -> AppEnvironment {
        try AppEnvironment(
            arguments: arguments, settings: { _ in nil }, debugBuild: debugBuild, appBundle: appBundle,
            bundleID: debugBuild ? ShuckKit.debugBundleID : ShuckKit.bundleID)
    }

    @Test func aReleaseBuildIgnoresTheFixtureRootArgumentNFRQA002() throws {
        let arguments = ["Shuck", AppEnvironment.fixtureRootArgument, fixture]
        #expect(try AppEnvironment.fixtureRoot(in: arguments, debugBuild: false) == nil)
        #expect(try AppEnvironment.fixtureRoot(in: [AppEnvironment.fixtureRootArgument], debugBuild: false) == nil)

        let release = try environment(arguments, debugBuild: false)
        #expect(release.context.home == URL.homeDirectory.resolvingSymlinksInPath())
        #expect(release.context.protection.protectedLocations.contains(URL(filePath: "/private")))
        #expect(release.trash is SystemTrash)
    }

    @Test func aDebugBuildScansTheFixtureRootWithTheTestConfigurationNFRQA002() throws {
        let debug = try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true)

        #expect(debug.context.home.path(percentEncoded: false).hasPrefix(fixture))
        // D-41: only the temporary folder's /private prefix leaves the protected list.
        let protected = Set(debug.context.protection.protectedLocations.map(\.path))
        #expect(!protected.contains("/private"))
        #expect(protected.isSuperset(of: ["/System", "/usr", "/Library", appBundle.path]))
    }

    /// A UI test's runs move items into the fixture root's own Trash, never the real one (D-47, D-63).
    @Test func aDebugBuildOnAFixtureRootUsesAFolderTrashInsideItSAF016() throws {
        let debug = try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true)

        let trash = try #require(debug.trash as? FolderTrash)
        #expect(trash.folder == debug.context.home.appending(path: ".Trash"))
        #expect(!(debug.trash is SystemTrash))
        // The run the review sheet calls has the type the review expects.
        let _: TrashReview.RunPlan = debug.run
    }

    @Test func theUITestRunnersContainerIsAccepted() throws {
        let runner =
            "/Users/someone/Library/Containers/me.nutabi.ShuckUITests.xctrunner/Data/tmp/ShuckFixtures/"
            + UUID().uuidString
        let root = try AppEnvironment.fixtureRoot(in: [AppEnvironment.fixtureRootArgument, runner], debugBuild: true)
        #expect(root?.path(percentEncoded: false).hasPrefix(runner) == true)
    }

    /// A rejected root stops the app instead of letting it fall back to the real home folder (SAF-016).
    @Test func anyOtherFolderIsRejectedSAF016() {
        let uuid = UUID().uuidString
        let paths = [
            "/Users/someone",
            "/Users/someone/ShuckFixtures/\(uuid)",
            "/private/var/folders/ab/xyz/T/Other/\(uuid)",
            "/private/var/folders/ab/xyz/T/ShuckFixtures/not-a-uuid",
            "/tmp/ShuckFixtures/\(uuid)",
            "/Users/someone/Library/Containers/com.example.App/Data/tmp/ShuckFixtures/\(uuid)",
        ]
        for path in paths {
            #expect(throws: AppEnvironment.LaunchError.self, "\(path)") {
                try environment([AppEnvironment.fixtureRootArgument, path], debugBuild: true)
            }
        }
        #expect(throws: AppEnvironment.LaunchError.self) {
            try environment([AppEnvironment.fixtureRootArgument], debugBuild: true)
        }
    }

    /// D-70: the release build and the debug build each keep their history log in a data folder named after their own
    /// bundle ID.
    @Test func eachBuildKeepsItsHistoryInItsOwnDataFolder() throws {
        let home = URL.homeDirectory.resolvingSymlinksInPath()
        let release = try environment(["Shuck"], debugBuild: false)
        #expect(release.historyFolder == home.appending(path: "Library/Application Support/me.nutabi.shuck"))

        let debug = try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true)
        #expect(
            debug.historyFolder
                == debug.context.home.appending(path: "Library/Application Support/me.nutabi.shuck.debug"))
    }

    /// D-70: a build with another build's bundle ID, or none, stops at launch instead of sharing that build's
    /// preferences and data folder.
    @Test func aBuildWithAnotherBuildsBundleIDStops() {
        for (bundleID, debugBuild) in [
            (ShuckKit.bundleID, true), (ShuckKit.debugBundleID, false), ("com.example.Other", false), (nil, true),
        ] as [(String?, Bool)] {
            #expect(throws: AppEnvironment.LaunchError.self, "\(bundleID ?? "none")") {
                try AppEnvironment(
                    arguments: [], settings: { _ in nil }, debugBuild: debugBuild, appBundle: appBundle,
                    bundleID: bundleID)
            }
        }
    }

    /// D-70: only a debug build launched on a fixture root clears preferences, and only its own domain.
    @Test func onlyAUITestsDebugBuildClearsItsOwnPreferences() {
        let uiTest = ["Shuck", AppEnvironment.fixtureRootArgument, fixture]
        let debugID = ShuckKit.debugBundleID
        #expect(AppEnvironment.preferencesToClear(arguments: uiTest, bundleID: debugID, debugBuild: true) == debugID)

        #expect(AppEnvironment.preferencesToClear(arguments: uiTest, bundleID: debugID, debugBuild: false) == nil)
        #expect(
            AppEnvironment.preferencesToClear(arguments: uiTest, bundleID: ShuckKit.bundleID, debugBuild: true) == nil)
        #expect(AppEnvironment.preferencesToClear(arguments: ["Shuck"], bundleID: debugID, debugBuild: true) == nil)
        let rejected = ["Shuck", AppEnvironment.fixtureRootArgument, "/Users/someone"]
        #expect(AppEnvironment.preferencesToClear(arguments: rejected, bundleID: debugID, debugBuild: true) == nil)
    }

    @Test func storedNumbersAreReadAsNumbersOrStrings() {
        #expect(AppEnvironment.number(nil) == nil)
        #expect(AppEnvironment.number(NSNumber(value: 1_048_576)) == 1_048_576)
        #expect(AppEnvironment.number("2097152") == 2_097_152)
        #expect(AppEnvironment.number("large") == nil)
        #expect(AppEnvironment.number(NSNumber(value: -1)) == nil)
    }

    @Test func thresholdsComeFromTheSettingsSET002() throws {
        let stored: [String: Any] = [
            AppEnvironment.largeFilesMinimumSizeKey: "1000", AppEnvironment.oldFilesPeriodKey: NSNumber(value: 3),
            AppEnvironment.oldFilesMinimumSizeKey: "0",
        ]
        let environment = try AppEnvironment(
            arguments: [], settings: { stored[$0] }, debugBuild: false, appBundle: appBundle,
            bundleID: ShuckKit.bundleID)

        #expect(environment.largeFiles.minimumSize == 1_000)
        #expect(environment.oldFiles.periodMonths == 3)
        #expect(environment.oldFiles.minimumSize == 0)
    }

    @Test func missingOrInvalidThresholdsUseTheDefaultsSET002() throws {
        let stored: [String: Any] = [
            AppEnvironment.largeFilesMinimumSizeKey: "large", AppEnvironment.oldFilesPeriodKey: "0",
        ]
        let environment = try AppEnvironment(
            arguments: [], settings: { stored[$0] }, debugBuild: false, appBundle: appBundle,
            bundleID: ShuckKit.bundleID)

        #expect(environment.largeFiles.minimumSize == 500_000_000)
        #expect(environment.oldFiles.periodMonths == 12)
        #expect(environment.oldFiles.minimumSize == 50_000_000)
    }
}
