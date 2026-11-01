import Testing

@testable import ShuckKit

struct ShuckKitTests {
    @Test func loggerSubsystemIsTheBundleID() {
        #expect(ShuckKit.loggerSubsystem == "me.nutabi.shuck")
    }
}
