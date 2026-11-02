import Foundation
import ShuckKit

/// Where the app scans and with which settings: the real home folder, or a UI test's fixture root (NFR-QA-002).
nonisolated struct AppEnvironment {
    let context: ScanContext
    let largeFiles: LargeFiles

    /// The launch argument UI tests pass, followed by the fixture root's path. Release builds ignore it.
    static let fixtureRootArgument = "-ShuckFixtureRoot"
    /// Large Files' minimum size in bytes, in `UserDefaults` (SET-002, SET-004). Settings gets a control in M5.
    static let largeFilesMinimumSizeKey = "LargeFilesMinimumSize"

    static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// A fixture-root argument the app refuses. The app stops instead of falling back to the real home folder.
    struct RejectedFixtureRoot: Error, CustomStringConvertible {
        let path: String
        var description: String { "Not a fixture root the test harness made: \(path)" }
    }

    /// - Parameters:
    ///   - arguments: The process's launch arguments.
    ///   - minimumSizeSetting: The stored value for ``largeFilesMinimumSizeKey``, if any.
    ///   - debugBuild: Whether the fixture-root argument counts.
    /// - Throws: ``RejectedFixtureRoot`` if a debug build gets a fixture-root argument it does not accept.
    init(
        arguments: [String], minimumSizeSetting: Any?, debugBuild: Bool = isDebugBuild,
        appBundle: URL = Bundle.main.bundleURL
    ) throws(RejectedFixtureRoot) {
        if let root = try Self.fixtureRoot(in: arguments, debugBuild: debugBuild) {
            // The engine tests' configuration (D-41): only the temporary folder's /private prefix is left out.
            let protection = PathGuardConfiguration(
                home: root, systemLocations: PathGuardConfiguration.systemLocations.filter { $0 != "/private" },
                appBundle: appBundle, userExclusions: [])
            context = ScanContext(home: root, protection: protection)
        } else {
            // The ownership map compares paths with symlinks resolved (D-53).
            let home = URL.homeDirectory.resolvingSymlinksInPath()
            context = ScanContext(
                home: home, protection: .production(home: home, appBundle: appBundle, userExclusions: []))
        }
        largeFiles = LargeFiles(minimumSize: Self.minimumSize(minimumSizeSetting))
    }

    /// The fixture root after ``fixtureRootArgument`` in a debug build, or `nil` if there is none.
    ///
    /// Only a folder the test harness creates is accepted: `ShuckFixtures/<UUID>` in the temporary folder, which is
    /// `/private/var/folders/…` for a test process, or the sandboxed UI test runner's container
    /// (`~/Library/Containers/<name>.xctrunner/Data/tmp`). Anything else throws, so a debug build is never pointed at
    /// real data by mistake.
    static func fixtureRoot(in arguments: [String], debugBuild: Bool) throws(RejectedFixtureRoot) -> URL? {
        guard debugBuild, let index = arguments.firstIndex(of: fixtureRootArgument) else { return nil }
        guard index + 1 < arguments.count else { throw RejectedFixtureRoot(path: "") }
        let root = URL(filePath: arguments[index + 1], directoryHint: .isDirectory).resolvingSymlinksInPath()
        let parts = root.pathComponents
        guard parts.count > 2, parts[parts.count - 2] == "ShuckFixtures",
            UUID(uuidString: parts[parts.count - 1]) != nil
        else { throw RejectedFixtureRoot(path: root.path) }
        let temporary = Array(parts.dropLast(2))
        let isProcessTemporary = temporary.starts(with: ["/", "private", "var", "folders"])
        // …/Library/Containers/<name>.xctrunner/Data/tmp
        let tail = Array(temporary.suffix(5))
        let isRunnerTemporary =
            tail.count == 5 && tail[0] == "Library" && tail[1] == "Containers" && tail[2].hasSuffix(".xctrunner")
            && tail[3] == "Data" && tail[4] == "tmp"
        guard isProcessTemporary || isRunnerTemporary else { throw RejectedFixtureRoot(path: root.path) }
        return root
    }

    /// The stored minimum size, or the default if there is none or it is not a size.
    static func minimumSize(_ setting: Any?) -> Int64 {
        let value: Int64? =
            switch setting {
            case let number as NSNumber: number.int64Value
            // A launch argument such as `-LargeFilesMinimumSize 1048576` arrives as a string.
            case let text as String: Int64(text)
            default: nil
            }
        guard let value, value >= 0 else { return LargeFiles.defaultMinimumSize }
        return value
    }
}
