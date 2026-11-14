import Testing

@testable import ShuckKit

struct ShuckKitTests {
    /// One category per tool and sub-tool, so a failed action is logged under the tool that ran it (NFR-OBS-001).
    @Test func everyToolLogsUnderACategoryOfItsOwn() {
        let tools: [ToolID] = [
            .fileCleanup, .largeFiles, .oldFiles, .developerJunk, .cachesAndLogs, .applications, .startupItems,
            .history,
        ]
        let categories = tools.map(\.loggerCategory)
        #expect(Set(categories).count == tools.count)
        #expect(categories.allSatisfy { !$0.contains(" ") && $0 != "History" })
        #expect(ToolID.largeFiles.loggerCategory == "LargeFiles" && ToolID.history.loggerCategory == "Restore")
    }
}
