import Foundation
import ShuckKit

extension FixtureRoot {
    /// The path-guard configuration for tests, with the fixture root as the home folder (D-41).
    ///
    /// Built exactly like the production configuration, with one difference: the system list drops `/private`, which
    /// contains the temporary folder and so the fixture root. Every other protected location stays protected.
    /// Shuck's app bundle is `Applications/Shuck.app` inside the root.
    public func pathGuardConfiguration(userExclusions: [URL] = []) -> PathGuardConfiguration {
        PathGuardConfiguration(
            home: url,
            systemLocations: PathGuardConfiguration.systemLocations.filter { $0 != "/private" },
            appBundle: url.appending(path: "Applications/Shuck.app"),
            userExclusions: userExclusions
        )
    }
}
