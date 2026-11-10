import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Where Developer Junk finds a tool and the command it builds (DEV-002, DEV-004, D-124).
struct ToolLocationsTests {
    let root: FixtureRoot

    init() throws {
        root = try FixtureRoot()
    }

    private func locations(toolRoot: URL?) -> ToolLocations? {
        ToolLocations(ScanContext(home: root.url, protection: root.pathGuardConfiguration(), toolRoot: toolRoot))
    }

    @Test func aScanWithoutAToolRootLooksForNoToolsDEV002() {
        #expect(locations(toolRoot: nil) == nil)
        #expect(locations(toolRoot: root.url) != nil)
    }

    @Test func aToolIsFoundUnderTheToolRootInTheFirstFolderWhereItRunsDEV002() throws {
        let locations = try #require(locations(toolRoot: root.url))
        let folders = ToolLocations.homebrewFolders
        #expect(locations.executable("npm", in: folders) == root.url.appending(path: "opt/homebrew/bin/npm").path)

        let second = try root.tool("usr/local/bin/npm", .exits(0))
        #expect(locations.executable("npm", in: folders) == second.path)
        // Where it runs first wins; a file that cannot run does not count.
        let first = try root.tool("opt/homebrew/bin/npm", .exits(0))
        #expect(locations.executable("npm", in: folders) == first.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: first.path)
        #expect(locations.executable("npm", in: folders) == second.path)
    }

    @Test func aCommandHasOnlyAPathAndAHomeFolderInItsEnvironmentDEV004() throws {
        let locations = try #require(locations(toolRoot: root.url))
        let tool = locations.executable("pip3", in: ToolLocations.homebrewFolders)
        let command = try locations.command(tool, ["cache", "purge"])

        #expect(command.executable == tool)
        #expect(command.arguments == ["cache", "purge"])
        #expect(Set(command.environment.keys) == [ToolLocations.pathVariable, ToolLocations.homeVariable])
        #expect(command.environment[ToolLocations.homeVariable] == root.url.path)
        #expect(command.environment[ToolLocations.pathVariable] == ToolLocations.searchPath)
        #expect(throws: RuleError.invalidDetection) { try locations.command("relative", []) }
    }
}
