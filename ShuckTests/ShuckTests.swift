import AppKit
import ShuckKit
import Testing

@testable import Shuck

struct SidebarDestinationTests {
    /// A destination without a label shows nothing, and one with a label needs an SF Symbol that exists, or its row has
    /// no icon.
    @Test func everyRegistryToolAndSubToolHasALabelWithASymbol() throws {
        let ids = ToolRegistry.standard.tools.map(\.info.id) + ToolRegistry.standard.subTools.map(\.id)
        let destinations = [SidebarDestination.overview, .history] + ids.map { SidebarDestination.tool($0) }
        for destination in destinations {
            let label = try #require(destination.label(in: .standard), "No label for \(destination)")
            #expect(
                NSImage(systemSymbolName: label.symbolName, accessibilityDescription: nil) != nil,
                "No symbol \(label.symbolName)")
        }
        #expect(SidebarDestination.tool(ToolID(rawValue: "XXX")).label(in: .standard) == nil)
    }
}
