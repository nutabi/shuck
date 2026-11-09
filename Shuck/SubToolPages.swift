import ShuckKit
import SwiftUI

/// Each sub-tool's page, found by its tool ID (FCL-003). The main window shows the selected sub-tool's page, or a
/// placeholder for a sub-tool that has none yet, so a new sub-tool adds its page here and nothing to `ContentView`.
struct SubToolPages {
    /// Builds a page, or returns `nil` if the model has no results for the sub-tool. `AnyView` lets pages of different
    /// types share one table.
    typealias Page = (FileCleanupModel, ToolRegistry) -> AnyView?

    private let pages: [ToolID: Page]

    /// Takes the sub-tools the registry lists, with the user's settings (SET-002).
    init(
        largeFiles: LargeFiles, oldFiles: OldFiles, developerJunk: DeveloperJunk = DeveloperJunk(),
        cachesAndLogs: CachesAndLogs = CachesAndLogs()
    ) {
        pages = [
            developerJunk.id: { model, _ in
                model.scanResults[developerJunk.id].map { results in
                    AnyView(DeveloperJunkView(subTool: developerJunk, model: model, results: results))
                }
            },
            cachesAndLogs.id: { model, _ in
                model.scanResults[cachesAndLogs.id].map { results in
                    AnyView(CachesAndLogsView(subTool: cachesAndLogs, model: model, results: results))
                }
            },
            largeFiles.id: { model, registry in
                model.personalFilesResults[largeFiles.id].map { results in
                    AnyView(LargeFilesView(subTool: largeFiles, model: model, results: results, registry: registry))
                }
            },
            oldFiles.id: { model, registry in
                model.personalFilesResults[oldFiles.id].map { results in
                    AnyView(OldFilesView(subTool: oldFiles, model: model, results: results, registry: registry))
                }
            },
        ]
    }

    /// The page of the sub-tool with `id`, or `nil` if it has none.
    func page(_ id: ToolID, model: FileCleanupModel, registry: ToolRegistry) -> AnyView? {
        pages[id]?(model, registry)
    }
}
