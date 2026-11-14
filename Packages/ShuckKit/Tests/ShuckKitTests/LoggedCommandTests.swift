import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// A tool run's command and output as History reads them back from the log (HIS-002, SAF-006, #63, D-115).
struct LoggedCommandTests {
    private func command(_ arguments: [String]) throws -> ToolCommand {
        try ToolCommand(executable: "/usr/bin/xcrun", arguments: arguments, environment: ["PATH": "/usr/bin"])
    }

    @Test func aCommandReadsBackFromItsDisplayFormHIS002() throws {
        let command = try command(["simctl", "delete", "unavailable"])
        let logged = try #require(LoggedCommand(logged: command.display))

        #expect(logged.executable == "/usr/bin/xcrun")
        #expect(logged.arguments == ["simctl", "delete", "unavailable"])
        #expect(logged.tool == "xcrun")
        #expect(logged.commandLine == "xcrun simctl delete unavailable")

        // A quote and spaces in an argument survive the round trip.
        let quoted = try self.command(["it's here", "a b"])
        #expect(LoggedCommand(logged: quoted.display)?.arguments == ["it's here", "a b"])
    }

    @Test func textThatIsNotAQuotedCommandIsNotOne() {
        #expect(LoggedCommand(logged: "/Users/someone/Movies/clip.mov") == nil)
        #expect(LoggedCommand(logged: "com.example.agent") == nil)
        #expect(LoggedCommand(logged: "") == nil)
        #expect(LoggedCommand(logged: "'/usr/bin/xcrun' 'unfinished") == nil)
        #expect(LoggedCommand(logged: "'relative/tool'") == nil)
    }

    @Test func aToolsOutputIsKeptApartFromItsOutcomeHIS002() async throws {
        let root = try FixtureRoot()
        let log = try HistoryLog(folder: root.historyFolder)
        let run = UUID()
        let path = try command(["simctl", "delete", "unavailable"]).display
        let details = ["exit 0; output: Removed 2", "ShuckToolExit 1: exit status 1; output: …cache is locked"]
        for (index, detail) in details.enumerated() {
            let status: HistoryRecord.Status = index == 0 ? .ok : .failed
            let item = path + " \(index)"
            try await log.append(
                .intent(run: run, tool: .developerJunk, operation: .tool, path: item, tier: .rebuildable))
            try await log.append(
                .result(
                    run: run, tool: .developerJunk, operation: .tool, path: item, tier: .rebuildable,
                    status: status, detail: detail))
        }

        let items = try #require(try HistoryLog.read(folder: root.historyFolder).runs().first).items
        #expect(items.map(\.outcome) == [.succeeded, .failed("ShuckToolExit 1: exit status 1")])
        #expect(items.map(\.toolOutput) == ["Removed 2", "…cache is locked"])
    }
}
