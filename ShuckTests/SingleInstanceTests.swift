import Testing

@testable import Shuck

/// A second launch of the same build hands over to the first (SAF-018).
struct SingleInstanceTests {
    @Test func anotherInstanceIsActivatedSAF018() {
        #expect(SingleInstance.instanceToActivate(running: [100, 200], current: 200, testLaunch: false) == 100)
    }

    @Test func aLoneInstanceGoesOnSAF018() {
        #expect(SingleInstance.instanceToActivate(running: [200], current: 200, testLaunch: false) == nil)
        #expect(SingleInstance.instanceToActivate(running: [], current: 200, testLaunch: false) == nil)
    }

    @Test func aFixtureRootLaunchAndATestHostAreTestLaunchesSAF018() {
        let fixture = [AppEnvironment.fixtureRootArgument, "/tmp/root"]
        #expect(SingleInstance.isTestLaunch(arguments: fixture, environment: [:]))
        #expect(SingleInstance.isTestLaunch(arguments: [], environment: ["XCTestConfigurationFilePath": "/x"]))
        #expect(!SingleInstance.isTestLaunch(arguments: ["Shuck"], environment: [:]))
    }

    @Test func aTestLaunchSkipsTheCheckSAF018() {
        #expect(SingleInstance.instanceToActivate(running: [100, 200], current: 200, testLaunch: true) == nil)
    }
}
