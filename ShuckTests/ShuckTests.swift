import AppKit
import ShuckKit
import Testing

@testable import Shuck

struct EngineLinkTests {
    /// The app links ShuckKit. The debug build, which hosts these tests, has its own bundle ID and logs under the
    /// release build's, which is the engine's logger subsystem (D-21, D-70).
    @Test func theDebugBuildHasItsOwnBundleIDAndTheReleaseSubsystem() {
        #expect(Bundle.main.bundleIdentifier == "me.nutabi.shuck.debug")
        #expect(ShuckKit.loggerSubsystem == "me.nutabi.shuck")
    }
}

struct SidebarDestinationTests {
    @Test func everyRegistryToolAndSubToolHasALabel() {
        let ids = ToolRegistry.standard.tools.map(\.info.id) + ToolRegistry.standard.subTools.map(\.id)
        for id in ids {
            #expect(SidebarDestination.tool(id).label(in: .standard) != nil, "No label for \(id.rawValue)")
        }
    }

    @Test func anUnknownToolHasNoLabel() {
        #expect(SidebarDestination.tool(ToolID(rawValue: "XXX")).label(in: .standard) == nil)
    }

    @Test(arguments: [SidebarDestination.overview, .history, .tool(.fileCleanup), .tool(.largeFiles)])
    func symbolExists(destination: SidebarDestination) throws {
        let label = try #require(destination.label(in: .standard))
        #expect(NSImage(systemSymbolName: label.symbolName, accessibilityDescription: nil) != nil)
    }
}
