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
        // Music and TV libraries in their default places. Photos libraries are matched by extension.
        "Music/Music", "Movies/TV",
        // Shuck's own data folder (D-21).
        "Library/Application Support/me.nutabi.shuck",
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
    }

    /// The configuration the app uses: the real home folder and the full protected list.
    public static func production(home: URL, appBundle: URL, userExclusions: [URL]) -> Self {
        Self(home: home, systemLocations: systemLocations, appBundle: appBundle, userExclusions: userExclusions)
    }
}
