import Testing

@testable import ShuckKit

struct ShuckKitTests {
    @Test func loggerSubsystemIsTheBundleID() {
        #expect(ShuckKit.loggerSubsystem == "me.nutabi.shuck")
    }

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

    /// Each method is logged as its own operation, so a plan that mixes methods says what was done to each item.
    @Test func everyMethodHasTheOperationOfTheSameName() {
        for method in ActionMethod.allCases {
            #expect(HistoryRecord.Operation(method).rawValue == method.rawValue)
        }
    }
}
