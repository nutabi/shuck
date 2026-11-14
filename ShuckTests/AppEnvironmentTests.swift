import Foundation
import ShuckExecution
import ShuckKit
import Testing

@testable import Shuck

/// The app scans the real home folder, or a UI test's fixture root in a debug build only (NFR-QA-002).
///
/// The tests pass a made-up home folder, so they never name the real one (SAF-016), and create an empty fixture root
/// in the temporary folder, as the test harness does. They only build URLs and configurations; nothing writes to the
/// folders they name.
final class AppEnvironmentTests {
    /// An empty `ShuckFixtures/<UUID>` folder, as the temporary folder spells it: `/var/folders/…`, through the
    /// symlink to `/private/var` (TD-12).
    let fixture: String
    let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
    let appBundle = URL(filePath: "/Applications/Shuck.app")

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShuckFixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fixture = folder.path(percentEncoded: false)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: fixture)
    }

    private func environment(_ arguments: [String], debugBuild: Bool) throws -> AppEnvironment {
        try AppEnvironment(
            arguments: arguments, settings: { _ in nil }, debugBuild: debugBuild, appBundle: appBundle,
            bundleID: debugBuild ? ShuckKit.debugBundleID : ShuckKit.bundleID, home: home)
    }

    /// A release build ignores the fixture root and every setting a UI test uses: the real home folder, the system
    /// Trash and running apps, no synced names, and no scan delay.
    @Test func aReleaseBuildIgnoresTheFixtureRootAndEverySettingATestUsesNFRQA002SAF009SAF014FCL010() throws {
        let arguments = ["Shuck", AppEnvironment.fixtureRootArgument, fixture]
        #expect(try AppEnvironment.fixtureRoot(in: arguments, debugBuild: false) == nil)
        #expect(try AppEnvironment.fixtureRoot(in: [AppEnvironment.fixtureRootArgument], debugBuild: false) == nil)
        let stored: [String: Any] = [
            AppEnvironment.runningAppsKey: "com.example.Other", AppEnvironment.syncedFilesKey: "a.mov",
            AppEnvironment.scanDelayKey: "2",
        ]

        for arguments in [arguments, ["Shuck"]] {
            let release = try AppEnvironment(
                arguments: arguments, settings: { stored[$0] }, debugBuild: false, appBundle: appBundle,
                bundleID: ShuckKit.bundleID, home: home)
            #expect(release.context.home == home)
            #expect(release.context.protection.protectedLocations.contains(URL(filePath: "/private")))
            #expect(release.trash is SystemTrash)
            #expect(release.runningApps is SystemRunningApps && release.context.runningApps is SystemRunningApps)
            #expect(release.syncedNames.isEmpty)
            #expect(
                try #require(release.readValues(URL(filePath: fixture, directoryHint: .isDirectory))).isSynced == false)
            #expect(release.scanDelay == nil)
        }
    }

    @Test func aDebugBuildScansTheFixtureRootWithTheTestConfigurationNFRQA002() throws {
        let debug = try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true)

        // The root with its symlinks resolved, as the test harness reports it: /private/var, not /var (TD-12).
        #expect(debug.context.home.pathComponents.starts(with: ["/", "private", "var", "folders"]))
        #expect(debug.context.home.lastPathComponent == URL(filePath: fixture).lastPathComponent)
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
        let _: RunPlan = debug.run
        // So does History's restore, which puts items back from that Trash (HIS-003).
        let _: HistoryRestore.RunRestore = debug.restore
    }

    /// Xcode runs the UI tests, so a fixture root never reads this Mac's running apps; the real home folder does
    /// (SAF-009, D-110).
    @Test func aFixtureRootStubsTheRunningAppsSAF009() throws {
        let debug = try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true)
        #expect(debug.runningApps.bundleIDs().isEmpty)
        #expect(debug.runningApps is StubRunningApps && debug.context.runningApps is StubRunningApps)
    }

    /// A UI test can pretend an app runs (D-113), but only on a fixture root; the real home folder never reads it.
    @Test func aFixtureRootRunsOnlyTheAppsTheTestNamesSAF009() throws {
        let key = AppEnvironment.runningAppsKey
        let settings: AppEnvironment.Settings = { $0 == key ? " com.apple.dt.Xcode, ,com.example.Other" : nil }
        func environment(_ arguments: [String], debugBuild: Bool) throws -> AppEnvironment {
            try AppEnvironment(
                arguments: arguments, settings: settings, debugBuild: debugBuild, appBundle: appBundle,
                bundleID: debugBuild ? ShuckKit.debugBundleID : ShuckKit.bundleID, home: home)
        }
        let debug = try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true)
        #expect(debug.runningApps.bundleIDs() == ["com.apple.dt.xcode", "com.example.other"])
        #expect(debug.context.runningApps.bundleIDs() == debug.runningApps.bundleIDs())
        #expect(AppEnvironment.list(nil).isEmpty && AppEnvironment.list(3).isEmpty)
    }

    /// A UI test can mark items as synced by iCloud, since a fixture file cannot be (FCL-010, D-137), but only on a
    /// fixture root; the real home folder never reads it.
    @Test func onlyAFixtureRootMarksTheItemsTheTestNamesAsSyncedFCL010() throws {
        let folder = URL(filePath: fixture, directoryHint: .isDirectory)
        let settings: AppEnvironment.Settings = {
            $0 == AppEnvironment.syncedFilesKey ? "Other.mov,\(folder.lastPathComponent)" : nil
        }
        let uiTest = try AppEnvironment(
            arguments: ["Shuck", AppEnvironment.fixtureRootArgument, fixture], settings: settings, debugBuild: true,
            appBundle: appBundle, bundleID: ShuckKit.debugBundleID, home: home)
        #expect(uiTest.syncedNames == ["Other.mov", folder.lastPathComponent])
        #expect(try #require(uiTest.readValues(folder)).isSynced)
        #expect(try #require(uiTest.readValues(folder)).isDirectory)

        let app = try AppEnvironment(
            arguments: ["Shuck"], settings: settings, debugBuild: true, appBundle: appBundle,
            bundleID: ShuckKit.debugBundleID, home: home)
        #expect(app.syncedNames.isEmpty)
        #expect(try #require(app.readValues(folder)).isSynced == false)
    }

    /// A UI test can delay the personal-files scan to stop it (SAF-014). Without a fixture root, the setting is ignored.
    @Test func onlyAUITestsDebugBuildDelaysItsScansSAF014() throws {
        let settings: AppEnvironment.Settings = { $0 == AppEnvironment.scanDelayKey ? "2" : nil }
        let uiTest = try AppEnvironment(
            arguments: ["Shuck", AppEnvironment.fixtureRootArgument, fixture], settings: settings, debugBuild: true,
            appBundle: appBundle, bundleID: ShuckKit.debugBundleID, home: home)
        #expect(uiTest.scanDelay == .seconds(2))

        let app = try AppEnvironment(
            arguments: ["Shuck"], settings: settings, debugBuild: true, appBundle: appBundle,
            bundleID: ShuckKit.debugBundleID, home: home)
        #expect(app.scanDelay == nil)
        #expect(
            try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true).scanDelay == nil)
    }

    @Test func aTestProcessesAndTheUITestRunnersTemporaryFoldersHaveTheShapeOfAFixtureRoot() {
        let uuid = UUID().uuidString
        let accepted = [
            "/private/var/folders/ab/xyz/T/ShuckFixtures/\(uuid)",
            "/Users/someone/Library/Containers/me.nutabi.ShuckUITests.xctrunner/Data/tmp/ShuckFixtures/\(uuid)",
        ]
        for path in accepted { #expect(AppEnvironment.isFixtureRootShape(URL(filePath: path)), "\(path)") }
    }

    /// A rejected root stops the app instead of letting it fall back to the real home folder (SAF-016).
    @Test func anyOtherFolderIsRejectedSAF016() {
        let uuid = UUID().uuidString
        let shapes = [
            "/Users/someone",
            "/Users/someone/ShuckFixtures/\(uuid)",
            "/private/var/folders/ab/xyz/T/Other/\(uuid)",
            "/private/var/folders/ab/xyz/T/ShuckFixtures/not-a-uuid",
            "/tmp/ShuckFixtures/\(uuid)",
            "/Users/someone/Library/Containers/com.example.App/Data/tmp/ShuckFixtures/\(uuid)",
        ]
        for path in shapes { #expect(!AppEnvironment.isFixtureRootShape(URL(filePath: path)), "\(path)") }
        // A fixture root that does not exist, although its shape is right.
        let missing = URL(filePath: fixture).deletingLastPathComponent().appending(path: UUID().uuidString).path
        for path in shapes + [missing] {
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
                    bundleID: bundleID, home: home)
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

    /// A stored number is read as a number or a string; a missing, invalid or negative one falls back to the default.
    @Test func thresholdsComeFromTheSettingsOrTheirDefaultsSET002() throws {
        func environment(_ stored: [String: Any]) throws -> AppEnvironment {
            try AppEnvironment(
                arguments: [], settings: { stored[$0] }, debugBuild: false, appBundle: appBundle,
                bundleID: ShuckKit.bundleID, home: home)
        }
        let set = try environment([
            AppEnvironment.largeFilesMinimumSizeKey: "1000", AppEnvironment.oldFilesPeriodKey: NSNumber(value: 3),
            AppEnvironment.oldFilesMinimumSizeKey: "0",
        ])
        #expect(set.largeFiles.minimumSize == 1_000)
        #expect(set.oldFiles.periodMonths == 3)
        #expect(set.oldFiles.minimumSize == 0)

        let invalid = try environment([
            AppEnvironment.largeFilesMinimumSizeKey: "large", AppEnvironment.oldFilesPeriodKey: "0",
            AppEnvironment.oldFilesMinimumSizeKey: NSNumber(value: -1),
        ])
        #expect(invalid.largeFiles.minimumSize == 500_000_000)
        #expect(invalid.oldFiles.periodMonths == 12)
        #expect(invalid.oldFiles.minimumSize == 50_000_000)

        let missing = try environment([:])
        #expect(missing.largeFiles.minimumSize == 500_000_000)
    }
}
