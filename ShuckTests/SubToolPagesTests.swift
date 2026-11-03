import Foundation
import ShuckKit
import Testing

@testable import Shuck

/// The main window finds a sub-tool's page by its tool ID, so a new sub-tool needs no change to `ContentView`
/// (FCL-003).
@MainActor
struct SubToolPagesTests {
    let pages = SubToolPages(largeFiles: LargeFiles(), oldFiles: OldFiles())
    let registry = ToolRegistry.standard

    @Test func everyAvailableSubToolHasAPageAndPlannedOnesHaveNoneFCL003() {
        let model = FileCleanupModel(
            subTools: registry.subTools, context: ScanContext(home: URL(filePath: "/StubHome")))

        for subTool in registry.subTools {
            let available = subTool.info.availability == .available
            #expect((pages.page(subTool.id, model: model, registry: registry) != nil) == available, "\(subTool.id)")
        }
        // A tool's own page, such as File Cleanup's landing page, isn't a sub-tool page.
        #expect(pages.page(.fileCleanup, model: model, registry: registry) == nil)
    }

    @Test func aSubToolTheModelHasNoResultsForHasNoPage() {
        let model = FileCleanupModel(subTools: [], context: ScanContext(home: URL(filePath: "/StubHome")))

        #expect(pages.page(.largeFiles, model: model, registry: registry) == nil)
    }
}
