import Foundation

/// What the path guard protects: the home folder and the protected locations of PRD section 8.4 (D-41).
///
/// The app builds its one configuration with ``production(home:appBundle:userExclusions:)``. Tests build theirs from
/// the fixture root with the same initializer, dropping only `/private`, which contains the temporary folder.
public struct PathGuardConfiguration: Sendable, Equatable {
    /// System and admin-owned folders (section 8.4). `/opt/homebrew` is touched only through `brew`.
    public static let systemLocations = ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/opt"]

    /// Protected folders and files inside the home folder, relative to it (section 8.4).
    public static let homeLocations = [
        // Synced storage: iCloud Drive and other sync providers.
        "Library/Mobile Documents", "Library/CloudStorage",
        // Personal data and credentials.
        "Library/Mail", "Library/Messages", "Library/Keychains",
        // Developer credentials.
        ".ssh", ".gnupg", ".aws", ".kube", ".azure", ".docker", ".netrc", ".password-store", ".config/gcloud",
        // Stores a tool manages, which only the tool's own command may change (DEV-007): the simulators' devices and
        // runtimes, which `simctl` manages, and Docker's disk image. Homebrew's Cellar lies in /opt, a system location.
        "Library/Developer/CoreSimulator/Devices", "Library/Developer/CoreSimulator/Volumes",
        "Library/Containers/com.docker.docker", "Library/Group Containers/group.com.docker",
        // Music and TV libraries in their default places. Photos libraries are matched by extension.
        "Music/Music", "Movies/TV",
        // Shuck's own data folders: the release build's and the debug build's (D-21, D-70).
        ShuckKit.dataFolder(bundleID: ShuckKit.bundleID), ShuckKit.dataFolder(bundleID: ShuckKit.debugBundleID),
    ]

    /// Bundles protected wherever they are: Photos, iPhoto, Music and TV libraries, and Time Machine backups.
    public static let protectedExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "backupbundle",
    ]

    /// Folder names protected wherever they are: a Time Machine backup folder.
    public static let protectedNames: Set<String> = ["Backups.backupdb"]

    /// The home folder, with symlinks resolved.
    public let home: URL

    /// Every protected location as an absolute path with symlinks resolved.
    public let protectedLocations: [URL]

    /// The folders and files the user excluded in Settings (SET-001), as absolute paths with symlinks resolved. They
    /// are also in ``protectedLocations``, so the guard refuses them like any protected location; this list tells a
    /// scan which of them are the user's, for a command item that is not a path the guard can validate (D-149).
    public let userExclusions: [URL]

    /// Builds a configuration from a home folder. Prefer ``production(home:appBundle:userExclusions:)`` in the app.
    ///
    /// - Parameters:
    ///   - home: The home folder; ``homeLocations`` are derived from it.
    ///   - systemLocations: Absolute protected folders, normally ``systemLocations``.
    ///   - appBundle: Shuck's own app bundle (self-protection).
    ///   - userExclusions: Paths the user added in Settings (SET-001).
    public init(home: URL, systemLocations: [String], appBundle: URL, userExclusions: [URL]) {
        let home = ResolvedPath(home)?.url ?? home
        self.home = home
        let locations =
            systemLocations.map { URL(filePath: $0) }
            + Self.homeLocations.map { home.appending(path: $0) }
            + [appBundle] + userExclusions
        protectedLocations = locations.map { ResolvedPath($0)?.url ?? $0 }
        self.userExclusions = userExclusions.map { ResolvedPath($0)?.url ?? $0 }
    }

    /// Whether `url` is inside one of the user's exclusions or contains one, compared as the guard compares: with case
    /// folded and Unicode forms equal (SET-001, D-79). A scan hides what this says yes to, and the guard would refuse
    /// it anyway.
    public func overlapsUserExclusion(_ url: URL) -> Bool {
        let target = (ResolvedPath(url)?.url ?? url).pathComponents.map(PathGuard.fold)
        return userExclusions.contains { exclusion in
            let excluded = exclusion.pathComponents.map(PathGuard.fold)
            return target.starts(with: excluded) || excluded.starts(with: target)
        }
    }

    /// The configuration the app uses: the real home folder and the full protected list.
    public static func production(home: URL, appBundle: URL, userExclusions: [URL]) -> Self {
        Self(home: home, systemLocations: systemLocations, appBundle: appBundle, userExclusions: userExclusions)
    }
}
