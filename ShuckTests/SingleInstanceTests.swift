import Testing

@testable import Shuck

/// A second launch of the same build hands over to the first (SAF-018).
struct SingleInstanceTests {
    @Test func aSecondInstanceHandsOverToTheFirstUnlessItIsATestLaunchSAF018() {
        #expect(SingleInstance.instanceToActivate(running: [100, 200], current: 200, testLaunch: false) == 100)
        #expect(SingleInstance.instanceToActivate(running: [200], current: 200, testLaunch: false) == nil)
        #expect(SingleInstance.instanceToActivate(running: [], current: 200, testLaunch: false) == nil)
        #expect(SingleInstance.instanceToActivate(running: [100, 200], current: 200, testLaunch: true) == nil)
    }

    /// A fixture-root launch and a test host are test launches in a debug build; a release build never is.
    @Test(arguments: [true, false])
    func onlyADebugBuildHasTestLaunchesSAF018(debugBuild: Bool) {
        let fixture = [AppEnvironment.fixtureRootArgument, "/tmp/root"]
        let host = ["XCTestConfigurationFilePath": "/x"]
        #expect(SingleInstance.isTestLaunch(arguments: fixture, environment: [:], debugBuild: debugBuild) == debugBuild)
        #expect(SingleInstance.isTestLaunch(arguments: [], environment: host, debugBuild: debugBuild) == debugBuild)
        #expect(!SingleInstance.isTestLaunch(arguments: ["Shuck"], environment: [:], debugBuild: debugBuild))
    }
}
