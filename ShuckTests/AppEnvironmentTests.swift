import Foundation
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
        try AppEnvironment(arguments: arguments, minimumSizeSetting: nil, debugBuild: debugBuild, appBundle: appBundle)
    }

    @Test func aReleaseBuildIgnoresTheFixtureRootArgumentNFRQA002() throws {
        let arguments = ["Shuck", AppEnvironment.fixtureRootArgument, fixture]
        #expect(try AppEnvironment.fixtureRoot(in: arguments, debugBuild: false) == nil)
        #expect(try AppEnvironment.fixtureRoot(in: [AppEnvironment.fixtureRootArgument], debugBuild: false) == nil)

        let release = try environment(arguments, debugBuild: false)
        #expect(release.context.home == URL.homeDirectory.resolvingSymlinksInPath())
        #expect(release.context.protection.protectedLocations.contains(URL(filePath: "/private")))
    }

    @Test func aDebugBuildScansTheFixtureRootWithTheTestConfigurationNFRQA002() throws {
        let debug = try environment(["Shuck", AppEnvironment.fixtureRootArgument, fixture], debugBuild: true)

        #expect(debug.context.home.path(percentEncoded: false).hasPrefix(fixture))
        // D-41: only the temporary folder's /private prefix leaves the protected list.
        let protected = Set(debug.context.protection.protectedLocations.map(\.path))
        #expect(!protected.contains("/private"))
        #expect(protected.isSuperset(of: ["/System", "/usr", "/Library", appBundle.path]))
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
            #expect(throws: AppEnvironment.RejectedFixtureRoot.self, "\(path)") {
                try environment([AppEnvironment.fixtureRootArgument, path], debugBuild: true)
            }
        }
        #expect(throws: AppEnvironment.RejectedFixtureRoot.self) {
            try environment([AppEnvironment.fixtureRootArgument], debugBuild: true)
        }
    }

    @Test func largeFilesMinimumSizeComesFromTheSettingSET002() throws {
        #expect(AppEnvironment.minimumSize(nil) == 500_000_000)
        #expect(AppEnvironment.minimumSize(NSNumber(value: 1_048_576)) == 1_048_576)
        #expect(AppEnvironment.minimumSize("2097152") == 2_097_152)
        #expect(AppEnvironment.minimumSize("large") == 500_000_000)
        #expect(AppEnvironment.minimumSize(NSNumber(value: -1)) == 500_000_000)

        let environment = try AppEnvironment(
            arguments: [], minimumSizeSetting: "1000", debugBuild: false, appBundle: appBundle)
        #expect(environment.largeFiles.minimumSize == 1_000)
    }
}
